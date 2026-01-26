import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<CameraDescription>? cameras;

// Softmax function to convert logits to probabilities
List<double> softmax(List<double> x) {
  double maxVal = x.reduce((a, b) => a > b ? a : b);
  final exp = x.map((e) => math.exp(e - maxVal)).toList();
  final sum = exp.reduce((a, b) => a + b);
  return exp.map((e) => e / sum).toList();
}

// Cosine similarity for comparing embedding vectors
double cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0;
  double normA = 0;
  double normB = 0;

  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  return dot / (math.sqrt(normA) * math.sqrt(normB) + 1e-10);
}

// ====== SECONDARY MODEL FRAMEWORK ======
// Enum to select secondary model type
enum SecondaryModelType { classifier, embedding }

// Abstract interface for all secondary models
abstract class SecondaryModel {
  Future<void> load();
  Future<SecondaryResult> infer(img.Image crop);
  void dispose();
  String get modelName;
}

// Result container for secondary model output
class SecondaryResult {
  final String? label;
  final double? confidence;
  final List<double>? embedding;
  final Map<String, dynamic>? rawOutput;

  SecondaryResult({
    this.label,
    this.confidence,
    this.embedding,
    this.rawOutput,
  });

  @override
  String toString() =>
      'SecondaryResult(label=$label, conf=$confidence, embeddingDim=${embedding?.length})';
}

// ====== CLASSIFIER MODEL IMPLEMENTATION ======
class ClassifierModel implements SecondaryModel {
  final String modelPath;
  final String labelsPath;
  
  Interpreter? _interpreter;
  List<String> _labels = [];
  int _inputSize = 224;
  bool _useBGR = false;
  bool _useNormalization_1_1 = false;
  
  ClassifierModel({
    required this.modelPath,
    required this.labelsPath,
  });

  @override
  String get modelName => 'ClassifierModel';

  @override
  Future<void> load() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);
      
      final rawLabels = await rootBundle.loadString(labelsPath);
      _labels = rawLabels
          .split(RegExp(r'\r?\n'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .map((s) {
            final parts = s.split(RegExp(r'\s+'));
            return parts.length > 1 ? parts.sublist(1).join(' ') : s;
          })
          .toList();
      
      final inputShape = _interpreter!.getInputTensor(0).shape;
      if (inputShape.length >= 3) {
        _inputSize = inputShape[1];
      }
      
      debugPrint('✅ ClassifierModel loaded: size=$_inputSize, labels=$_labels');
    } catch (e, st) {
      debugPrint('❌ ClassifierModel load error: $e\n$st');
      rethrow;
    }
  }

  @override
  Future<SecondaryResult> infer(img.Image crop) async {
    if (_interpreter == null) throw Exception('Model not loaded');

    try {
      final resized = img.copyResize(
        crop,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );

      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      final inputType = inputTensor.type;
      final numClasses = outputTensor.shape.last;

      dynamic input;
      if (inputType == TensorType.uint8) {
        final bytes = Uint8List(1 * _inputSize * _inputSize * 3);
        int idx = 0;
        for (int py = 0; py < _inputSize; py++) {
          for (int px = 0; px < _inputSize; px++) {
            final pixel = resized.getPixel(px, py);
            if (_useBGR) {
              bytes[idx++] = pixel.b.toInt();
              bytes[idx++] = pixel.g.toInt();
              bytes[idx++] = pixel.r.toInt();
            } else {
              bytes[idx++] = pixel.r.toInt();
              bytes[idx++] = pixel.g.toInt();
              bytes[idx++] = pixel.b.toInt();
            }
          }
        }
        input = bytes.reshape([1, _inputSize, _inputSize, 3]);
      } else {
        final floats = Float32List(1 * _inputSize * _inputSize * 3);
        int idx = 0;
        for (int py = 0; py < _inputSize; py++) {
          for (int px = 0; px < _inputSize; px++) {
            final pixel = resized.getPixel(px, py);
            double r = pixel.r.toDouble();
            double g = pixel.g.toDouble();
            double b = pixel.b.toDouble();

            if (_useNormalization_1_1) {
              r = (r / 127.5) - 1.0;
              g = (g / 127.5) - 1.0;
              b = (b / 127.5) - 1.0;
            } else {
              r = r / 255.0;
              g = g / 255.0;
              b = b / 255.0;
            }

            if (_useBGR) {
              floats[idx++] = b;
              floats[idx++] = g;
              floats[idx++] = r;
            } else {
              floats[idx++] = r;
              floats[idx++] = g;
              floats[idx++] = b;
            }
          }
        }
        input = floats.reshape([1, _inputSize, _inputSize, 3]);
      }

      dynamic output;
      if (outputTensor.type == TensorType.uint8) {
        output = Uint8List(numClasses).reshape([1, numClasses]);
      } else {
        output = Float32List(numClasses).reshape([1, numClasses]);
      }

      _interpreter!.run(input, output);

      List<double> logits = [];
      for (int i = 0; i < numClasses; i++) {
        final val = (output[0][i] is int) 
            ? output[0][i].toDouble() 
            : output[0][i] as double;
        logits.add(val);
      }

      final probs = softmax(logits);
      final maxIdx = probs.indexOf(probs.reduce((a, b) => a > b ? a : b));
      final confidence = probs[maxIdx];
      final label = maxIdx < _labels.length ? _labels[maxIdx] : maxIdx.toString();

      debugPrint('🔍 Classifier: label=$label, conf=${confidence.toStringAsFixed(3)}');

      return SecondaryResult(
        label: label,
        confidence: confidence,
        rawOutput: {'logits': logits, 'probabilities': probs},
      );
    } catch (e) {
      debugPrint('❌ Classifier infer error: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
  }

  // Configuration setters
  void setBGR(bool value) => _useBGR = value;
  void setNormalization_1_1(bool value) => _useNormalization_1_1 = value;
}

// ====== EMBEDDING MODEL PLACEHOLDER ======
class EmbeddingModel implements SecondaryModel {
  final String modelPath;
  Interpreter? _interpreter;
  int _inputSize = 224;

  EmbeddingModel({required this.modelPath});

  @override
  String get modelName => 'EmbeddingModel';

  @override
  Future<void> load() async {
    try {
      _interpreter = await Interpreter.fromAsset(modelPath);
      final inputShape = _interpreter!.getInputTensor(0).shape;
      if (inputShape.length >= 3) {
        _inputSize = inputShape[1];
      }
      debugPrint('✅ EmbeddingModel loaded: size=$_inputSize');
    } catch (e) {
      debugPrint('❌ EmbeddingModel load error: $e');
      rethrow;
    }
  }

  @override
  Future<SecondaryResult> infer(img.Image crop) async {
    if (_interpreter == null) throw Exception('Model not loaded');

    try {
      final resized = img.copyResize(
        crop,
        width: _inputSize,
        height: _inputSize,
        interpolation: img.Interpolation.linear,
      );

      // Prepare float input
      final floats = Float32List(1 * _inputSize * _inputSize * 3);
      int idx = 0;
      for (int py = 0; py < _inputSize; py++) {
        for (int px = 0; px < _inputSize; px++) {
          final pixel = resized.getPixel(px, py);
          floats[idx++] = pixel.r.toDouble() / 255.0;
          floats[idx++] = pixel.g.toDouble() / 255.0;
          floats[idx++] = pixel.b.toDouble() / 255.0;
        }
      }

      final input = floats.reshape([1, _inputSize, _inputSize, 3]);
      final outputTensor = _interpreter!.getOutputTensor(0);
      final embeddingDim = outputTensor.shape.last;
      
      final output = Float32List(embeddingDim).reshape([1, embeddingDim]);
      _interpreter!.run(input, output);

      List<double> embedding = [];
      for (int i = 0; i < embeddingDim; i++) {
        embedding.add(output[0][i] as double);
      }

      debugPrint('🔍 Embedding: dim=$embeddingDim');

      return SecondaryResult(
        embedding: embedding,
        rawOutput: {'embedding': embedding},
      );
    } catch (e) {
      debugPrint('❌ Embedding infer error: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint("Error fetching cameras: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const YoloDetectionPage(),
    );
  }
}

class YoloDetectionPage extends StatefulWidget {
  const YoloDetectionPage({super.key});
  @override
  State<YoloDetectionPage> createState() => _YoloDetectionPageState();
}

class _YoloDetectionPageState extends State<YoloDetectionPage> {
  CameraController? controller;
  FlutterVision vision = FlutterVision();
  List<Map<String, dynamic>>? detections;
  bool isModelLoaded = false;
  bool isInferenceRunning = false;
  bool isFrontCamera = false;
  
  // ===== SECONDARY MODEL FRAMEWORK =====
  SecondaryModelType secondaryModelType = SecondaryModelType.classifier;
  SecondaryModel? secondaryModel;
  bool isSecondaryModelLoaded = false;
  
  // Settings Menu State
  bool _showSettingsMenu = false;
  
  // ===== YOLO DETECTION SETTINGS =====
  double confidenceThreshold = 0.25;
  double iouThreshold = 0.4;
  double classThreshold = 0.25;
  
  // ===== SECONDARY MODEL PREPROCESSING (Classifier-specific) =====
  bool _classifierUseBGR = false;
  bool _classifierUseNormalization_1_1 = false;
  bool _flipImageVertically = false;
  bool _flipImageHorizontally = false;
  bool _rotate90 = false;
  
  // ===== SECONDARY MODEL CONFIDENCE & SMOOTHING =====
  double _minSecondaryConfidence = 0.5;
  int _smoothingWindow = 5;
  int _classifyEveryNFrames = 3;
  bool _enableSmoothing = true;
  bool _enableCaching = true;
  
  // ===== DISPLAY SETTINGS =====
  bool _showFPS = true;
  bool _showConfidenceSlider = true;
  bool _showDetectionLabels = true;
  bool _showClassifierLabel = true;
  
  // ===== ADVANCED SETTINGS =====
  int _cropPaddingPercent = 20;
  bool _showDebugInfo = false;
  String _selectedResolution = 'high';
  
  // Stats
  double fps = 0;
  double inferenceTime = 0;
  DateTime? lastInference;
  
  // Prediction smoothing for stability
  final Map<String, List<String>> _predictionHistory = {};
  String? _lastStableLabel;
  int _stableCount = 0;
  
  // Performance optimization
  int _frameCount = 0;
  String? _cachedClassifierLabel;
  double? _cachedClassifierConf;
  
  // Embedding result caching to prevent flickering
  String? _cachedEmbeddingLabel;
  double? _cachedEmbeddingConf;
  
  // ===== EMBEDDING-BASED FACE VERIFICATION =====
  Map<String, List<double>> registeredPeople = {};  // Database: name -> embedding
  List<double>? _cachedEmbedding;
  double _embeddingThreshold = 0.7;

  @override
  void initState() {
    super.initState();
    _initEverything();
  }

  Future<void> _initEverything() async {
    // 1. Permissions
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    // 2. Load saved faces from storage
    await _loadFacesFromStorage();

    // 3. Load Model
    try {
      await vision.loadYoloModel(
        labels: 'assets/models/labels.txt',
        modelPath: 'assets/models/model.tflite',
        modelVersion: "yolov8", 
        numThreads: 4,
        useGpu: true, // Enable GPU for better performance
      );
      setState(() => isModelLoaded = true);
    } catch (e) {
      debugPrint("Error loading model: $e");
    }

    // Load secondary model (pluggable type)
    try {
      secondaryModel = _createSecondaryModel(secondaryModelType);
      await secondaryModel!.load();
      
      setState(() => isSecondaryModelLoaded = true);
      
      // Print initialization summary
      debugPrint('''
╔════════════════════════════════════════╗
║     MULTI-MODEL FRAMEWORK READY        ║
╠════════════════════════════════════════╣
║ 🟢 YOLO Detection:  ENABLED            ║
║    Confidence: ${(confidenceThreshold * 100).toInt()}%                      ║
║    IOU:        ${(iouThreshold * 100).toInt()}%                      ║
╠════════════════════════════════════════╣
║ 🟢 Secondary Model: ${isSecondaryModelLoaded ? 'ENABLED' : 'DISABLED'}         ║
║    Type:      ${secondaryModel?.modelName}               ║
║    Status:    Ready                    ║
╠════════════════════════════════════════╣
║ 📝 FRAMEWORK INFO:                     ║
║ Pluggable Architecture - supports:     ║
║ • Classifier (me/not_me, emotions)    ║
║ • Embedding (face verification)       ║
║ • Custom models (via interface)        ║
╚════════════════════════════════════════╝
''');
    } catch (e, st) {
      debugPrint('Second model not loaded (optional): $e\n$st');
      isSecondaryModelLoaded = false;
    }

    // 3. Setup Camera (use selected lens)
    await _initCamera(front: isFrontCamera);
  }

  Future<void> _initCamera({required bool front}) async {
    // Stop and dispose existing controller if any
    try {
      if (controller != null) {
        await controller!.stopImageStream();
        await controller!.dispose();
        controller = null;
      }
    } catch (e) {
      debugPrint("Error stopping previous camera: $e");
    }

    if (cameras == null || cameras!.isEmpty) return;

    // Find desired camera
    CameraDescription? selected;
    for (final c in cameras!) {
      if (front && c.lensDirection == CameraLensDirection.front) {
        selected = c;
        break;
      }
      if (!front && c.lensDirection == CameraLensDirection.back) {
        selected = c;
        break;
      }
    }

    // Fallback to first camera if desired not found
    selected ??= cameras!.first;

    controller = CameraController(
      selected,
      ResolutionPreset.high, // Back to high for better detection
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // Optimal format
    );

    try {
      await controller!.initialize();

      // Start streaming with throttle
      controller!.startImageStream((image) {
        // Skip if still processing or too soon (throttle to ~15fps max input)
        if (isInferenceRunning || !isModelLoaded) return;
        
        final now = DateTime.now();
        if (lastInference != null && now.difference(lastInference!).inMilliseconds < 60) {
          return; // Throttle input to max ~15fps
        }
        
        isInferenceRunning = true;
        _runDetection(image);
      });

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera init error: $e");
    }
  }

  // Factory function to create secondary model based on type
  SecondaryModel _createSecondaryModel(SecondaryModelType type) {
    switch (type) {
      case SecondaryModelType.classifier:
        final classifier = ClassifierModel(
          modelPath: 'assets/models/second_model.tflite',
          labelsPath: 'assets/models/second_labels.txt',
        );
        classifier.setBGR(_classifierUseBGR);
        classifier.setNormalization_1_1(_classifierUseNormalization_1_1);
        return classifier;
      
      case SecondaryModelType.embedding:
        return EmbeddingModel(
          modelPath: 'assets/models/embedding_model.tflite',
        );
    }
  }

  void _switchCamera() async {
    setState(() => isFrontCamera = !isFrontCamera);
    await _initCamera(front: isFrontCamera);
  }

  Future<void> _runDetection(CameraImage image) async {
    final start = DateTime.now();
    try {
      final results = await vision.yoloOnFrame(
        bytesList: image.planes.map((p) => p.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.4,
        confThreshold: confidenceThreshold,
        classThreshold: 0.25, // Lowered for better detection
      );

      final end = DateTime.now();
      _frameCount++;
      
      if (mounted) {
        // Apply cached classifier result to new detections
        if (_cachedClassifierLabel != null && results.isNotEmpty) {
          for (final d in results) {
            d['classifier'] = _cachedClassifierLabel;
            d['classifierConf'] = _cachedClassifierConf;
          }
        }
        
      // Only run secondary model every N frames to save CPU
        final shouldRunSecondary = isSecondaryModelLoaded && 
            results.isNotEmpty && 
            (_frameCount % _classifyEveryNFrames == 0);
        
        if (shouldRunSecondary) {
          await _runSecondaryInference(image, results);
        } else if (secondaryModelType == SecondaryModelType.embedding && _cachedEmbeddingLabel != null) {
          // Use cached embedding result on non-inference frames
          for (final det in results) {
            det['classifier'] = _cachedEmbeddingLabel;
            det['classifierConf'] = _cachedEmbeddingConf ?? 0.0;
          }
        } else if (secondaryModelType == SecondaryModelType.classifier && _cachedClassifierLabel != null) {
          // Use cached classifier result on non-inference frames
          for (final det in results) {
            det['classifier'] = _cachedClassifierLabel;
            det['classifierConf'] = _cachedClassifierConf;
          }
        }
        
        // Single setState for all updates
        setState(() {
          detections = results;
          inferenceTime = end.difference(start).inMilliseconds.toDouble();
          if (lastInference != null) {
            fps = 1000 / end.difference(lastInference!).inMilliseconds;
          }
          lastInference = end;
        });
      }
    } catch (e) {
      debugPrint("Detection error: $e");
    } finally {
      isInferenceRunning = false;
    }
  }

  // Run TFLite classifier using tflite_flutter interpreter on FIRST detection only (performance)
  Future<void> _runSecondaryInference(CameraImage image, List<Map<String, dynamic>> dets) async {
    if (controller == null || secondaryModel == null || dets.isEmpty) {
      if (dets.isEmpty && _showDebugInfo) {
        debugPrint('🔴 NO DETECTIONS: YOLO found 0 faces. Try lowering confidence threshold (current: ${(confidenceThreshold * 100).toInt()}%)');
      }
      return;
    }
    final previewSize = controller!.value.previewSize;
    if (previewSize == null) return;

    img.Image? fullImage;
    try {
      fullImage = _convertCameraImage(image);
    } catch (e) {
      debugPrint('Failed to convert camera image: $e');
      return;
    }

    // Only process FIRST detection for performance
    final d = dets.first;
    try {
      final List<dynamic> box = d['box'];
      final double x1 = box[0];
      final double y1 = box[1];
      final double x2 = box[2];
      final double y2 = box[3];

      // Preview size is often rotated (width/height swapped), so we use the camera image dimensions directly
      // The box coordinates from YOLO are in preview coordinate space
      final double scaleX = image.width / previewSize.height;
      final double scaleY = image.height / previewSize.width;

      // Convert preview coordinates to camera image coordinates
      int left = (x1 * scaleX).toInt();
      int top = (y1 * scaleY).toInt();
      int right = (x2 * scaleX).toInt();
      int bottom = (y2 * scaleY).toInt();

      // Ensure coordinates are valid
      left = left.clamp(0, fullImage.width - 1);
      top = top.clamp(0, fullImage.height - 1);
      right = right.clamp(left + 1, fullImage.width);
      bottom = bottom.clamp(top + 1, fullImage.height);

        final cropW = right - left;
        final cropH = bottom - top;
        if (cropW <= 10 || cropH <= 10) return; // Too small crop, skip classification

        // Add padding around crop for better context (configurable percentage)
        final padRatio = _cropPaddingPercent / 100.0;
        final padX = (cropW * padRatio).toInt();
        final padY = (cropH * padRatio).toInt();
        final paddedLeft = (left - padX).clamp(0, fullImage.width - 1);
        final paddedTop = (top - padY).clamp(0, fullImage.height - 1);
        final paddedRight = (right + padX).clamp(paddedLeft + 1, fullImage.width);
        final paddedBottom = (bottom + padY).clamp(paddedTop + 1, fullImage.height);

        final cropped = img.copyCrop(fullImage, x: paddedLeft, y: paddedTop, 
            width: paddedRight - paddedLeft, height: paddedBottom - paddedTop);
        // Use linear interpolation for better quality resize
        final resized = img.copyResize(cropped, width: 224, height: 224, 
            interpolation: img.Interpolation.linear);

        // Run secondary model inference (abstracted)
        final result = await secondaryModel!.infer(resized);
        
        // Handle result based on model type
        if (secondaryModelType == SecondaryModelType.classifier) {
          // Classifier result: has label and confidence
          final String rawLabel = result.label ?? 'unknown';
          final double confidence = result.confidence ?? 0.0;
          
          // Apply prediction smoothing for stability
          final String stableLabel = _getSmoothedPrediction(rawLabel, confidence);
          
          // Cache result and apply to ALL detections
          _cachedClassifierLabel = stableLabel;
          _cachedClassifierConf = confidence;
          for (final det in dets) {
            det['classifier'] = stableLabel;
            det['classifierConf'] = confidence;
          }
          
          // Debug output
          if (_showDebugInfo) {
            debugPrint('========== ${secondaryModel!.modelName.toUpperCase()} DEBUG ==========');
            debugPrint('Crop size: ${paddedRight - paddedLeft}x${paddedBottom - paddedTop} -> 224x224');
            debugPrint('Result: label=$rawLabel, conf=${confidence.toStringAsFixed(3)}');
            debugPrint('Smoothed: $stableLabel');
            debugPrint('=====================================');
          }
        } else if (secondaryModelType == SecondaryModelType.embedding) {
          // Embedding result: has embedding vector
          final embedding = result.embedding ?? [];
          
          // Cache the embedding for registration
          _cachedEmbedding = embedding;
          
          // Match against all registered people
          final String matchedName = _findClosestMatch(embedding);
          
          // Find similarity score for debug output
          double matchScore = 0.0;
          if (registeredPeople.isNotEmpty && embedding.isNotEmpty) {
            registeredPeople.forEach((name, refEmb) {
              final sim = cosineSimilarity(refEmb, embedding);
              if (sim > matchScore) {
                matchScore = sim;
              }
            });
          }
          
          // Cache the result to prevent flickering on non-inference frames
          _cachedEmbeddingLabel = matchedName;
          _cachedEmbeddingConf = matchScore;
          
          // Store result like classifier
          for (final det in dets) {
            det['classifier'] = matchedName;
            det['classifierConf'] = matchScore;
            det['embedding'] = embedding;
          }
          
          // ALWAYS show debug info for embedding (important!)
          debugPrint('📊 EMBEDDING RECOGNITION:');
          debugPrint('   Dim: ${embedding.length}');
          debugPrint('   Database: ${registeredPeople.keys.toList()}');
          debugPrint('   Match: $matchedName (score: ${matchScore.toStringAsFixed(3)})');
          debugPrint('   Threshold: $_embeddingThreshold');
          if (registeredPeople.isNotEmpty) {
            registeredPeople.forEach((name, refEmb) {
              final sim = cosineSimilarity(refEmb, embedding);
              debugPrint('   → $name: ${sim.toStringAsFixed(3)}');
            });
          }
        }
      } catch (e, st) {
        debugPrint('Secondary inference error: $e\n$st');
      }
  }

  // Find closest match from registered people database
  String _findClosestMatch(List<double> embedding) {
    if (registeredPeople.isEmpty) return "UNKNOWN";
    
    String bestMatch = "UNKNOWN";
    double bestScore = 0.0;
    
    registeredPeople.forEach((name, refEmb) {
      final similarity = cosineSimilarity(refEmb, embedding);
      if (similarity > bestScore) {
        bestScore = similarity;
        bestMatch = name;
      }
    });
    
    // Only return match if above threshold
    return bestScore > _embeddingThreshold ? bestMatch : "UNKNOWN";
  }

  // Show name input dialog for face registration
  Future<String?> _showNameInputDialog(BuildContext context) async {
    final controller = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Register Face'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context, controller.text);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Show face management dialog to view, edit, and delete registered faces
  void _showFaceManagementDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Manage Faces'),
            Text(
              '(${registeredPeople.length})',
              style: TextStyle(color: Colors.purpleAccent, fontSize: 14),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: registeredPeople.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.face_6, size: 48, color: Colors.purpleAccent.withOpacity(0.3)),
                    const SizedBox(height: 12),
                    Text(
                      'No registered faces yet',
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: registeredPeople.length,
                itemBuilder: (context, index) {
                  final names = registeredPeople.keys.toList();
                  final name = names[index];
                  final embedding = registeredPeople[name]!;
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purpleAccent.withOpacity(0.15), Colors.purpleAccent.withOpacity(0.05)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.purpleAccent.withOpacity(0.3), width: 1),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Embedding: ${embedding.length} dims',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Delete button
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              registeredPeople.remove(name);
                            });
                            _saveFacesToStorage();
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('❌ Deleted: $name'),
                                duration: const Duration(seconds: 2),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            
                            // Close dialog if all faces deleted
                            if (registeredPeople.isEmpty) {
                              Navigator.pop(context);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (registeredPeople.isNotEmpty)
            TextButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear All Faces?'),
                    content: const Text('This will delete all registered faces. This action cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => registeredPeople.clear());
                          _saveFacesToStorage();
                          Navigator.pop(ctx);
                          Navigator.pop(context);
                          
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('❌ All faces cleared'),
                              duration: Duration(seconds: 2),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
    );
  }

  // Smoothing function to stabilize predictions across frames
  String _getSmoothedPrediction(String rawLabel, double confidence) {
    // If confidence is too low, keep last stable prediction
    if (confidence < _minSecondaryConfidence && _lastStableLabel != null) {
      return _lastStableLabel!;
    }
    
    // Add to prediction history
    const historyKey = 'main'; // Use single key for simplicity, or use detection ID for multi-face
    _predictionHistory[historyKey] ??= [];
    _predictionHistory[historyKey]!.add(rawLabel);
    
    // Keep only recent predictions
    if (_predictionHistory[historyKey]!.length > _smoothingWindow) {
      _predictionHistory[historyKey]!.removeAt(0);
    }
    
    // Count occurrences (voting)
    final counts = <String, int>{};
    for (final pred in _predictionHistory[historyKey]!) {
      counts[pred] = (counts[pred] ?? 0) + 1;
    }
    
    // Find most common prediction
    String mostCommon = rawLabel;
    int maxCount = 0;
    counts.forEach((label, count) {
      if (count > maxCount) {
        maxCount = count;
        mostCommon = label;
      }
    });
    
    // Require majority (more than half) to change prediction
    final threshold = (_smoothingWindow / 2).ceil();
    if (maxCount >= threshold) {
      if (mostCommon == _lastStableLabel) {
        _stableCount++;
      } else {
        // Only switch if we've seen the new prediction consistently
        if (_stableCount < 2 && _lastStableLabel != null) {
          return _lastStableLabel!;
        }
        _stableCount = 1;
      }
      _lastStableLabel = mostCommon;
      return mostCommon;
    }
    
    // Not enough consensus, keep previous
    return _lastStableLabel ?? rawLabel;
  }

  // Save registered faces to persistent storage
  Future<void> _saveFacesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert Map to JSON-serializable format
      final faceData = <String, dynamic>{};
      registeredPeople.forEach((name, embedding) {
        faceData[name] = embedding;
      });
      
      // Store as JSON string
      final jsonString = jsonEncode(faceData);
      await prefs.setString('registered_faces', jsonString);
      
      debugPrint('💾 Saved ${registeredPeople.length} faces to storage');
    } catch (e) {
      debugPrint('❌ Error saving faces: $e');
    }
  }

  // Load registered faces from persistent storage
  Future<void> _loadFacesFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('registered_faces');
      
      if (jsonString != null && jsonString.isNotEmpty) {
        final faceData = jsonDecode(jsonString) as Map<String, dynamic>;
        
        // Reconstruct registeredPeople Map
        registeredPeople.clear();
        faceData.forEach((name, embeddingList) {
          // Convert dynamic list to List<double>
          registeredPeople[name] = List<double>.from(embeddingList as List);
        });
        
        debugPrint('📂 Loaded ${registeredPeople.length} faces from storage');
        debugPrint('   People: ${registeredPeople.keys.toList()}');
      } else {
        debugPrint('📂 No saved faces found');
      }
    } catch (e) {
      debugPrint('❌ Error loading faces: $e');
    }
  }

  // Converts YUV420 camera image to `image` package RGB image (image v4 API).
  img.Image _convertCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image imgImage = img.Image(width: width, height: height);

    final Plane planeY = image.planes[0];
    final Plane planeU = image.planes[1];
    final Plane planeV = image.planes[2];

    final Uint8List y = planeY.bytes;
    final Uint8List u = planeU.bytes;
    final Uint8List v = planeV.bytes;

    final int uvRowStride = planeU.bytesPerRow;
    final int uvPixelStride = planeU.bytesPerPixel ?? 1;

    for (int h = 0; h < height; h++) {
      for (int w = 0; w < width; w++) {
        final int yIndex = h * planeY.bytesPerRow + w;
        final int uvIndex = (h >> 1) * uvRowStride + (w >> 1) * uvPixelStride;

        final int yVal = y[yIndex] & 0xff;
        final int uVal = u[uvIndex] & 0xff;
        final int vVal = v[uvIndex] & 0xff;

        int r = (yVal + (1.370705 * (vVal - 128))).round();
        int g = (yVal - (0.337633 * (uVal - 128)) - (0.698001 * (vVal - 128))).round();
        int b = (yVal + (1.732446 * (uVal - 128))).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        imgImage.setPixelRgb(w, h, r, g, b);
      }
    }

    return imgImage;
  }

  

  @override
  void dispose() {
    controller?.dispose();
    vision.closeYoloModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isReady = controller != null && controller!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: !isReady
        ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
        : Stack(
            fit: StackFit.expand,
            children: [
              // Full screen camera preview
              Positioned.fill(
                child: CameraPreview(controller!),
              ),

              

              if (detections != null)
                ...detections!.map((d) => _buildBoundingBox(d)),

              // Stats Panel (Top Left) - positioned below safe area
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withOpacity(0.75), Colors.black.withOpacity(0.55)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.6), width: 1),
                    boxShadow: [
                      BoxShadow(color: Colors.greenAccent.withOpacity(0.15), blurRadius: 10, spreadRadius: 1),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.greenAccent, blurRadius: 6)],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text("${fps.toStringAsFixed(1)} FPS",
                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 10),
                      Text("${inferenceTime.toStringAsFixed(0)}ms",
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                    ],
                  ),
                ),
              ),

              // Mode Selector Dropdown (Top Left)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.75), Colors.black.withOpacity(0.55)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: secondaryModelType == SecondaryModelType.classifier 
                          ? Colors.orangeAccent.withOpacity(0.6) 
                          : Colors.purpleAccent.withOpacity(0.6), 
                        width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: secondaryModelType == SecondaryModelType.classifier 
                            ? Colors.orangeAccent.withOpacity(0.2) 
                            : Colors.purpleAccent.withOpacity(0.2), 
                          blurRadius: 10, 
                          spreadRadius: 1),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          color: Colors.white70,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        DropdownButton<SecondaryModelType>(
                          value: secondaryModelType,
                          dropdownColor: Colors.grey[900],
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem(
                              value: SecondaryModelType.classifier,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.category, color: Colors.orangeAccent, size: 16),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "Classifier",
                                    style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: SecondaryModelType.embedding,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.face, color: Colors.purpleAccent, size: 16),
                                  const SizedBox(width: 6),
                                  const Text(
                                    "Embedding",
                                    style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (SecondaryModelType? newMode) async {
                            if (newMode != null && newMode != secondaryModelType) {
                              // Dispose old model
                              secondaryModel?.dispose();
                              
                              // Switch mode
                              setState(() {
                                secondaryModelType = newMode;
                                isSecondaryModelLoaded = false;
                                registeredPeople.clear();
                                _cachedEmbedding = null;
                              });
                              
                              // Load new model
                              try {
                                secondaryModel = _createSecondaryModel(newMode);
                                await secondaryModel!.load();
                                
                                // Reload saved faces if switching to embedding mode
                                if (newMode == SecondaryModelType.embedding) {
                                  await _loadFacesFromStorage();
                                }
                                
                                setState(() => isSecondaryModelLoaded = true);
                                
                                debugPrint('✅ Switched to ${secondaryModel!.modelName}');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("✅ Switched to ${newMode == SecondaryModelType.classifier ? 'Classifier' : 'Embedding'} Mode"),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: newMode == SecondaryModelType.classifier ? Colors.orangeAccent : Colors.purpleAccent,
                                  ),
                                );
                              } catch (e) {
                                debugPrint('❌ Error switching mode: $e');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("❌ Error: $e")),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                ),
              ),

              // Both Threshold Sliders (Top Right, Stacked Vertically)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // YOLO Threshold Slider
                    Container(
                      width: 130,
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withOpacity(0.75), Colors.black.withOpacity(0.55)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1),
                        boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(0.1), blurRadius: 6, spreadRadius: 0)],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text("YOLO", style: TextStyle(color: Colors.cyanAccent.withOpacity(0.8), fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: 1)),
                              Text("${(confidenceThreshold * 100).toInt()}%", style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                              activeTrackColor: Colors.cyanAccent,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.cyanAccent,
                              overlayColor: Colors.cyanAccent.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: confidenceThreshold,
                              min: 0.1,
                              max: 0.9,
                              onChanged: (value) => setState(() => confidenceThreshold = value),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Secondary Model Threshold Slider
                    Container(
                      width: 130,
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black.withOpacity(0.75), Colors.black.withOpacity(0.55)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.6), width: 1),
                        boxShadow: [BoxShadow(color: Colors.amberAccent.withOpacity(0.1), blurRadius: 6, spreadRadius: 0)],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                secondaryModelType == SecondaryModelType.classifier ? "CLASS" : "EMBD",
                                style: TextStyle(color: Colors.amberAccent.withOpacity(0.8), fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: 1),
                              ),
                              Text(
                                "${(secondaryModelType == SecondaryModelType.embedding ? (_embeddingThreshold * 100).toInt() : (_minSecondaryConfidence * 100).toInt())}%",
                                style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                              activeTrackColor: Colors.amberAccent,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.amberAccent,
                              overlayColor: Colors.amberAccent.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: secondaryModelType == SecondaryModelType.embedding ? _embeddingThreshold : _minSecondaryConfidence,
                              min: 0.1,
                              max: 0.9,
                              onChanged: (value) {
                                setState(() {
                                  if (secondaryModelType == SecondaryModelType.embedding) {
                                    _embeddingThreshold = value;
                                  } else {
                                    _minSecondaryConfidence = value;
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Detection List (Bottom Left) - safe area aware
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 12,
                right: 80,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withOpacity(0.85), Colors.black.withOpacity(0.65)],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 15, spreadRadius: 1),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: detections == null || detections!.isEmpty
                      ? Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent.withOpacity(0.5)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text("SCANNING",
                                style: TextStyle(color: Colors.white.withOpacity(0.4), letterSpacing: 2, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    Icon(Icons.radar, color: Colors.greenAccent, size: 14),
                                    const SizedBox(width: 6),
                                    Text("DETECTED",
                                      style: TextStyle(color: Colors.greenAccent.withOpacity(0.9), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.greenAccent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                                      ),
                                      child: Text("${detections!.length}",
                                        style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  itemCount: detections!.length,
                                  itemBuilder: (context, index) {
                                    final d = detections![index];
                                    final hasClassifier = d['classifier'] != null;
                                    return Container(
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: hasClassifier 
                                            ? [Colors.purpleAccent.withOpacity(0.2), Colors.purpleAccent.withOpacity(0.08)]
                                            : [Colors.greenAccent.withOpacity(0.15), Colors.greenAccent.withOpacity(0.05)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: hasClassifier ? Colors.purpleAccent.withOpacity(0.5) : Colors.greenAccent.withOpacity(0.5), 
                                          width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(d['tag'] ?? "Object",
                                            style: TextStyle(color: Colors.greenAccent.withOpacity(0.9), fontWeight: FontWeight.w600, fontSize: 12)),
                                          if (hasClassifier) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.purpleAccent.withOpacity(0.3),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(d['classifier'].toString(),
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                            ),
                                          ],
                                          const SizedBox(width: 6),
                                          Text("${((d['box'][4] ?? 0) * 100).toStringAsFixed(0)}%",
                                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                  ),
                ),
              ),

              // Camera Switch Button (Bottom Right)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                right: 12,
                child: GestureDetector(
                  onTap: _switchCamera,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.7), Colors.black.withOpacity(0.5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.cyanAccent.withOpacity(0.2), blurRadius: 10, spreadRadius: 1),
                      ],
                    ),
                    child: Icon(
                      isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                      color: Colors.cyanAccent,
                      size: 24,
                    ),
                  ),
                ),
              ),

              // Register Face Button (Bottom Right, Stacked Above Camera Switch) - for embedding mode
              if (secondaryModelType == SecondaryModelType.embedding)
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 75,
                  right: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      // Register Face Button
                      ElevatedButton(
                        onPressed: () async {
                          if (_cachedEmbedding != null) {
                            final name = await _showNameInputDialog(context);
                            if (name != null && name.isNotEmpty) {
                              registeredPeople[name] = List.from(_cachedEmbedding!);
                              
                              // Save to persistent storage
                              await _saveFacesToStorage();
                              
                              debugPrint("✅ Registered: $name (embedding dim: ${_cachedEmbedding!.length})");
                              debugPrint("📊 Total people: ${registeredPeople.keys.toList()}");
                              
                              if (mounted) {
                                setState(() {}); // Update UI to show new count
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("✅ $name Registered!"),
                                    duration: const Duration(seconds: 2),
                                    backgroundColor: Colors.purpleAccent,
                                  ),
                                );
                              }
                            }
                          } else {
                            debugPrint("❌ No face detected yet");
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        child: const Text("Register", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      // Manage Faces Button
                      ElevatedButton.icon(
                        onPressed: () => _showFaceManagementDialog(context),
                        icon: Icon(Icons.manage_accounts, size: 16, color: Colors.white),
                        label: Text(
                          "(${registeredPeople.length})",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent.withOpacity(0.7),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
    );
  }
  Widget _buildBoundingBox(Map<String, dynamic> d) {
    if (controller == null) return const SizedBox.shrink();
    final previewSize = controller!.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;

    // flutter_vision provides [x1, y1, x2, y2, score]
    final List<dynamic> box = d['box'];
    final double x1 = box[0];
    final double y1 = box[1];
    final double x2 = box[2];
    final double y2 = box[3];
    final double confidence = box[4];

    // Scaling factors - map from camera resolution to screen size
    final double scaleX = screenSize.width / previewSize.height;
    final double scaleY = screenSize.height / previewSize.width;

    return Positioned(
      left: x1 * scaleX,
      top: y1 * scaleY,
      width: (x2 - x1) * scaleX,
      height: (y2 - y1) * scaleY,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.greenAccent, width: 2),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            color: Colors.greenAccent,
            padding: const EdgeInsets.all(2),
            child: Text(
              "${d['tag']} ${(confidence * 100).toStringAsFixed(0)}% ${d['classifier'] != null ? '(' + d['classifier'].toString() + ')' : ''}",
              style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
