import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../database/database_manager.dart';
import '../models/face_detection_model.dart';
import '../models/student_model.dart';
import '../models/embedding_model.dart';
import '../modules/m1_face_detection.dart' as face_detection_module;
import '../modules/m2_face_embedding.dart';
import '../utils/constants.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _classController = TextEditingController();

  CameraController? _controller;
  late face_detection_module.FaceDetectionModule _faceDetector;
  late FaceEmbeddingModule _faceEmbedder;
  List<CameraDescription> _availableCameras = [];
  CameraDescription? _currentCamera;
  late DatabaseManager _dbManager;

  int _capturedSamples = 0;
  final List<List<double>> _embeddings = [];
  bool _isCapturing = false;
  bool _autoCapturing = false;
  bool _embedderReady = false;

  // Performance tracking
  int _embeddingDim = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceEmbedder.dispose();
    _faceDetector.dispose();
    _nameController.dispose();
    _rollController.dispose();
    _classController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _dbManager = DatabaseManager();
      await _dbManager.database;

      // Initialize modules
      _faceDetector = face_detection_module.FaceDetectionModule();
      await _faceDetector.initialize();

      _faceEmbedder = FaceEmbeddingModule();
      await _faceEmbedder.initialize();
      _embeddingDim = FaceEmbeddingModule.embeddingDimension;
      _embedderReady = _faceEmbedder.isReady;
      if (!_embedderReady) {
        throw Exception('AdaFace-Mobile interpreter failed to initialize');
      }

      debugPrint(
        '✅ Face recognition modules initialized (${_embeddingDim}D embeddings)',
      );

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
      // Request camera permission
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        debugPrint('❌ Camera permission denied');
        return;
      }
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) return;

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
      // Track current camera description for later use
      // Note: lens direction & sensor orientation not stored to keep state minimal
      // (overlay mirroring handled in attendance screen via painter parameters)
      _currentCamera = camera;

      await _controller?.dispose();
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
    if (_availableCameras.length < 2 || _currentCamera == null) return;
    final currentIndex = _availableCameras.indexOf(_currentCamera!);
    final nextIndex = (currentIndex + 1) % _availableCameras.length;
    final nextCamera = _availableCameras[nextIndex];
    await _initCameraFor(nextCamera);
  }

  Future<void> _captureFaceSample() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isCapturing) return;

    _isCapturing = true;

    try {
      final image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final rawImage = img.decodeImage(bytes);

      if (rawImage != null) {
        debugPrint(
          '📸 Captured image for enrollment: ${rawImage.width}x${rawImage.height}',
        );

        // Step 1: Detect face using ML Kit to ensure alignment with attendance screen
        final detections = await _detectFaceWithMlKit(bytes);

        if (detections.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ No face detected. Please face the camera.'),
              ),
            );
          }
          return;
        }

        // Take the largest detected face
        detections.sort(
          (a, b) => (b.width * b.height).compareTo(a.width * a.height),
        );
        final face = detections.first;

        // Strict quality check for enrollment: require large, clear face
        if (face.width < 150 || face.height < 150) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '❌ Face too small! (${face.width.toInt()}x${face.height.toInt()})\n'
                  'Please move closer to camera. Need at least 150x150px',
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Check if face is centered (not too far to edges)
        final imageCenterX = rawImage.width / 2;
        final imageCenterY = rawImage.height / 2;
        final faceCenterX = face.x + (face.width / 2);
        final faceCenterY = face.y + (face.height / 2);
        
        final distanceFromCenter = 
            ((imageCenterX - faceCenterX).abs() + (imageCenterY - faceCenterY).abs()) / 2;
        final maxDeviation = rawImage.width * 0.25; // Allow 25% deviation from center
        
        if (distanceFromCenter > maxDeviation) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Face not centered. Please center your face in the frame.'),
                duration: Duration(seconds: 1),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        debugPrint('✅ Face quality check passed: ${face.width.toInt()}x${face.height.toInt()}');

        // Step 2: Crop face (Identical logic to Attendance screen)
        final croppedFace = _cropFace(rawImage, face);

        // Step 3: Generate embedding using MobileFaceNet
        final embedding = await _generateEmbedding(croppedFace);
        debugPrint('🧠 Generated embedding: ${embedding.length} dimensions');
        debugPrint('   Values: ${embedding.take(5).toList()}...');

        if (embedding.isNotEmpty) {
          _embeddings.add(embedding);
          debugPrint('✅ Added embedding #${_embeddings.length} to list');

          if (mounted) {
            setState(() => _capturedSamples++);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Sample $_capturedSamples captured (${embedding.length}D)'),
                duration: const Duration(milliseconds: 500),
                backgroundColor: AppConstants.primaryColor,
              ),
            );
          }
        } else {
          debugPrint('❌ Embedding is empty!');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Failed to generate embedding'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Capture error: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _startAutoCapture() async {
    if (_autoCapturing) return;
    _autoCapturing = true;
    if (mounted) setState(() {});

    try {
      while (_autoCapturing &&
          _capturedSamples < AppConstants.requiredEnrollmentSamples) {
        // If a capture is already in progress, wait a short while
        if (_isCapturing) {
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }

        await _captureFaceSample();

        // Small delay between captures to allow user/head movement
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } finally {
      _autoCapturing = false;
      if (mounted) setState(() {});
    }
  }

  void _stopAutoCapture() {
    _autoCapturing = false;
    if (mounted) setState(() {});
  }

  Future<List<DetectedFace>> _detectFaceWithMlKit(Uint8List imageBytes) async {
    try {
      final faces = await _faceDetector.detectFaces(imageBytes);

      // Convert to legacy DetectedFace format for compatibility
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

  // Enrollment uses ML Kit for detection; NMS not required
  img.Image _cropFace(img.Image fullImage, DetectedFace face) {
    final x = face.x.toInt().clamp(0, fullImage.width - 1);
    final y = face.y.toInt().clamp(0, fullImage.height - 1);
    final w = face.width.toInt().clamp(1, fullImage.width - x);
    final h = face.height.toInt().clamp(1, fullImage.height - y);
    debugPrint('Cropping face at ($x, $y) with size ($w x $h) from ${fullImage.width}x${fullImage.height}');
    return img.copyCrop(fullImage, x: x, y: y, width: w, height: h);
  }

  Future<List<double>> _generateEmbedding(img.Image faceImage) async {
    try {
      debugPrint('🔄 Generating embedding from face ${faceImage.width}x${faceImage.height}');
      // Convert to bytes for the embedding module
      final faceBytes = Uint8List.fromList(img.encodeJpg(faceImage));
      debugPrint('   Encoded to ${faceBytes.length} bytes');
      final embedding = await _faceEmbedder.generateEmbedding(faceBytes);
      if (embedding == null) {
        debugPrint('❌ Embedding generation returned null');
        return [];
      }
      debugPrint('✅ Embedding generated: ${embedding.length}D vector');
      return embedding;
    } catch (e) {
      debugPrint('❌ Embedding generation error: $e');
      return [];
    }
  }

  Future<void> _saveStudent() async {
    if (_nameController.text.isEmpty ||
        _rollController.text.isEmpty ||
        _classController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }

    if (_embeddings.length < AppConstants.requiredEnrollmentSamples) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Need ${AppConstants.requiredEnrollmentSamples} samples. Have ${_embeddings.length}',
          ),
        ),
      );
      return;
    }

    try {
      debugPrint('💾 Saving student with ${_embeddings.length} embeddings');
      // Insert student
      final student = Student(
        name: _nameController.text,
        rollNumber: _rollController.text,
        className: _classController.text,
        enrollmentDate: DateTime.now(),
      );
      debugPrint('   Name: ${student.name}, Roll: ${student.rollNumber}, Class: ${student.className}');

      final studentId = await _dbManager.insertStudent(student);
      debugPrint('   ✅ Student inserted with ID: $studentId');

      // Insert embeddings
      for (var i = 0; i < _embeddings.length; i++) {
        final embedding = _embeddings[i];
        await _dbManager.insertEmbedding(
          FaceEmbedding(
            studentId: studentId,
            vector: embedding,
            captureDate: DateTime.now(),
          ),
        );
        debugPrint('   ✅ Embedding $i inserted (${embedding.length}D)');
      }
      debugPrint('✅ Student enrolled successfully!');
      
      // Verify data was actually saved
      final savedStudent = await _dbManager.getStudentById(studentId);
      if (savedStudent != null) {
        debugPrint('🔍 VERIFICATION: Student found in database!');
        debugPrint('   ID: ${savedStudent.id}');
        debugPrint('   Name: ${savedStudent.name}');
        debugPrint('   Roll: ${savedStudent.rollNumber}');
        debugPrint('   Class: ${savedStudent.className}');
        
        // Verify embeddings were saved
        final savedEmbeddings = await _dbManager.getEmbeddingsForStudent(studentId);
        debugPrint('   Embeddings saved: ${savedEmbeddings.length}');
        for (var i = 0; i < savedEmbeddings.length; i++) {
          debugPrint('      Embedding $i: ${savedEmbeddings[i].vector.length}D');
        }
        
        final allStudents = await _dbManager.getAllStudents();
        debugPrint('   Total students in DB: ${allStudents.length}');
      } else {
        debugPrint('❌ VERIFICATION FAILED: Student NOT found after insert!');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Student enrolled successfully!')),
        );
        _nameController.clear();
        _rollController.clear();
        _classController.clear();
        setState(() {
          _capturedSamples = 0;
          _embeddings.clear();
        });
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('❌ Save error: $e');
      if (mounted) {
        String errorMsg = 'Error: $e';
        if (e.toString().contains('UNIQUE')) {
          errorMsg = 'Roll number already exists!';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _controller != null && _controller!.value.isInitialized;
    final canCapture = isReady && _embedderReady;

    return Scaffold(
      appBar: AppBar(title: const Text('Enroll Student')),
      body: Container(
        decoration: const BoxDecoration(gradient: AppConstants.backgroundGradient),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Student Information Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.paddingLarge),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withAlpha(26),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.person_add,
                              color: AppConstants.primaryColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: AppConstants.paddingMedium),
                          const Text(
                            'Student Information',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.paddingLarge),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          hintText: 'Enter student name',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.borderRadius,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppConstants.paddingMedium),
                      TextField(
                        controller: _rollController,
                        decoration: InputDecoration(
                          labelText: 'Roll Number',
                          hintText: 'e.g., 21CS01',
                          prefixIcon: const Icon(Icons.numbers),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.borderRadius,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppConstants.paddingMedium),
                      TextField(
                        controller: _classController,
                        decoration: InputDecoration(
                          labelText: 'Class/Section',
                          hintText: 'e.g., CSE-A',
                          prefixIcon: const Icon(Icons.school),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.borderRadius,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Camera Preview Section
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
                    border: Border.all(color: AppConstants.cardBorder, width: 2),
                  ),
                  constraints: const BoxConstraints(
                    maxWidth: 500,
                    maxHeight: 450,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
                    child: Container(
                      color: AppConstants.secondaryColor,
                      child: !isReady
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: AppConstants.paddingMedium),
                                Text(
                                  'Initializing Camera...',
                                  style: TextStyle(
                                    color: AppConstants.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Stack(
                            children: [
                              CameraPreview(_controller!),
                              // Camera Switch Button
                              if (_availableCameras.length > 1)
                                Positioned(
                                  right: 12,
                                  top: 12,
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
                              // Status Indicator
                              Positioned(
                                bottom: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withAlpha(153),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppConstants.successColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        'Camera Ready',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Progress Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.paddingLarge),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Enrollment Progress',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_capturedSamples/${AppConstants.requiredEnrollmentSamples}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppConstants.primaryColor,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.paddingMedium),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _capturedSamples /
                              AppConstants.requiredEnrollmentSamples,
                          minHeight: 10,
                          backgroundColor: AppConstants.inputFill,
                          valueColor: AlwaysStoppedAnimation(
                            _capturedSamples >=
                                    AppConstants.requiredEnrollmentSamples
                                ? AppConstants.successColor
                                : AppConstants.primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppConstants.paddingSmall),
                      if (_capturedSamples <
                          AppConstants.requiredEnrollmentSamples)
                        Text(
                          'Capture ${AppConstants.requiredEnrollmentSamples - _capturedSamples} more samples',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppConstants.textTertiary,
                          ),
                        )
                      else
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppConstants.successColor,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Ready to save!',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppConstants.successColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              if (!_embedderReady)
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppConstants.paddingMedium,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(AppConstants.paddingMedium),
                    decoration: BoxDecoration(
                      color: AppConstants.errorColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                      border: Border.all(
                        color: AppConstants.errorColor.withAlpha(77),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning,
                          color: AppConstants.errorColor,
                          size: 20,
                        ),
                        const SizedBox(width: AppConstants.paddingSmall),
                        Expanded(
                          child: Text(
                            'Face embedding model unavailable. Check logs.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppConstants.errorLight,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Action Buttons
              ElevatedButton.icon(
                onPressed: canCapture && !_autoCapturing
                    ? () => _startAutoCapture()
                    : (_autoCapturing ? () => _stopAutoCapture() : null),
                icon: Icon(_autoCapturing ? Icons.stop_circle : Icons.videocam),
                label: Text(
                  _autoCapturing ? 'Stop Capture' : 'Start Auto Capture',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: AppConstants.paddingSmall),

              ElevatedButton.icon(
                onPressed:
                    _capturedSamples >=
                            AppConstants.requiredEnrollmentSamples &&
                        _embedderReady
                        ? _saveStudent
                        : null,
                icon: const Icon(Icons.check_circle),
                label: const Text(
                  'Save Student',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: AppConstants.paddingSmall),

              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),
            ],
          ),
        ),
      ),
    );
  }
}
