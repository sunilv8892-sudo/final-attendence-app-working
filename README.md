# 🚀 Multi-Model Real-Time Mobile Vision Engine

A **production-ready Flutter application** for real-time object detection, classification, and face recognition using YOLO and TensorFlow Lite models on mobile devices.

**Status:** ✅ Fully Functional | 🎯 Feature-Complete | 📱 Mobile Optimized

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.x-blue?logo=dart)
![TFLite](https://img.shields.io/badge/TensorFlow%20Lite-Supported-orange?logo=tensorflow)
![License](https://img.shields.io/badge/License-MIT-green)

---

## ✨ Key Features

### 🎯 **Real-Time YOLO Detection**
- Detects objects/faces at 30+ FPS
- GPU acceleration enabled
- Configurable confidence threshold (0.1 - 0.9)
- Live bounding box visualization

### 🏷️ **Pluggable Secondary Models Framework**
Unique architecture supports **multiple model types** without code refactoring:
- **Classifier Mode** - Classify detected objects (me/not_me, emotions, etc.)
- **Embedding Mode** - Face verification via cosine similarity
- **Custom Models** - Easy to add your own via `SecondaryModel` interface

### 👤 **Multi-Person Face Recognition**
- Register multiple faces by name
- Automatic face matching using embedding similarity
- **Persistent storage** - Faces saved even after app closes
- **Smooth prediction** - No flickering, stable labels
- Adjustable threshold for sensitivity (0.7 default)

### 🔒 **Persistent Storage**
- Registered faces saved to phone's SharedPreferences
- Auto-loaded on app startup
- Survives app restart and phone reboot

### ⚡ **Performance Optimized**
- Frame skipping (process every 3rd frame)
- Result caching to prevent label flickering
- Prediction smoothing with voting window
- Efficient YUV → RGB conversion

---

## 🏗️ Architecture

### Two-Stage Pipeline
```
Camera Feed (30 FPS)
    ↓
YOLO Detection (FlutterVision)
    ↓ (extract face region)
Secondary Model (pluggable)
    ├─ Classifier → Label + Confidence
    ├─ Embedding → Vector + Similarity Match
    └─ Custom... (extensible)
    ↓
UI Rendering + Bounding Boxes
```

### Pluggable Framework Pattern
```dart
abstract class SecondaryModel {
  Future<void> load();
  Future<SecondaryResult> infer(img.Image crop);
  void dispose();
}

// Classifier implementation
class ClassifierModel implements SecondaryModel { ... }

// Embedding implementation
class EmbeddingModel implements SecondaryModel { ... }

// Add your own model by implementing interface!
```

---

## 🚀 Getting Started

### Prerequisites
- Flutter 3.10+
- Android 7.0+ or iOS 11.0+
- Models in `assets/models/`:
  - `model.tflite` (YOLO detection)
  - `labels.txt` (YOLO labels)
  - `second_model.tflite` (classifier)
  - `second_labels.txt` (classifier labels)
  - `embedding_model.tflite` (face embeddings)

### Installation
```bash
# Clone repository
git clone https://github.com/sunilv8892-sudo/flutter-Real-time-mobile-vision-engine.git
cd flutter-Real-time-mobile-vision-engine

# Install dependencies
flutter pub get

# Run on device
flutter run
```

---

## 📖 Usage Guide

### Mode Selection
Use the **dropdown at top-center** to switch between modes instantly:
- 🟠 **Classifier** - Classification results
- 🟣 **Embedding** - Face recognition

### Classifier Mode
1. Point at object/face
2. See detected class + confidence
3. Example: `person (happy 0.92)`

### Embedding Mode (Face Recognition)

#### Register a Face
1. Point your face at camera
2. Click **"Register Face"** button (bottom-left)
3. Enter your name in dialog
4. System saves your embedding

#### Recognize Faces
1. Point at any face
2. System compares against registered faces
3. Shows match name + similarity score
4. Example: `person (SUNIL 0.88)` ✅ or `person (UNKNOWN 0.45)` ❌

#### Data Persistence
- Registered faces automatically saved to phone
- Reopen app → Faces load automatically
- **No retraining needed!**

---

## ⚙️ Configuration

### Detection Settings (Top Right)
- **Confidence Threshold** - 0.1 to 0.9 (default: 0.25)
- Lower = more detections but noisier
- Higher = fewer but more confident detections

### Embedding Settings (Code)
Edit these in `lib/main.dart`:
```dart
double _embeddingThreshold = 0.7;        // Similarity threshold for match
int _classifyEveryNFrames = 3;           // Process every Nth frame (performance)
double _minSecondaryConfidence = 0.5;    // Min confidence for classifier
int _smoothingWindow = 5;                // Prediction smoothing window size
```

---

## 🔧 Technical Details
### Face Overlay Accuracy Fix
- **Problem**: The camera preview used a fixed `AspectRatio` and the overlay logic rotated the bounding box based on sensor orientation, which double-rotated the ML Kit face rectangles and caused the circle to land on the chin/neck.
- **Solution**: Camera preview now expands via `FittedBox(fit: BoxFit.cover)` so the rendered feed matches the display area, and the overlay mapping simply scales the ML Kit bounding box from the upright JPEG (`img.decodeImage`) to display coordinates (no rotation). The front camera mirror is applied after scaling, resulting in a stable, pixel-accurate circle around the face without manual calibration.

### Algorithms Implemented

#### Softmax Function
Converts logits to probabilities:
```dart
List<double> softmax(List<double> x) {
  double maxVal = x.reduce((a, b) => a > b ? a : b);
  final exp = x.map((e) => math.exp(e - maxVal)).toList();
  final sum = exp.reduce((a, b) => a + b);
  return exp.map((e) => e / sum).toList();
}
```

#### Cosine Similarity
Compares embedding vectors (0 = different, 1 = identical):
```dart
double cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (math.sqrt(normA) * math.sqrt(normB) + 1e-10);
}
```

#### Prediction Smoothing
Voting-based stability:
```dart
// Uses sliding window of predictions
// Requires majority to change label
// Prevents flickering from frame-to-frame noise
```

### Data Structure
```dart
Map<String, List<double>> registeredPeople = {
  "Sunil": [0.124, 0.456, 0.789, ...],  // 192-dim embedding
  "Rahul": [0.234, 0.567, 0.890, ...],
};
// Automatically saved to SharedPreferences as JSON
```

---

## 📊 Performance Metrics

| Metric | Value |
|--------|-------|
| **FPS** | 30+ (live) |
| **Detection Latency** | ~30-50ms |
| **Inference Time** | ~15-25ms (secondary model) |
| **Memory** | ~100-150MB (peak) |
| **Model Size** | ~50MB (YOLO + Classifier + Embedding) |

---

## 🔍 Debugging

### Enable Debug Output
```dart
_showDebugInfo = true;  // In _YoloDetectionPageState
```

### Console Messages
```
🔍 Embedding: dim=192                    // Embedding extracted
📊 EMBEDDING RECOGNITION:                // Recognition output
   Match: sunil (score: 0.928)          // Best match
   → sunil: 0.928                        // Individual scores
💾 Saved 1 faces to storage              // Persistence success
📂 Loaded 1 faces from storage           // Loaded on startup
```

---

## 🛠️ Extending the Framework

### Add Custom Classifier
```dart
class MyCustomClassifier implements SecondaryModel {
  @override
  Future<SecondaryResult> infer(img.Image crop) async {
    // Your inference logic here
    return SecondaryResult(
      label: 'custom_result',
      confidence: 0.95,
    );
  }
  
  // Implement other required methods...
}
```

### Register Custom Model
```dart
SecondaryModel _createSecondaryModel(SecondaryModelType type) {
  switch (type) {
    case SecondaryModelType.classifier:
      return ClassifierModel(...);
    case SecondaryModelType.embedding:
      return EmbeddingModel(...);
    case SecondaryModelType.custom:  // NEW!
      return MyCustomClassifier();
  }
}
```

---

## 📁 Project Structure
```
lib/
├── main.dart                    # Main app (1400+ lines)
│   ├── Softmax function         # Probability conversion
│   ├── Cosine similarity        # Embedding comparison
│   ├── SecondaryModel interface # Abstract pattern
│   ├── ClassifierModel          # Classification impl
│   ├── EmbeddingModel           # Face verification impl
│   ├── Persistence functions    # Storage/load
│   └── UI (Camera, Detection, Mode switching)
│
assets/
├── models/
│   ├── model.tflite             # YOLO detection
│   ├── labels.txt               # YOLO classes
│   ├── second_model.tflite      # Classifier (optional)
│   ├── second_labels.txt        # Classifier classes (optional)
│   └── embedding_model.tflite   # Face embeddings
│
pubspec.yaml
├── flutter
├── camera: ^0.11.0+1
├── flutter_vision: ^2.0.0
├── tflite_flutter: ^0.11.0
├── shared_preferences: ^2.2.0
└── permission_handler: ^11.3.1
```

---

## 📋 Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.11.0+1              # Camera streaming
  flutter_vision: ^2.0.0          # YOLO detection
  tflite_flutter: ^0.11.0         # TFLite inference
  shared_preferences: ^2.2.0      # Persistent storage
  permission_handler: ^11.3.1     # Camera permissions
  image: ^4.0.0                   # Image processing
```

---

## 🐛 Troubleshooting

### Models Not Found
**Error:** `FileSystemException: models not found`
- **Solution:** Place `.tflite` files in `assets/models/`
- Update `pubspec.yaml` assets section

### No Detections
**Error:** `0 detections found`
- **Solution:** Lower confidence threshold (0.1 - 0.2)
- Ensure lighting is adequate
- Check that model is appropriate for your objects

### Embedding Always "UNKNOWN"
**Error:** Face registers but shows UNKNOWN
- **Solution:** Check threshold (0.7 default)
- Ensure face is well-lit and centered
- Lower threshold to 0.5 if too strict

### App Crashes on Register
**Error:** `NullPointerException` on register face
- **Solution:** Ensure face is detected first
- Wait for "🔍 Embedding: dim=192" in logs
- Try different lighting/angle

---

## 🎯 Future Enhancements

- [ ] **Multi-face Detection** - Recognize multiple faces in one frame
- [ ] **Delete/Edit Registered Faces** - Manage face database UI
- [ ] **Face List Display** - Show all registered people on screen
- [ ] **Threshold Slider** - Adjust sensitivity in real-time UI
- [ ] **Alternative Models** - Support YOLOv5, v6, v7, v8n variants
- [ ] **Emotion Detection** - Classify emotions alongside face recognition
- [ ] **Profile Matching** - Store additional metadata per person

---

## 📄 License
MIT License - Feel free to use in your projects!

---

## 👨‍💻 Author
Built with ❤️ for real-time mobile vision on edge devices.

### Key Achievements
✅ **Pluggable Architecture** - Add models without refactoring  
✅ **Multi-Person Recognition** - Register unlimited faces  
✅ **Persistent Storage** - Faces survive app restart  
✅ **Smooth Predictions** - No flickering, voting-based stability  
✅ **Production Ready** - 30+ FPS, optimized memory usage  

---

## 🔗 Resources
- [YOLO Documentation](https://docs.ultralytics.com/)
- [TensorFlow Lite Flutter Guide](https://www.tensorflow.org/lite/guide/flutter)
- [Flutter Camera Plugin](https://pub.dev/packages/camera)
- [SharedPreferences Guide](https://pub.dev/packages/shared_preferences)

---

**Happy Detecting! 🚀**
