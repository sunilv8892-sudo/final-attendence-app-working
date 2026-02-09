import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../database/database_manager.dart';
import '../models/face_detection_model.dart';
import '../models/student_model.dart';
import '../models/attendance_model.dart';
import '../modules/m1_face_detection.dart' as face_detection_module;
import '../modules/m2_face_embedding.dart';
import '../utils/constants.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  CameraController? _controller;
  late face_detection_module.FaceDetectionModule _faceDetector;
  late FaceEmbeddingModule _faceEmbedder;
  late FlutterTts _flutterTts;
  List<CameraDescription> _availableCameras = [];
  late CameraDescription _currentCamera;
  late DatabaseManager _dbManager;

  List<Student> _enrolledStudents = [];
  final Map<int, List<List<double>>> _studentEmbeddings = {};
  bool _isProcessing = false;
  bool _isScanning = false;
  final Map<int, AttendanceStatus> _attendanceStatus = {};
  DateTime? _attendanceDate;
  double _similarityThreshold = 0.85;  // High threshold (85%) for max accuracy
  final Map<int, DateTime> _lastDetectionTime = {}; // Prevent duplicate detections
  static const Duration _detectionCooldown = Duration(seconds: 3);
  
  // Multiple consecutive detection tracking
  int? _lastDetectedStudentId;
  int _consecutiveDetections = 0;
  static const int _requiredConsecutiveDetections = 3; // Require 3 consecutive matches for extra safety

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.dispose();
    _faceEmbedder.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      // Load similarity threshold from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _similarityThreshold = prefs.getDouble('similarity_threshold') ?? 0.85;
      debugPrint('📊 Loaded similarity threshold: $_similarityThreshold');

      _dbManager = DatabaseManager();
      await _dbManager.database;
      // Initialize text-to-speech
      _flutterTts = FlutterTts();
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      debugPrint('🔊 Text-to-Speech initialized');
      // Initialize modules
      _faceDetector = face_detection_module.FaceDetectionModule();
      await _faceDetector.initialize();

      _faceEmbedder = FaceEmbeddingModule();
      await _faceEmbedder.initialize();

      // Load enrolled students and their embeddings
      _enrolledStudents = await _dbManager.getAllStudents();
      debugPrint('📚 Loaded ${_enrolledStudents.length} enrolled students');

      for (final student in _enrolledStudents) {
        final embeddings = await _dbManager.getEmbeddingsForStudent(
          student.id!,
        );
        // embeddings are already parsed from JSON to List<double> by database_manager
        _studentEmbeddings[student.id!] =
            embeddings.map((e) => e.vector).toList();
        debugPrint('   ${student.name}: ${embeddings.length} embeddings');
      }

      _attendanceDate = DateTime.now();
      // Normalize to midnight (no time component) for consistent date matching
      _attendanceDate = DateTime(_attendanceDate!.year, _attendanceDate!.month, _attendanceDate!.day);
      await _initCamera();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        debugPrint('❌ Camera permission denied');
        return;
      }
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) return;

      _currentCamera = _availableCameras.first;
      final preferredCamera = _availableCameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _availableCameras.first,
      );
      await _initCameraFor(preferredCamera);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  Future<void> _initCameraFor(CameraDescription camera) async {
    try {
      await _controller?.dispose();
      _currentCamera = camera;
      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Init camera error: $e');
    }
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2) return;
    
    final nextCamera = _availableCameras.lastWhere(
      (camera) => camera.lensDirection != _currentCamera.lensDirection,
      orElse: () => _availableCameras.first,
    );
    
    _currentCamera = nextCamera;
    await _initCameraFor(nextCamera);
    debugPrint('Switched to ${nextCamera.lensDirection.toString()} camera');
  }

  Future<void> _scanFace() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final rawImage = img.decodeImage(bytes);

      if (rawImage != null) {
        debugPrint('📸 Scanning face: ${rawImage.width}x${rawImage.height}');

        // Detect face
        final detections = await _detectFaceWithMlKit(bytes);
        if (detections.isEmpty) {
          debugPrint('❌ No face detected');
          return;
        }

        // Take largest face
        detections.sort(
          (a, b) => (b.width * b.height).compareTo(a.width * a.height),
        );
        final face = detections.first;

        // Validate face size (must be at least 80x80)
        if (face.width < 80 || face.height < 80) {
          debugPrint('⚠️ Face too small: ${face.width.toInt()}x${face.height.toInt()}');
          _consecutiveDetections = 0;
          _lastDetectedStudentId = null;
          if (mounted) setState(() {});
          return;
        }

        // Crop and generate embedding
        final croppedFace = _cropFace(rawImage, face);
        final embedding = await _generateEmbedding(croppedFace);

        if (embedding.isEmpty) {
          debugPrint('❌ Failed to generate embedding');
          _consecutiveDetections = 0;
          _lastDetectedStudentId = null;
          if (mounted) setState(() {});
          return;
        }

        // Find matching student with similarity check
        final match = _findMatchingStudent(embedding);
        if (match != null) {
          // Check if it's the same person as last detection
          if (match.id == _lastDetectedStudentId) {
            _consecutiveDetections++;
          } else {
            // Different person, reset counter and start new sequence
            _consecutiveDetections = 1;
            _lastDetectedStudentId = match.id;
          }

          // If we have enough consecutive detections, mark attendance
          if (_consecutiveDetections >= _requiredConsecutiveDetections) {
            final now = DateTime.now();
            final lastTime = _lastDetectionTime[match.id] ?? DateTime(2000);
            
            if (now.difference(lastTime) >= _detectionCooldown) {
              debugPrint('✅ ${match.name} marked present (confirmed)');
              _lastDetectionTime[match.id!] = now;
              _consecutiveDetections = 0;
              _lastDetectedStudentId = null;
              
              if (mounted) {
                setState(() {
                  _attendanceStatus[match.id!] = AttendanceStatus.present;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ ${match.name} marked present'),
                    backgroundColor: Colors.green,
                    duration: const Duration(milliseconds: 800),
                  ),
                );
                // Speak the attendance confirmation
                _speakAttendanceConfirmation(match.name);
              }
            }
          } else {
            if (mounted) setState(() {});
          }
        } else {
          _consecutiveDetections = 0;
          _lastDetectedStudentId = null;
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _startContinuousScanning() async {
    if (_isScanning) return;
    _isScanning = true;
    if (mounted) setState(() {});

    try {
      while (_isScanning) {
        if (!_isProcessing) {
          await _scanFace();
        }
        await Future.delayed(const Duration(milliseconds: 800));
      }
    } finally {
      _isScanning = false;
      if (mounted) setState(() {});
    }
  }

  void _stopScanning() {
    _isScanning = false;
    if (mounted) setState(() {});
  }

  Future<List<DetectedFace>> _detectFaceWithMlKit(Uint8List imageBytes) async {
    try {
      final faces = await _faceDetector.detectFaces(imageBytes);
      return faces
          .map(
            (face) => DetectedFace(
              x: face.boundingBox.left.toDouble(),
              y: face.boundingBox.top.toDouble(),
              width: face.boundingBox.width.toDouble(),
              height: face.boundingBox.height.toDouble(),
              confidence: 1.0,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('Face detection error: $e');
      return [];
    }
  }

  img.Image _cropFace(img.Image fullImage, DetectedFace face) {
    final x = face.x.toInt().clamp(0, fullImage.width - 1);
    final y = face.y.toInt().clamp(0, fullImage.height - 1);
    final w = face.width.toInt().clamp(1, fullImage.width - x);
    final h = face.height.toInt().clamp(1, fullImage.height - y);
    return img.copyCrop(fullImage, x: x, y: y, width: w, height: h);
  }

  Future<List<double>> _generateEmbedding(img.Image faceImage) async {
    try {
      final faceBytes = Uint8List.fromList(img.encodeJpg(faceImage));
      final embedding = await _faceEmbedder.generateEmbedding(faceBytes);
      return embedding ?? [];
    } catch (e) {
      debugPrint('Embedding generation error: $e');
      return [];
    }
  }

  Future<void> _speakAttendanceConfirmation(String studentName) async {
    try {
      final message = "$studentName's attendance marked successfully";
      await _flutterTts.speak(message);
      debugPrint('🔊 Speaking: $message');
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  Student? _findMatchingStudent(List<double> embedding) {
    double bestSimilarity = 0.0;
    Student? bestMatch;

    for (final student in _enrolledStudents) {
      final studentEmbeddings = _studentEmbeddings[student.id] ?? [];
      for (final studentEmb in studentEmbeddings) {
        final similarity = _cosineSimilarity(embedding, studentEmb);
        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          bestMatch = student;
        }
      }
    }

    debugPrint(
      '🔍 Best match: ${bestMatch?.name} (similarity: ${bestSimilarity.toStringAsFixed(3)}) [threshold: ${_similarityThreshold.toStringAsFixed(2)}]',
    );
    return bestSimilarity > _similarityThreshold ? bestMatch : null;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    final denominator = _sqrt(normA) * _sqrt(normB);
    return denominator == 0 ? 0.0 : dotProduct / denominator;
  }

  double _sqrt(double x) {
    if (x == 0) return 0;
    double z = x;
    double result = 0;
    while ((z - result).abs() > 1e-7) {
      result = z;
      z = 0.5 * (z + x / z);
    }
    return z;
  }

  Future<void> _submitAttendance() async {
    if (_attendanceStatus.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No attendance marked')));
      return;
    }

    try {
      int submitted = 0;
      for (final entry in _attendanceStatus.entries) {
        await _dbManager.insertAttendance(
          AttendanceRecord(
            studentId: entry.key,
            date: _attendanceDate!,
            time: '${DateTime.now().hour}:${DateTime.now().minute}',
            status: entry.value,
            recordedAt: DateTime.now(),
          ),
        );
        submitted++;
      }
      debugPrint('✅ Attendance submitted for $submitted students');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Attendance submitted for $submitted students'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Submit error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _controller != null && _controller!.value.isInitialized;
    final markedCount = _attendanceStatus.values
        .where((s) => s == AttendanceStatus.present)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        elevation: 0,
        actions: [
          if (markedCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: ColorSchemes.presentColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '✓ $markedCount Marked',
                    style: const TextStyle(
                      color: ColorSchemes.presentColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppConstants.backgroundGradient,
        ),
        child: Column(
          children: [
            // Camera Preview Section
            if (isReady)
              Expanded(
                flex: 3,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(AppConstants.paddingMedium),
                    constraints: const BoxConstraints(
                      maxWidth: 500,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppConstants.borderRadiusLarge,
                      ),
                      border: Border.all(
                        color: _attendanceStatus.containsValue(AttendanceStatus.present)
                            ? Colors.green
                            : AppConstants.cardBorder,
                        width: _attendanceStatus.containsValue(AttendanceStatus.present) ? 3 : 2,
                      ),
                      boxShadow: [AppConstants.cardShadow],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppConstants.borderRadiusLarge,
                      ),
                      child: Stack(
                        children: [
                          CameraPreview(_controller!),
                          // Processing Overlay
                          if (_isProcessing)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(102),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppConstants.primaryColor,
                                      ),
                                    ),
                                    SizedBox(height: AppConstants.paddingMedium),
                                    Text(
                                      'Scanning face...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // Scan Status Badge
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _isScanning
                                    ? ColorSchemes.presentColor
                                    : Colors.grey,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(77),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isScanning ? 'Scanning' : 'Ready',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Camera Switch Button
                          if (_availableCameras.length > 1)
                            Positioned(
                              top: 12,
                              left: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(153),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  onPressed: _switchCamera,
                                  icon: const Icon(
                                    Icons.cameraswitch,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                flex: 3,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(AppConstants.paddingMedium),
                    constraints: const BoxConstraints(
                      maxWidth: 500,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        AppConstants.borderRadiusLarge,
                      ),
                      border: Border.all(
                        color: AppConstants.cardBorder,
                        width: 2,
                      ),
                      color: AppConstants.cardColor,
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: AppConstants.paddingMedium),
                          Text(
                            'Initializing Camera...',
                            style: TextStyle(
                              color: AppConstants.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Student List Section
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingMedium,
                  vertical: AppConstants.paddingSmall,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    AppConstants.borderRadiusLarge,
                  ),
                  border: Border.all(color: AppConstants.cardBorder),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    AppConstants.borderRadiusLarge,
                  ),
                  child: _enrolledStudents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_off,
                                size: 48,
                                color: AppConstants.textTertiary,
                              ),
                              const SizedBox(
                                height: AppConstants.paddingMedium,
                              ),
                              const Text(
                                'No enrolled students',
                                style: TextStyle(
                                  color: AppConstants.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _enrolledStudents.length,
                          separatorBuilder: (context, index) => Container(
                            height: 1,
                            color: AppConstants.cardBorder,
                          ),
                          itemBuilder: (context, index) {
                            final student = _enrolledStudents[index];
                            final status = _attendanceStatus[student.id];
                            final isPresent =
                                status == AttendanceStatus.present;
                            return InkWell(
                              onTap: () {
                                setState(() {
                                  if (isPresent) {
                                    _attendanceStatus.remove(student.id);
                                  } else {
                                    _attendanceStatus[student.id!] =
                                        AttendanceStatus.present;
                                  }
                                });
                              },
                              child: Container(
                                color: isPresent
                                    ? ColorSchemes.presentColor.withAlpha(26)
                                    : AppConstants.cardColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppConstants.paddingMedium,
                                  vertical: AppConstants.paddingSmall,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: isPresent
                                            ? ColorSchemes.presentColor
                                            : AppConstants.inputFill,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        isPresent
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        color: isPresent
                                            ? Colors.white
                                            : AppConstants.textTertiary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(
                                      width: AppConstants.paddingMedium,
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            student.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            '${student.rollNumber} • ${student.className}',
                                            style: const TextStyle(
                                              color: AppConstants.textTertiary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isPresent)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: ColorSchemes.presentColor,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: const Text(
                                          'Present',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppConstants.secondaryColor,
          border: Border(top: BorderSide(color: AppConstants.cardBorder)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(77),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          AppConstants.paddingMedium,
          AppConstants.paddingMedium,
          AppConstants.paddingMedium,
          AppConstants.paddingMedium + MediaQuery.of(context).padding.bottom,
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isScanning
                    ? _stopScanning
                    : _startContinuousScanning,
                icon: Icon(_isScanning ? Icons.stop_circle : Icons.videocam),
                label: Text(
                  _isScanning ? 'Stop' : 'Scan',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isScanning
                      ? AppConstants.warningColor
                      : AppConstants.primaryColor,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.paddingMedium),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _submitAttendance,
                icon: const Icon(Icons.check_circle),
                label: const Text(
                  'Submit',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: markedCount > 0
                      ? ColorSchemes.presentColor
                      : AppConstants.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom Painter for Face Detection Bounding Box (Spider-Man Mask Style)

