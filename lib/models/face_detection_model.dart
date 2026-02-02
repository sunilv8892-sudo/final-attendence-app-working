/// Face detection result from M1 module
class DetectedFace {
  final double x;
  final double y;
  final double width;
  final double height;
  final double confidence;

  DetectedFace({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.confidence,
  });

  /// Get bounding box as [x, y, width, height]
  List<double> get boundingBox => [x, y, width, height];

  /// Calculate center point of the face
  Offset get center => Offset(x + width / 2, y + height / 2);

  /// Validate if face detection is valid
  bool get isValid => x >= 0 && y >= 0 && width > 0 && height > 0 && confidence > 0 && confidence <= 1.0;

  @override
  String toString() => 'DetectedFace(x: $x, y: $y, w: $width, h: $height, conf: $confidence)';
}

class Offset {
  final double dx;
  final double dy;

  Offset(this.dx, this.dy);
}
