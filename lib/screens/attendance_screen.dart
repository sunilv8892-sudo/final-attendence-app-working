import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../database/database_manager.dart';
import '../models/face_detection_model.dart';
import '../models/embedding_model.dart';
import '../models/attendance_model.dart';
import '../models/student_model.dart';
import '../utils/constants.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({Key? key}) : super(key: key);

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  CameraController? _controller;
  Interpreter? _yoloInterpreter;
  Interpreter? _faceNetInterpreter;
  late DatabaseManager _dbManager;
  
  // Camera orientation properties
  int _sensorOrientation = 0;
  bool _isFrontCamera = false;
  
  // ML and Detection state
  List<DetectedFace> _detections = [];
  Map<int, String> _faceRecognitionMap = {}; // faceIndex -> studentName
  Map<int, double> _faceConfidenceMap = {}; // faceIndex -> similarity score
  bool _isProcessing = false;
  List<CameraDescription> _availableCameras = [];
  CameraDescription? _currentCamera;
  bool _isSwitchingCamera = false;
  
  // Performance optimization
  static const int _knnNeighbors = 5;
  bool _hasLoggedCameraSize = false;
  Map<int, DateTime> _studentLastMarkTime = {}; // Student ID -> last mark time

  // Lookup cache
  final Map<int, Student> _studentLookup = {};
  
  // Caching
  late List<FaceEmbedding> _cachedEmbeddings;
  final Set<int> _todayMarkedStudentIds = {};
  DateTime? _todayAttendanceDate;
  
  // Statistics
  int _totalRecognized = 0;

  int _yoloInputWidth = 416;
  int _yoloInputHeight = 416;
  int _yoloInputChannels = 3;
  int _yoloOutputAttributes = 85;
  int _yoloOutputBoxes = 25200;
  static const double _yoloConfidenceThreshold = 0.35;
  static const double _yoloNmsThreshold = 0.45;

  @override
  void initState() {
    super.initState();
    _initializeModels();
  }

  Future<void> _initializeModels() async {
    try {
      // Initialize database
      _dbManager = DatabaseManager();
      await _dbManager.database;
      
      // Pre-cache all embeddings for faster matching
      await _loadEmbeddingsCache();
      await _refreshTodayAttendanceRecords();

      // Load YOLO interpreter
      _yoloInterpreter = await Interpreter.fromAsset('assets/models/model.tflite');
      _yoloInterpreter?.allocateTensors();
      debugPrint('✅ YOLO model loaded');
      _logInterpreterShapes(_yoloInterpreter!, 'YOLO');
      _cacheYoloTensorInfo();

      // Load MobileFaceNet interpreter
      _faceNetInterpreter = await Interpreter.fromAsset('assets/models/embedding_model.tflite');
      debugPrint('✅ MobileFaceNet model loaded');
      debugPrint('📦 Cached ${_cachedEmbeddings.length} embeddings from database');

      // Initialize camera
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        throw Exception('No cameras are available on this device.');
      }
      final preferredCamera = _availableCameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _availableCameras.first,
      );
      await _initCamera(preferredCamera);

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ Error initializing: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _logInterpreterShapes(Interpreter interpreter, String tag) {
    try {
      final inputShape = interpreter.getInputTensor(0).shape;
      final outputShape = interpreter.getOutputTensor(0).shape;
      debugPrint('📐 $tag interpreter I/O -> input: ${inputShape.join('x')}, output: ${outputShape.join('x')}');
    } catch (e) {
      debugPrint('⚠️ Unable to log $tag interpreter shapes: $e');
    }
  }

  void _cacheYoloTensorInfo() {
    if (_yoloInterpreter == null) return;

    try {
      final inputShape = _yoloInterpreter!.getInputTensor(0).shape;
      if (inputShape.length >= 4) {
        _yoloInputHeight = inputShape[1];
        _yoloInputWidth = inputShape[2];
        _yoloInputChannels = inputShape[3];
      }

      final outputShape = _yoloInterpreter!.getOutputTensor(0).shape;
      if (outputShape.length >= 3) {
        _yoloOutputAttributes = outputShape[1];
        _yoloOutputBoxes = outputShape[2];
      }

      debugPrint('🧠 Cached YOLO shape -> input: ${_yoloInputWidth}x${_yoloInputHeight}x${_yoloInputChannels}, output: ${_yoloOutputAttributes}x${_yoloOutputBoxes}');
    } catch (e) {
      debugPrint('⚠️ Caching YOLO tensor info failed: $e');
    }
  }
  
  Future<void> _loadEmbeddingsCache() async {
    try {
      _cachedEmbeddings = await _dbManager.getAllEmbeddings();
      debugPrint('✅ Loaded ${_cachedEmbeddings.length} embeddings into cache');
      final students = await _dbManager.getAllStudents();
      _studentLookup
        ..clear()
        ..addEntries(students
            .where((student) => student.id != null)
            .map((student) => MapEntry(student.id!, student)));
      debugPrint('🧾 Cached ${_studentLookup.length} students for lookup');
    } catch (e) {
      debugPrint('❌ Cache load error: $e');
      _cachedEmbeddings = [];
      _studentLookup.clear();
    }
  }

  Future<void> _refreshTodayAttendanceRecords() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (_todayAttendanceDate != null && _isSameDay(_todayAttendanceDate!, today)) {
        return;
      }

      final records = await _dbManager.getAttendanceForDate(today);
      final ids = records.map((record) => record.studentId).toSet();

      if (mounted) {
        setState(() {
          _todayAttendanceDate = today;
          _todayMarkedStudentIds
            ..clear()
            ..addAll(ids);
        });
      } else {
        _todayAttendanceDate = today;
        _todayMarkedStudentIds
          ..clear()
          ..addAll(ids);
      }
    } catch (e) {
      debugPrint('⚠️ Unable to refresh today attendance: $e');
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _initCamera(CameraDescription camera) async {
    try {
      // Request camera permission
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        debugPrint('❌ Camera permission denied');
        return;
      }

      debugPrint('📷 Switching to camera: ${camera.name} (${camera.lensDirection})');
      _sensorOrientation = camera.sensorOrientation;
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;

      await _controller?.stopImageStream();
      await _controller?.dispose();

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _currentCamera = camera;
      await _controller!.initialize();
      debugPrint('✅ Camera initialized. Orientation=$_sensorOrientation, Front=$_isFrontCamera');
      _startImageStream();
    } catch (e) {
      debugPrint('❌ Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2 || _currentCamera == null || _isSwitchingCamera) {
      return;
    }

    final currentIndex = _availableCameras.indexOf(_currentCamera!);
    final nextIndex = (currentIndex + 1) % _availableCameras.length;
    final nextCamera = _availableCameras[nextIndex];

    setState(() {
      _isSwitchingCamera = true;
    });

    await _initCamera(nextCamera);

    if (mounted) {
      setState(() {
        _isSwitchingCamera = false;
      });
    }
  }

  void _startImageStream() {
    _controller?.startImageStream((image) {
      if (_isProcessing) return;
      _isProcessing = true;
      if (!_hasLoggedCameraSize) {
        debugPrint('📷 Camera image size: ${image.width}x${image.height}, Planes: ${image.planes.length}');
        _hasLoggedCameraSize = true;
      }
      _processFrame(image);
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final frameStart = DateTime.now();
      
      // Step 1: Run YOLO face detection
      final detections = await _runYoloDetection(image);
      
      if (detections.isNotEmpty) {
        debugPrint('🎯 Detected ${detections.length} face(s)');
      } else {
        // No faces, return early to save CPU
        if (mounted) setState(() => _detections = []);
        _isProcessing = false;
        return;
      }
      
      // Step 2: For each detected face, extract ROI and match
      _faceRecognitionMap.clear();
      _faceConfidenceMap.clear();
      
      for (int i = 0; i < detections.length; i++) {
        final detection = detections[i];
        
        // OPTIMIZATION: Convert ONLY the face ROI from YUV instead of full frame
        final faceImage = _convertYUV420ToImageROI(image, detection);
        if (faceImage == null) continue;

        // NEW: Rotate and Flip to match Enrollment's upright/non-mirrored format
        img.Image orientationCorrected = faceImage;
        
        // 1. Handle Sensor Rotation (Align with enrollment's takePicture)
        if (_sensorOrientation == 90) {
          orientationCorrected = img.copyRotate(faceImage, angle: 90);
        } else if (_sensorOrientation == 270) {
          orientationCorrected = img.copyRotate(faceImage, angle: 270);
        }

        // 2. Handle Mirroring (Front camera stream is mirrored, takePicture is not)
        if (_isFrontCamera) {
          orientationCorrected = img.flipHorizontal(orientationCorrected);
        }
        
        // Step 3: Generate embedding using MobileFaceNet
        final embedding = await _generateEmbedding(orientationCorrected);
        
        // Step 4: Match with database
        final matchResult = await _matchEmbedding(embedding);
        
        if (matchResult['studentName'] != 'Unknown') {
          _faceRecognitionMap[i] = matchResult['studentName'];
          _faceConfidenceMap[i] = matchResult['similarity'] as double;
          _totalRecognized++;
          
          debugPrint('✅ Matched: ${matchResult['studentName']} (${((matchResult['similarity'] as double) * 100).toStringAsFixed(1)}%)');
          
          // Step 5: Record attendance if not already marked today
          final studentId = matchResult['studentId'] as int?;
          if (studentId != null) {
            final now = DateTime.now();
            final lastMark = _studentLastMarkTime[studentId];
            
            // Cooldown: Don't mark same face within 2 seconds
            if (lastMark == null || now.difference(lastMark).inSeconds >= 2) {
              _studentLastMarkTime[studentId] = now;
              unawaited(_attemptAttendanceMark(studentId, matchResult['studentName'], now));
            }
          }
        }
        faceImage.clear();
        if (orientationCorrected != faceImage) orientationCorrected.clear();
      }

      if (mounted) {
        setState(() {
          _detections = detections;
        });
      }
      
      final frameTime = DateTime.now().difference(frameStart).inMilliseconds;
      debugPrint('⏱️ Frame processed in ${frameTime}ms');
    } catch (e) {
      debugPrint('Frame processing error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  img.Image? _convertYUV420ToImageROI(CameraImage image, DetectedFace face) {
    try {
      // Clamp coordinates to image boundaries
      int xStart = face.x.toInt().clamp(0, image.width - 1);
      int yStart = face.y.toInt().clamp(0, image.height - 1);
      int roiWidth = face.width.toInt().clamp(1, image.width - xStart);
      int roiHeight = face.height.toInt().clamp(1, image.height - yStart);

      final imgImage = img.Image(width: roiWidth, height: roiHeight);
      
      final Uint8List y = image.planes[0].bytes;
      final Uint8List u = image.planes[1].bytes;
      final Uint8List v = image.planes[2].bytes;

      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      for (int h = 0; h < roiHeight; h++) {
        final int yRow = yStart + h;
        for (int w = 0; w < roiWidth; w++) {
          final int xCol = xStart + w;
          
          // Get Y value
          final int yIndex = yRow * yRowStride + xCol;
          final int yVal = y[yIndex];
          
          // Get U and V values (UV is sampled at half resolution)
          final int uvH = yRow >> 1;
          final int uvW = xCol >> 1;
          final int uvIndex = uvH * uvRowStride + uvW * uvPixelStride;
          
          final int uVal = u[uvIndex.clamp(0, u.length - 1)];
          final int vVal = v[uvIndex.clamp(0, v.length - 1)];
          
          // Fast YUV to RGB conversion
          int r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
          int g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).round().clamp(0, 255);
          int b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);
          
          imgImage.setPixelRgb(w, h, r, g, b);
        }
      }
      return imgImage;
    } catch (e) {
      debugPrint('ROI Conversion error: $e');
      return null;
    }
  }

  Future<List<DetectedFace>> _runYoloDetection(CameraImage image) async {
    if (_yoloInterpreter == null) {
      debugPrint('❌ YOLO interpreter is null!');
      return [];
    }

    try {
      debugPrint('🔄 Starting YOLO detection... Image: ${image.width}x${image.height}');
      
      // Convert YUV420 to RGB
      final preprocessRequest = _YoloPreprocessRequest(
        imageWidth: image.width,
        imageHeight: image.height,
        yPlane: Uint8List.fromList(image.planes[0].bytes),
        uPlane: Uint8List.fromList(image.planes[1].bytes),
        vPlane: Uint8List.fromList(image.planes[2].bytes),
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        targetWidth: _yoloInputWidth,
        targetHeight: _yoloInputHeight,
      );

      final preprocessResult = await compute(_yoloPreprocess, preprocessRequest);
      final input = preprocessResult.input.reshape([1, _yoloInputHeight, _yoloInputWidth, _yoloInputChannels]);
      debugPrint('✅ Input tensor shape: [1, $_yoloInputHeight, $_yoloInputWidth, $_yoloInputChannels]');
      
      // Run inference
      final outputSize = 1 * _yoloOutputAttributes * _yoloOutputBoxes;
      final output = List.filled(outputSize, 0.0).reshape([1, _yoloOutputAttributes, _yoloOutputBoxes]);
      debugPrint('📍 Running YOLO inference...');
      _yoloInterpreter!.run(input, output);
      debugPrint('✅ YOLO inference complete. Output shape: ${output.shape}');

      // Parse YOLO output and extract detections
      final detections = _parseYoloOutput(output, image.width, image.height);
      
      return detections;
    } catch (e) {
      debugPrint('❌ YOLO detection error: $e');
      return [];
    }
  }

  Future<void> _attemptAttendanceMark(int studentId, String studentName, DateTime detectionTime) async {
    final today = DateTime(detectionTime.year, detectionTime.month, detectionTime.day);
    if (_todayAttendanceDate == null || !_isSameDay(_todayAttendanceDate!, today)) {
      await _refreshTodayAttendanceRecords();
    }

    if (_todayMarkedStudentIds.contains(studentId)) {
      return;
    }

    final recorded = await _recordAttendance(studentId, studentName);
    if (!recorded) return;

    if (mounted) {
      setState(() {
        _todayMarkedStudentIds.add(studentId);
      });
    } else {
      _todayMarkedStudentIds.add(studentId);
    }
  }

  List<DetectedFace> _parseYoloOutput(
    List output,
    int imageWidth,
    int imageHeight,
  ) {
    List<DetectedFace> detections = [];
    const double minFaceWidth = 20.0;
    const double minFaceHeight = 20.0;
    final double confidenceThreshold = _yoloConfidenceThreshold;

    try {
      if (output.isEmpty) {
        debugPrint('⚠️ YOLO output empty');
        return detections;
      }

      final batch = output[0] as List<dynamic>;
      final attrCount = math.min(batch.length, _yoloOutputAttributes);
      if (attrCount < 5) {
        debugPrint('⚠️ YOLO output does not contain enough attributes ($attrCount)');
        return detections;
      }

      final attrLists = List<List<dynamic>>.generate(
        attrCount,
        (index) => batch[index] as List<dynamic>);

      int maxAvailableBoxes = _yoloOutputBoxes;
      for (final attrList in attrLists) {
        maxAvailableBoxes = math.min(maxAvailableBoxes, attrList.length);
      }

      debugPrint('📊 YOLO parsed attr=$attrCount boxes=$maxAvailableBoxes');

      for (int i = 0; i < maxAvailableBoxes; i++) {
        final double cx = _toDouble(attrLists[0][i]);
        final double cy = _toDouble(attrLists[1][i]);
        final double w = _toDouble(attrLists[2][i]);
        final double h = _toDouble(attrLists[3][i]);
        final double confidence = _toDouble(attrLists[4][i]);

        if (confidence < confidenceThreshold) continue;

        final double pixelCx = cx * imageWidth;
        final double pixelCy = cy * imageHeight;
        double pixelW = w * imageWidth;
        double pixelH = h * imageHeight;

        double x = pixelCx - pixelW / 2.0;
        double y = pixelCy - pixelH / 2.0;

        x = x.clamp(0.0, imageWidth - pixelW);
        y = y.clamp(0.0, imageHeight - pixelH);

        pixelW = pixelW.clamp(minFaceWidth, imageWidth.toDouble());
        pixelH = pixelH.clamp(minFaceHeight, imageHeight.toDouble());

        if (pixelW < minFaceWidth || pixelH < minFaceHeight) continue;

        detections.add(DetectedFace(
          x: x,
          y: y,
          width: pixelW,
          height: pixelH,
          confidence: confidence,
        ));

        debugPrint('✅ Face $i -> x=${x.toStringAsFixed(0)}, y=${y.toStringAsFixed(0)}, w=${pixelW.toStringAsFixed(0)}, h=${pixelH.toStringAsFixed(0)}, conf=${(confidence * 100).toStringAsFixed(1)}%');
      }

      final filteredDetections = _applyNonMaxSuppression(detections, _yoloNmsThreshold);
      if (filteredDetections.isNotEmpty) {
        debugPrint('🎯 Faces before NMS: ${detections.length}, after: ${filteredDetections.length}');
      } else {
        debugPrint('⚠️ No valid faces detected this frame');
      }
      return filteredDetections;
    } catch (e) {
      debugPrint('❌ Error parsing YOLO output: $e');
    }

    return [];
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return 0.0;
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
      if (shouldKeep) {
        selected.add(candidate);
      }
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

  img.Image _convertYUV420ToImage(CameraImage image, {int skipRows = 0, int skipCols = 0}) {
    final width = skipRows > 0 ? image.width ~/ 2 : image.width;
    final height = skipRows > 0 ? image.height ~/ 2 : image.height;
    
    debugPrint('🎨 Converting YUV420: ${image.width}x${image.height} -> $width x$height (skip=$skipRows)');
    
    final imgImage = img.Image(width: width, height: height);
    
    try {
      final Uint8List y = image.planes[0].bytes;
      final Uint8List u = image.planes[1].bytes;
      final Uint8List v = image.planes[2].bytes;

      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      for (int h = 0; h < height; h++) {
        final yRow = skipRows > 0 ? h * 2 : h;
        
        for (int w = 0; w < width; w++) {
          final xCol = skipCols > 0 ? w * 2 : w;
          
          // Get Y value
          final yIndex = yRow * yRowStride + xCol;
          final yVal = y[yIndex].clamp(0, 255);
          
          // Get U and V values (UV is sampled at half resolution)
          final uvH = yRow >> 1;
          final uvW = xCol >> 1;
          final uvIndex = uvH * uvRowStride + uvW * uvPixelStride;
          
          final uVal = u[uvIndex.clamp(0, u.length - 1)].clamp(0, 255);
          final vVal = v[uvIndex.clamp(0, v.length - 1)].clamp(0, 255);
          
          // YUV to RGB conversion
          int r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
          int g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).round().clamp(0, 255);
          int b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);
          
          imgImage.setPixelRgb(w, h, r, g, b);
        }
      }
      
      debugPrint('✅ YUV conversion complete');
    } catch (e) {
      debugPrint('⚠️ YUV conversion error: $e');
    }

    return imgImage;
  }

  img.Image _cropFace(img.Image fullImage, DetectedFace face) {
    int x = face.x.toInt().clamp(0, fullImage.width - 1);
    int y = face.y.toInt().clamp(0, fullImage.height - 1);
    int width = face.width.toInt().clamp(1, fullImage.width - x);
    int height = face.height.toInt().clamp(1, fullImage.height - y);

    // Validate dimensions before cropping
    if (width <= 0 || height <= 0 || x < 0 || y < 0) {
      debugPrint('⚠️ Invalid crop dimensions: x=$x, y=$y, w=$width, h=$height');
      return img.Image(width: 112, height: 112); // Return blank image
    }

    return img.copyCrop(fullImage, x: x, y: y, width: width, height: height);
  }

  Future<List<double>> _generateEmbedding(img.Image faceImage) async {
    if (_faceNetInterpreter == null) return [];

    try {
      // Skip resizing if already 112x112
      final toProcess = (faceImage.width == 112 && faceImage.height == 112) 
          ? faceImage 
          : img.copyResize(faceImage, width: 112, height: 112, 
              interpolation: img.Interpolation.linear);
      
      // Convert to float32 array with normalization
      final input = Float32List(1 * 112 * 112 * 3);
      int index = 0;
      for (int y = 0; y < 112; y++) {
        for (int x = 0; x < 112; x++) {
          final pixel = toProcess.getPixel(x, y);
          // Normalize to -1 to 1
          input[index++] = ((pixel.r.toInt() / 255.0) - 0.5) * 2.0;
          input[index++] = ((pixel.g.toInt() / 255.0) - 0.5) * 2.0;
          input[index++] = ((pixel.b.toInt() / 255.0) - 0.5) * 2.0;
        }
      }

      final inputTensor = input.reshape([1, 112, 112, 3]);
      final outputShape = _faceNetInterpreter!.getOutputTensor(0).shape;
      final embeddingDim = outputShape.last;
      
      final output = Float32List(embeddingDim).reshape([1, embeddingDim]);
      
      _faceNetInterpreter!.run(inputTensor, output);

      // Extract and normalize in single pass
      final embedding = <double>[];
      double norm = 0.0;
      
      for (int i = 0; i < embeddingDim; i++) {
        final val = output[0][i] as double;
        embedding.add(val);
        norm += val * val;
      }
      
      norm = norm > 0 ? math.sqrt(norm) : 1.0;
      final normalized = embedding.map((v) => v / norm).toList();
      
      // Clear memory
      if (toProcess != faceImage) toProcess.clear();
      
      return normalized;
    } catch (e) {
      debugPrint('Embedding generation error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> _matchEmbedding(List<double> embedding) async {
    try {
      if (embedding.isEmpty) {
        return {'studentName': 'Unknown', 'studentId': null, 'similarity': 0.0};
      }

      // Use cached embeddings (much faster than DB query per frame)
      if (_cachedEmbeddings.isEmpty) {
        return {'studentName': 'Unknown', 'studentId': null, 'similarity': 0.0};
      }

      final matches = <_EmbeddingMatch>[];
      for (final storedEmbed in _cachedEmbeddings) {
        if (storedEmbed.vector.length != embedding.length) continue;
        final similarity = _cosineSimilarity(embedding, storedEmbed.vector);
        matches.add(_EmbeddingMatch(
          studentId: storedEmbed.studentId,
          similarity: similarity,
        ));
      }

      if (matches.isEmpty) {
        return {'studentName': 'Unknown', 'studentId': null, 'similarity': 0.0};
      }

      matches.sort((a, b) => b.similarity.compareTo(a.similarity));
      final neighborCount = math.min(_knnNeighbors, matches.length);
      final selected = matches.take(neighborCount).toList();
      double totalWeight = 0.0;

      final Map<int, double> voteTotals = {};
      for (final match in selected) {
        totalWeight += match.similarity;
        voteTotals[match.studentId] = (voteTotals[match.studentId] ?? 0.0) + match.similarity;
      }

      if (voteTotals.isEmpty) {
        return {
          'studentName': 'Unknown',
          'studentId': null,
          'similarity': selected.first.similarity,
        };
      }

      final bestEntry = voteTotals.entries.reduce((value, element) => value.value >= element.value ? value : element);
      final knnScore = totalWeight > 0 ? bestEntry.value / selected.length : 0.0;
      final highestSimilarity = selected.first.similarity;

      if (knnScore < AppConstants.similarityThreshold) {
        debugPrint('⚠️ Similarity too low: KNN Score=${knnScore.toStringAsFixed(3)}, Best Match=${highestSimilarity.toStringAsFixed(3)}');
      }

      if (knnScore >= AppConstants.similarityThreshold) {
        final student = _studentLookup[bestEntry.key];
        final studentName = student?.name ?? 'Unknown';
        return {
          'studentName': studentName,
          'studentId': bestEntry.key,
          'similarity': knnScore,
        };
      }

      return {
        'studentName': 'Unknown',
        'studentId': null,
        'similarity': highestSimilarity,
      };
    } catch (e) {
      debugPrint('Matching error: $e');
      return {'studentName': 'Unknown', 'studentId': null, 'similarity': 0.0};
    }
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = (normA * normB).clamp(0.0, double.infinity);
    if (denominator == 0.0) return 0.0;
    
    return dotProduct / denominator;
  }

  Future<bool> _recordAttendance(int studentId, String studentName) async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final timeStr = now.hour.toString().padLeft(2, '0') + ':' + now.minute.toString().padLeft(2, '0');
      final record = AttendanceRecord(
        studentId: studentId,
        date: today,
        time: timeStr,
        status: AttendanceStatus.present,
      );

      final id = await _dbManager.recordAttendance(record);
      final success = id > 0;
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $studentName marked present'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      return success;
    } catch (e) {
      debugPrint('Attendance recording error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _yoloInterpreter?.close();
    _faceNetInterpreter?.close();
    _cachedEmbeddings.clear();
    _faceRecognitionMap.clear();
    _faceConfidenceMap.clear();
    _studentLastMarkTime.clear();
    _detections.clear();
    _todayMarkedStudentIds.clear();
    _todayAttendanceDate = null;
    debugPrint('✅ Attendance screen disposed - memory freed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Attendance'),
        elevation: 0,
        actions: [
          if (_availableCameras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              tooltip: 'Switch camera',
              onPressed: _isSwitchingCamera ? null : _switchCamera,
            ),
        ],
      ),
      body: !isReady
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading models and camera...'),
                ],
              ),
            )
          : Column(
              children: [
                // Top Stats Bar
                Container(
                  color: Colors.grey[200],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          Text(
                            _detections.length.toString(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const Text('Detected', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            _totalRecognized.toString(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const Text('Recognized', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            _todayMarkedStudentIds.length.toString(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const Text('Marked Today', style: TextStyle(fontSize: 10)),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      // Draw bounding boxes with confidence
                      CustomPaint(
                        painter: FaceBoxPainter(
                          detections: _detections,
                          recognitionMap: _faceRecognitionMap,
                          confidenceMap: _faceConfidenceMap,
                          cameraImage: _controller?.value.previewSize,
                        ),
                        size: Size.infinite,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detected: ${_detections.length} face(s) | Recognized: ${_faceRecognitionMap.length}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_detections.isEmpty)
                          const Text('No faces detected - Position students facing camera')
                        else
                          ..._detections.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final name = _faceRecognitionMap[idx] ?? 'Unknown';
                            final confidence = _faceConfidenceMap[idx] ?? 0.0;
                            final confidenceStr = (confidence * 100).toStringAsFixed(1);
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.face, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: TextStyle(
                                            fontWeight: name != 'Unknown' ? FontWeight.bold : FontWeight.normal,
                                            color: name != 'Unknown' ? Colors.green : Colors.grey,
                                          ),
                                        ),
                                        if (name != 'Unknown')
                                          Text(
                                            'Confidence: $confidenceStr%',
                                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (name != 'Unknown')
                                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                ],
                              ),
                            );
                          }).toList(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class FaceBoxPainter extends CustomPainter {
  final List<DetectedFace> detections;
  final Map<int, String> recognitionMap;
  final Map<int, double> confidenceMap;
  final Size? cameraImage;

  FaceBoxPainter({
    required this.detections,
    required this.recognitionMap,
    required this.confidenceMap,
    this.cameraImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || cameraImage == null) return;

    double scaleX, scaleY;
    bool isPortrait = size.height > size.width;
    
    // Most mobile sensors are landscape (e.g. 640x480)
    // In portrait UI, the image is rotated, so camera height maps to screen width
    if (isPortrait) {
      scaleX = size.width / cameraImage!.height;
      scaleY = size.height / cameraImage!.width;
    } else {
      scaleX = size.width / cameraImage!.width;
      scaleY = size.height / cameraImage!.height;
    }

    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (int i = 0; i < detections.length; i++) {
      final detection = detections[i];
      
      double scaledX, scaledY, scaledW, scaledH;

      if (isPortrait) {
        // Map landscape camera coordinates to portrait UI coordinates
        // This is a 90-degree rotation mapping
        scaledX = detection.y * scaleX;
        scaledY = (cameraImage!.width - detection.x - detection.width) * scaleY;
        scaledW = detection.height * scaleX;
        scaledH = detection.width * scaleY;
      } else {
        scaledX = detection.x * scaleX;
        scaledY = detection.y * scaleY;
        scaledW = detection.width * scaleX;
        scaledH = detection.height * scaleY;
      }

      final rect = Rect.fromLTWH(scaledX, scaledY, scaledW, scaledH);
      canvas.drawRect(rect, paint);

      final name = recognitionMap[i] ?? 'Unknown';
      final confidence = confidenceMap[i] ?? 0.0;
      final displayText = name != 'Unknown'
          ? '$name (${(confidence * 100).toStringAsFixed(0)}%)'
          : 'Unknown';

      final textPainter = TextPainter(
        text: TextSpan(
          text: displayText,
          style: TextStyle(
            color: name != 'Unknown' ? Colors.green : Colors.yellow,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      final backgroundRect = Rect.fromLTWH(
        scaledX,
        scaledY - 30,
        textPainter.width + 8,
        28,
      );

      final backgroundPaint = Paint()..color = Colors.black87;
      canvas.drawRect(backgroundRect, backgroundPaint);
      textPainter.paint(canvas, ui.Offset(scaledX + 2, scaledY - 26));
    }
  }

  @override
  bool shouldRepaint(FaceBoxPainter oldDelegate) => oldDelegate.detections != detections;
}

class _YoloPreprocessRequest {
  final int imageWidth;
  final int imageHeight;
  final Uint8List yPlane;
  final Uint8List uPlane;
  final Uint8List vPlane;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int targetWidth;
  final int targetHeight;

  _YoloPreprocessRequest({
    required this.imageWidth,
    required this.imageHeight,
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.targetWidth,
    required this.targetHeight,
  });
}

class _YoloPreprocessResult {
  final Float32List input;

  _YoloPreprocessResult(this.input);
}

class _EmbeddingMatch {
  final int studentId;
  final double similarity;

  _EmbeddingMatch({required this.studentId, required this.similarity});
}

Future<_YoloPreprocessResult> _yoloPreprocess(_YoloPreprocessRequest request) async {
  final img.Image rgbImage = img.Image(width: request.imageWidth, height: request.imageHeight);
  final y = request.yPlane;
  final u = request.uPlane;
  final v = request.vPlane;

  for (int h = 0; h < request.imageHeight; h++) {
    for (int w = 0; w < request.imageWidth; w++) {
      final yIndex = h * request.yRowStride + w;
      final uvH = h >> 1;
      final uvW = w >> 1;
      final uvIndex = uvH * request.uvRowStride + uvW * request.uvPixelStride;

      final yVal = y[yIndex].clamp(0, 255);
      final uVal = u[uvIndex.clamp(0, u.length - 1)].clamp(0, 255);
      final vVal = v[uvIndex.clamp(0, v.length - 1)].clamp(0, 255);

      int r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
      int g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128)).round().clamp(0, 255);
      int b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

      rgbImage.setPixelRgb(w, h, r, g, b);
    }
  }

  final resized = img.copyResize(
    rgbImage,
    width: request.targetWidth,
    height: request.targetHeight,
    interpolation: img.Interpolation.linear,
  );

  final Float32List floats = Float32List(1 * request.targetHeight * request.targetWidth * 3);
  int index = 0;
  for (int yRow = 0; yRow < request.targetHeight; yRow++) {
    for (int x = 0; x < request.targetWidth; x++) {
      final pixel = resized.getPixel(x, yRow);
      floats[index++] = pixel.r.toDouble() / 255.0;
      floats[index++] = pixel.g.toDouble() / 255.0;
      floats[index++] = pixel.b.toDouble() / 255.0;
    }
  }

  return _YoloPreprocessResult(floats);
}
