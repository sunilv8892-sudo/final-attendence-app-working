import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;

/// M1: Face Detection Module using MediaPipe
/// Detects faces in images with high accuracy and speed
class FaceDetectionModule {
  static const String modelName = 'MediaPipe Face Detection';
  static const double minDetectionConfidence = 0.5;

  FaceDetector? _faceDetector;

  /// Initialize MediaPipe face detector
  Future<void> initialize() async {
    // ignore: deprecated_member_use
    _faceDetector = GoogleMlKit.vision.faceDetector(
      FaceDetectorOptions(
        enableContours: false,
        enableClassification: false,
        enableLandmarks: false,
        enableTracking: false,
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
  }

  /// Detect faces in image
  Future<List<DetectedFace>> detectFaces(Uint8List imageBytes) async {
    final tempPath = await _writeBytesToTempFile(imageBytes);
    try {
      return await detectFacesFromPath(tempPath);
    } finally {
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
  }

  /// Detect faces using a file path backed input image
  Future<List<DetectedFace>> detectFacesFromPath(String path) async {
    if (_faceDetector == null) await initialize();

    final inputImage = InputImage.fromFilePath(path);
    final faces = await _faceDetector!.processImage(inputImage);
    return faces.map((face) => DetectedFace.fromMlKitFace(face)).toList();
  }

  Future<String> _writeBytesToTempFile(Uint8List bytes) async {
    final tempDir = Directory.systemTemp;
    final file = File(
      '${tempDir.path}/face_detection_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Extract face ROI from image
  Uint8List extractFaceROI(Uint8List imageBytes, DetectedFace face) {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Failed to decode image');

    final rect = face.boundingBox;
    final x = rect.left.toInt().clamp(0, image.width);
    final y = rect.top.toInt().clamp(0, image.height);
    final width = rect.width.toInt().clamp(0, image.width - x);
    final height = rect.height.toInt().clamp(0, image.height - y);

    if (width <= 0 || height <= 0) {
      throw Exception('Invalid face bounding box');
    }

    final cropped = img.copyCrop(
      image,
      x: x,
      y: y,
      width: width,
      height: height,
    );
    return Uint8List.fromList(img.encodeJpg(cropped));
  }

  /// Check if face is suitable for embedding (good quality, proper angle, etc.)
  bool isFaceSuitableForEmbedding(DetectedFace face) {
    // Check face size (should be large enough)
    final rect = face.boundingBox;
    final faceArea = rect.width * rect.height;
    if (faceArea < 10000) return false; // Too small

    // Check face angle (should be mostly frontal)
    if (face.headEulerAngleY != null && face.headEulerAngleY!.abs() > 30) {
      return false;
    }
    if (face.headEulerAngleZ != null && face.headEulerAngleZ!.abs() > 15) {
      return false;
    }

    return true;
  }

  /// Dispose resources
  void dispose() {
    _faceDetector?.close();
    _faceDetector = null;
  }
}

/// Detected face model
class DetectedFace {
  final Rect boundingBox;
  final double? headEulerAngleY; // Left-right rotation
  final double? headEulerAngleZ; // Up-down rotation
  final List<Offset> landmarks;

  DetectedFace({
    required this.boundingBox,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    required this.landmarks,
  });

  factory DetectedFace.fromMlKitFace(Face face) {
    return DetectedFace(
      boundingBox: face.boundingBox,
      headEulerAngleY: face.headEulerAngleY,
      headEulerAngleZ: face.headEulerAngleZ,
      landmarks: [], // TODO: Implement landmark extraction if needed
    );
  }
}
