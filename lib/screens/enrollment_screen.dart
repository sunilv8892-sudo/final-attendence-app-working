import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../database/database_manager.dart';
import '../models/student_model.dart';
import '../models/embedding_model.dart';
import '../models/face_detection_model.dart';
import '../utils/constants.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({Key? key}) : super(key: key);

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final _nameController = TextEditingController();
  final _rollController = TextEditingController();
  final _classController = TextEditingController();

  CameraController? _controller;
  Interpreter? _faceNetInterpreter;
  Interpreter? _yoloInterpreter;
  late DatabaseManager _dbManager;

  int _capturedSamples = 0;
  List<List<double>> _embeddings = [];
  bool _isCapturing = false;
  
  // YOLO Constants (Aligned with Attendance Screen)
  static const int _yoloInputSize = 640;
  static const int _yoloOutputBoxes = 8400;
  static const int _yoloOutputAttributes = 5; // [x, y, w, h, confidence]
  static const double _yoloConfidenceThreshold = 0.45;
  static const double _yoloIouThreshold = 0.45;

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
    _faceNetInterpreter?.close();
    _yoloInterpreter?.close();
    _nameController.dispose();
    _rollController.dispose();
    _classController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _dbManager = DatabaseManager();
      await _dbManager.database;

      // Load FaceNet
      _faceNetInterpreter = await Interpreter.fromAsset('assets/models/embedding_model.tflite');
      final outputShape = _faceNetInterpreter!.getOutputTensor(0).shape;
      _embeddingDim = outputShape.last;
      debugPrint('✅ MobileFaceNet loaded for enrollment (${_embeddingDim}D embeddings)');

      // Load YOLO for face cropping alignment
      _yoloInterpreter = await Interpreter.fromAsset('assets/models/model.tflite');
      debugPrint('✅ YOLO loaded for enrollment cropping');

      await _initCamera();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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

      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      // Find front camera (selfie camera)
      CameraDescription? frontCamera;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
          break;
        }
      }
      
      final selectedCamera = frontCamera ?? cameras.first;
      debugPrint('📷 Enrollment using camera: ${selectedCamera.name} (${selectedCamera.lensDirection})');

      // Use Medium resolution for performance (alignment with attendance)
      _controller = CameraController(
        selectedCamera, 
        ResolutionPreset.medium, 
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Camera error: $e');
    }
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
        debugPrint('📸 Captured image for enrollment: ${rawImage.width}x${rawImage.height}');
        
        // Step 1: Detect face to ensure alignment with attendance screen
        final detections = await _runYoloOnImage(rawImage);
        
        if (detections.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❌ No face detected. Please face the camera.')),
            );
          }
          return;
        }

        // Take the largest detected face
        detections.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
        final face = detections.first;
        
        // Step 2: Crop face (Identical logic to Attendance screen)
        final croppedFace = _cropFace(rawImage, face);
        
        // Step 3: Generate embedding using MobileFaceNet
        final embedding = await _generateEmbedding(croppedFace);

        if (embedding.isNotEmpty) {
          _embeddings.add(embedding);
          
          if (mounted) {
            setState(() => _capturedSamples++);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Sample ${_capturedSamples} captured'),
                duration: const Duration(milliseconds: 500),
                backgroundColor: AppConstants.goldButtonColor,
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

  Future<List<DetectedFace>> _runYoloOnImage(img.Image image) async {
    if (_yoloInterpreter == null) return [];

    try {
      // Resize to 640x640 for YOLO
      final resized = img.copyResize(image, width: _yoloInputSize, height: _yoloInputSize);
      
      final input = Float32List(1 * _yoloInputSize * _yoloInputSize * 3);
      int index = 0;
      for (int y = 0; y < _yoloInputSize; y++) {
        for (int x = 0; x < _yoloInputSize; x++) {
          final pixel = resized.getPixel(x, y);
          input[index++] = pixel.r.toDouble() / 255.0;
          input[index++] = pixel.g.toDouble() / 255.0;
          input[index++] = pixel.b.toDouble() / 255.0;
        }
      }

      final inputTensor = input.reshape([1, _yoloInputSize, _yoloInputSize, 3]);
      final output = List.filled(1 * _yoloOutputAttributes * _yoloOutputBoxes, 0.0)
          .reshape([1, _yoloOutputAttributes, _yoloOutputBoxes]);
      
      _yoloInterpreter!.run(inputTensor, output);
      
      return _parseYoloOutput(output, image.width, image.height);
    } catch (e) {
      debugPrint('YOLO inference error: $e');
      return [];
    }
  }

  List<DetectedFace> _parseYoloOutput(List output, int imageWidth, int imageHeight) {
    List<DetectedFace> detections = [];
    final batch = output[0] as List<dynamic>;
    
    final attrLists = List<List<dynamic>>.generate(
      _yoloOutputAttributes,
      (index) => batch[index] as List<dynamic>
    );

    for (int i = 0; i < _yoloOutputBoxes; i++) {
        final double confidence = _toDouble(attrLists[4][i]);
        if (confidence < _yoloConfidenceThreshold) continue;

        final double cx = _toDouble(attrLists[0][i]);
        final double cy = _toDouble(attrLists[1][i]);
        final double w = _toDouble(attrLists[2][i]);
        final double h = _toDouble(attrLists[3][i]);

        double x = (cx * imageWidth) - (w * imageWidth / 2.0);
        double y = (cy * imageHeight) - (h * imageHeight / 2.0);
        double pixelW = w * imageWidth;
        double pixelH = h * imageHeight;

        detections.add(DetectedFace(
          x: x,
          y: y,
          width: pixelW,
          height: pixelH,
          confidence: confidence,
        ));
    }

    return _applyNonMaxSuppression(detections, _yoloIouThreshold);
  }

  List<DetectedFace> _applyNonMaxSuppression(List<DetectedFace> candidates, double iouThreshold) {
    final sorted = List<DetectedFace>.from(candidates)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final List<DetectedFace> selected = [];

    for (final candidate in sorted) {
      bool shouldKeep = true;
      for (final existing in selected) {
        if (_intersectionOverUnion(existing, candidate) > iouThreshold) {
          shouldKeep = false;
          break;
        }
      }
      if (shouldKeep) selected.add(candidate);
    }
    return selected;
  }

  double _intersectionOverUnion(DetectedFace a, DetectedFace b) {
    final double left = math.max(a.x, b.x);
    final double top = math.max(a.y, b.y);
    final double right = math.min(a.x + a.width, b.x + b.width);
    final double bottom = math.min(a.y + a.height, b.y + b.height);

    final double intersectW = math.max(0.0, right - left);
    final double intersectH = math.max(0.0, bottom - top);
    final double intersection = intersectW * intersectH;
    final double union = (a.width * a.height) + (b.width * b.height) - intersection;
    if (union <= 0.0) return 0.0;
    return intersection / union;
  }

  img.Image _cropFace(img.Image fullImage, DetectedFace face) {
    final x = face.x.toInt().clamp(0, fullImage.width - 1);
    final y = face.y.toInt().clamp(0, fullImage.height - 1);
    final width = face.width.toInt().clamp(1, fullImage.width - x);
    final height = face.height.toInt().clamp(1, fullImage.height - y);
    return img.copyCrop(fullImage, x: x, y: y, width: width, height: height);
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return 0.0;
  }

  Future<List<double>> _generateEmbedding(img.Image faceImage) async {
    if (_faceNetInterpreter == null) return [];

    try {
      // Aligned with attendance screen: 112x112 resize
      final toProcess = (faceImage.width == 112 && faceImage.height == 112) 
          ? faceImage 
          : img.copyResize(faceImage, width: 112, height: 112, interpolation: img.Interpolation.linear);

      final input = Float32List(1 * 112 * 112 * 3);
      int index = 0;
      for (int y = 0; y < 112; y++) {
        for (int x = 0; x < 112; x++) {
          final pixel = toProcess.getPixel(x, y);
          // Normalization [-1, 1]
          input[index++] = ((pixel.r.toInt() / 255.0) - 0.5) * 2.0;
          input[index++] = ((pixel.g.toInt() / 255.0) - 0.5) * 2.0;
          input[index++] = ((pixel.b.toInt() / 255.0) - 0.5) * 2.0;
        }
      }

      final inputTensor = input.reshape([1, 112, 112, 3]);
      final output = Float32List(_embeddingDim).reshape([1, _embeddingDim]);
      
      _faceNetInterpreter!.run(inputTensor, output);

      // L2 Normalization
      final embedding = <double>[];
      double norm = 0.0;
      for (int i = 0; i < _embeddingDim; i++) {
        final val = output[0][i] as double;
        embedding.add(val);
        norm += val * val;
      }
      
      norm = math.sqrt(norm) > 0 ? math.sqrt(norm) : 1.0;
      return embedding.map((v) => v / norm).toList();
    } catch (e) {
      debugPrint('Embedding error: $e');
      return [];
    }
  }

  Future<void> _saveStudent() async {
    if (_nameController.text.isEmpty ||
        _rollController.text.isEmpty ||
        _classController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
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
      // Insert student
      final student = Student(
        name: _nameController.text,
        rollNumber: _rollController.text,
        className: _classController.text,
        enrollmentDate: DateTime.now(),
      );

      final studentId = await _dbManager.insertStudent(student);

      // Insert embeddings
      for (final embedding in _embeddings) {
        await _dbManager.insertEmbedding(
          FaceEmbedding(
            studentId: studentId,
            vector: embedding,
            captureDate: DateTime.now(),
          ),
        );
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
    } on Exception catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        String errorMsg = 'Error: $e';
        if (e.toString().contains('UNIQUE')) {
          errorMsg = 'Roll number already exists!';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Enroll Student'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Student Information',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppConstants.paddingMedium),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'Enter student name',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: AppConstants.paddingMedium),
                    TextField(
                      controller: _rollController,
                      decoration: const InputDecoration(
                        labelText: 'Roll Number',
                        hintText: 'e.g., 21CS01',
                        prefixIcon: Icon(Icons.numbers),
                      ),
                    ),
                    const SizedBox(height: AppConstants.paddingMedium),
                    TextField(
                      controller: _classController,
                      decoration: const InputDecoration(
                        labelText: 'Class',
                        hintText: 'e.g., CSE-A',
                        prefixIcon: Icon(Icons.class_),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.paddingLarge),
            Card(
              color: Colors.grey[200],
              child: !isReady
                  ? const SizedBox(
                      height: 300,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : SizedBox(
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                        child: CameraPreview(_controller!),
                      ),
                    ),
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Samples Captured'),
                        Text(
                          '$_capturedSamples / ${AppConstants.requiredEnrollmentSamples}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.paddingSmall),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _capturedSamples / AppConstants.requiredEnrollmentSamples,
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppConstants.paddingLarge),
            ElevatedButton.icon(
              onPressed: isReady && !_isCapturing ? _captureFaceSample : null,
              icon: const Icon(Icons.camera),
              label: const Text('Capture Face Sample'),
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            ElevatedButton(
              onPressed: _capturedSamples >= AppConstants.requiredEnrollmentSamples
                  ? _saveStudent
                  : null,
              child: const Text('Save Student'),
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
