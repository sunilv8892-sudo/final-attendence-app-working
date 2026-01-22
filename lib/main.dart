import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription>? cameras;

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
  // Second model (classifier)
  bool isSecondModelLoaded = false;
  final String secondModelPath = 'assets/models/second_model.tflite';
  final String secondLabelsPath = 'assets/models/second_labels.txt';
  Interpreter? classifierInterpreter;
  List<String> classifierLabels = [];
  int classifierInputSize = 224;
  
  // Stats
  double fps = 0;
  double inferenceTime = 0;
  DateTime? lastInference;
  double confidenceThreshold = 0.4;
  
  // Prediction smoothing for stability
  final Map<String, List<String>> _predictionHistory = {}; // Track recent predictions per detection
  final int _smoothingWindow = 5; // Number of frames to average
  final double _minClassifierConfidence = 0.6; // Minimum confidence to accept prediction
  String? _lastStableLabel; // Last stable prediction
  int _stableCount = 0; // Frames with same prediction

  @override
  void initState() {
    super.initState();
    _initEverything();
  }

  Future<void> _initEverything() async {
    // 1. Permissions
    final status = await Permission.camera.request();
    if (!status.isGranted) return;

    // 2. Load Model
    try {
      await vision.loadYoloModel(
        labels: 'assets/models/labels.txt',
        modelPath: 'assets/models/model.tflite',
        modelVersion: "yolov8", 
        numThreads: 1,
        useGpu: false, // Defaulting to False for higher compatibility with nano models
      );
      setState(() => isModelLoaded = true);
    } catch (e) {
      debugPrint("Error loading model: $e");
    }

    // Load second (classifier) model using tflite_flutter interpreter
    try {
      // For tflite_flutter, use the full asset path
      classifierInterpreter = await Interpreter.fromAsset('assets/models/second_model.tflite');
      final rawLabels = await rootBundle.loadString(secondLabelsPath);
      classifierLabels = rawLabels
          .split(RegExp(r'\r?\n'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .map((s) {
            // Handle "0 Happy" format - extract label after number
            final parts = s.split(RegExp(r'\s+'));
            return parts.length > 1 ? parts.sublist(1).join(' ') : s;
          })
          .toList();
      // Try to get input size from model
      final inputShape = classifierInterpreter!.getInputTensor(0).shape;
      debugPrint('Classifier inputShape: $inputShape');
      if (inputShape.length >= 3) {
        classifierInputSize = inputShape[1];
      }
      debugPrint('Classifier loaded: inputSize=$classifierInputSize labels=$classifierLabels');
      setState(() => isSecondModelLoaded = true);
    } catch (e, st) {
      debugPrint('Second model not loaded (optional): $e\n$st');
      isSecondModelLoaded = false;
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
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await controller!.initialize();

      // Start streaming
      controller!.startImageStream((image) {
        if (!isInferenceRunning && isModelLoaded) {
          isInferenceRunning = true;
          _runDetection(image);
        }
      });

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera init error: $e");
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
        classThreshold: 0.4,
      );

      final end = DateTime.now();
      if (mounted) {
        setState(() {
          detections = results;
          inferenceTime = end.difference(start).inMilliseconds.toDouble();
          if (lastInference != null) {
            fps = 1000 / end.difference(lastInference!).inMilliseconds;
          }
          lastInference = end;
        });
        // If second classifier is loaded, run it on detected regions
        if (isSecondModelLoaded && detections != null && detections!.isNotEmpty) {
          _classifyDetectionsWithInterpreter(image, detections!);
        }
      }
    } catch (e) {
      debugPrint("Detection error: $e");
    } finally {
      isInferenceRunning = false;
    }
  }

  // Run TFLite classifier using tflite_flutter interpreter on each detection
  Future<void> _classifyDetectionsWithInterpreter(CameraImage image, List<Map<String, dynamic>> dets) async {
    if (controller == null || classifierInterpreter == null) return;
    final previewSize = controller!.value.previewSize;
    if (previewSize == null) return;

    img.Image? fullImage;
    try {
      fullImage = _convertCameraImage(image);
    } catch (e) {
      debugPrint('Failed to convert camera image: $e');
      return;
    }

    for (final d in dets) {
      try {
        final List<dynamic> box = d['box'];
        final double x1 = box[0];
        final double y1 = box[1];
        final double x2 = box[2];
        final double y2 = box[3];

        final double scaleX = image.width / previewSize.height;
        final double scaleY = image.height / previewSize.width;

        int left = (x1 * scaleX).toInt();
        int top = (y1 * scaleY).toInt();
        int right = (x2 * scaleX).toInt();
        int bottom = (y2 * scaleY).toInt();

        left = left.clamp(0, fullImage.width - 1);
        top = top.clamp(0, fullImage.height - 1);
        right = right.clamp(left + 1, fullImage.width);
        bottom = bottom.clamp(top + 1, fullImage.height);

        final cropW = right - left;
        final cropH = bottom - top;
        if (cropW <= 0 || cropH <= 0) continue;

        final cropped = img.copyCrop(fullImage, x: left, y: top, width: cropW, height: cropH);
        final resized = img.copyResize(cropped, width: classifierInputSize, height: classifierInputSize);

        // Get input/output tensor info
        final inputTensor = classifierInterpreter!.getInputTensor(0);
        final outputTensor = classifierInterpreter!.getOutputTensor(0);
        final inputType = inputTensor.type;
        final numClasses = outputTensor.shape.last;

        // Prepare input based on tensor type
        dynamic input;
        if (inputType == TensorType.uint8) {
          // Quantized model expects uint8 [0-255]
          final bytes = Uint8List(1 * classifierInputSize * classifierInputSize * 3);
          int idx = 0;
          for (int py = 0; py < classifierInputSize; py++) {
            for (int px = 0; px < classifierInputSize; px++) {
              final pixel = resized.getPixel(px, py);
              bytes[idx++] = pixel.r.toInt();
              bytes[idx++] = pixel.g.toInt();
              bytes[idx++] = pixel.b.toInt();
            }
          }
          input = bytes.reshape([1, classifierInputSize, classifierInputSize, 3]);
        } else {
          // Float model expects normalized floats
          final floats = Float32List(1 * classifierInputSize * classifierInputSize * 3);
          int idx = 0;
          for (int py = 0; py < classifierInputSize; py++) {
            for (int px = 0; px < classifierInputSize; px++) {
              final pixel = resized.getPixel(px, py);
              floats[idx++] = pixel.r / 255.0;
              floats[idx++] = pixel.g / 255.0;
              floats[idx++] = pixel.b / 255.0;
            }
          }
          input = floats.reshape([1, classifierInputSize, classifierInputSize, 3]);
        }

        // Prepare output buffer
        dynamic output;
        if (outputTensor.type == TensorType.uint8) {
          output = Uint8List(numClasses).reshape([1, numClasses]);
        } else {
          output = Float32List(numClasses).reshape([1, numClasses]);
        }

        // Run inference
        classifierInterpreter!.run(input, output);

        // Find max probability
        double maxVal = -1.0;
        int maxIdx = 0;
        for (int i = 0; i < numClasses; i++) {
          final val = (output[0][i] is int) ? output[0][i].toDouble() : output[0][i];
          if (val > maxVal) {
            maxVal = val;
            maxIdx = i;
          }
        }

        final rawLabel = (classifierLabels.isNotEmpty && maxIdx < classifierLabels.length)
            ? classifierLabels[maxIdx]
            : maxIdx.toString();
        
        // Apply prediction smoothing for stability
        final String stableLabel = _getSmoothedPrediction(rawLabel, maxVal);
        
        debugPrint('Classified: $rawLabel (conf: ${maxVal.toStringAsFixed(2)}) -> Stable: $stableLabel');
        setState(() { d['classifier'] = stableLabel; d['classifierConf'] = maxVal; });
      } catch (e, st) {
        debugPrint('Classification error: $e\n$st');
      }
    }
  }

  // Smoothing function to stabilize predictions across frames
  String _getSmoothedPrediction(String rawLabel, double confidence) {
    // If confidence is too low, keep last stable prediction
    if (confidence < _minClassifierConfidence && _lastStableLabel != null) {
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

              // Confidence Slider (Top Right) - positioned below safe area
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 12,
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withOpacity(0.75), Colors.black.withOpacity(0.55)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1),
                    boxShadow: [
                      BoxShadow(color: Colors.cyanAccent.withOpacity(0.15), blurRadius: 10, spreadRadius: 1),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("CONF",
                            style: TextStyle(color: Colors.cyanAccent.withOpacity(0.8), fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 1)),
                          Text("${(confidenceThreshold * 100).toInt()}%",
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                          activeTrackColor: Colors.cyanAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.cyanAccent,
                          overlayColor: Colors.cyanAccent.withOpacity(0.2),
                        ),
                        child: Slider(
                          value: confidenceThreshold,
                          min: 0.1,
                          max: 0.9,
                          onChanged: (value) {
                            setState(() {
                              confidenceThreshold = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Detection List (Bottom) - safe area aware
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 16,
                left: 12,
                right: 12,
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
                bottom: MediaQuery.of(context).padding.bottom + 110,
                right: 16,
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
