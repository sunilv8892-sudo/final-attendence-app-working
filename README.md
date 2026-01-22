# Multi-Model YOLO + Emotion Classification Flutter App

A real-time object detection app using **YOLOv8** with a secondary **emotion classification** model. Detects faces and classifies emotions (Happy, Sad, Surprised, Fearful, Angry, Disgusted, Neutral) in real-time.

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.x-blue?logo=dart)
![TFLite](https://img.shields.io/badge/TensorFlow%20Lite-Supported-orange?logo=tensorflow)

---

## 📱 Features

- **Real-time YOLO Detection** - Detect objects/faces using YOLOv8 model
- **Emotion Classification** - Classify detected faces into 7 emotion categories
- **Camera Switching** - Switch between front and back cameras
- **Adjustable Confidence** - Real-time confidence threshold slider
- **FPS & Inference Stats** - Live performance monitoring
- **Modern UI** - Clean, responsive overlay interface

---

## 🛠️ Prerequisites

Before you begin, ensure you have the following installed on your system:

### 1. Flutter SDK
```bash
# Download from: https://docs.flutter.dev/get-started/install
# Add Flutter to PATH

# Verify installation
flutter doctor
```

### 2. Android Studio (for Android builds)
- Download from: https://developer.android.com/studio
- Install Android SDK (API 21+)
- Set up Android emulator or connect physical device

### 3. Git
```bash
# Download from: https://git-scm.com/downloads
git --version
```

---

## 🚀 Setup Instructions

### Step 1: Clone the Repository
```bash
git clone https://github.com/sunilv8892-sudo/final-flutter-.git
cd final-flutter-
```

### Step 2: Install Flutter Dependencies
```bash
flutter pub get
```

### Step 3: Verify Setup
```bash
flutter doctor
```
Ensure there are no critical issues (red X marks).

### Step 4: Connect Device
- **Physical Device**: Enable USB debugging and connect via USB
- **Emulator**: Start an Android emulator from Android Studio

Check connected devices:
```bash
flutter devices
```

### Step 5: Run the App
```bash
# Run in debug mode
flutter run

# Or specify device
flutter run -d <device_id>
```

---

## 📦 Project Structure

```
multi-model-support-yolo-main/
├── lib/
│   └── main.dart              # Main app code (YOLO + classifier)
├── assets/
│   └── models/
│       ├── model.tflite       # YOLOv8 detection model
│       ├── labels.txt         # YOLO class labels
│       ├── second_model.tflite # Emotion classifier model
│       └── second_labels.txt  # Emotion labels
├── android/                   # Android platform files
├── ios/                       # iOS platform files
├── pubspec.yaml              # Flutter dependencies
└── README.md
```

---

## 📋 Dependencies

The app uses the following Flutter packages:

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_vision` | ^2.0.0 | YOLO model inference |
| `tflite_flutter` | ^0.11.0 | TFLite interpreter for classifier |
| `camera` | ^0.11.0+1 | Camera access |
| `image` | ^4.0.0 | Image processing |
| `permission_handler` | ^11.0.0 | Runtime permissions |

---

## 🏗️ Building Release APK

### Debug Build
```bash
flutter build apk --debug
```

### Release Build
```bash
flutter build apk --release
```

The APK will be located at:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 🎯 How It Works

1. **Camera Stream** - App captures frames from device camera
2. **YOLO Detection** - Each frame passes through YOLOv8 model to detect faces/objects
3. **Emotion Classification** - For each detected face region:
   - Crop the bounding box area
   - Resize to 224x224 (classifier input size)
   - Run through emotion classifier model
   - Display emotion label on bounding box
4. **UI Overlay** - Results displayed with bounding boxes and labels

---

## 🔧 Customization

### Replace Models

1. **YOLO Model**: Replace `assets/models/model.tflite` with your YOLOv8 `.tflite` model
2. **Labels**: Update `assets/models/labels.txt` with your class names
3. **Classifier**: Replace `assets/models/second_model.tflite` with your classifier
4. **Classifier Labels**: Update `assets/models/second_labels.txt`

### Adjust Parameters

In `lib/main.dart`:
```dart
// Confidence threshold (default: 0.4)
double confidenceThreshold = 0.4;

// Classifier input size (auto-detected from model, default: 224)
int classifierInputSize = 224;
```

---

## ⚠️ Troubleshooting

### Camera Permission Denied
- Go to device Settings → Apps → [App Name] → Permissions → Enable Camera

### Model Not Loading
- Verify model files exist in `assets/models/`
- Check `pubspec.yaml` includes:
  ```yaml
  flutter:
    assets:
      - assets/models/
  ```

### Build Errors
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

### Gradle Issues
```bash
# Navigate to android folder and sync
cd android
./gradlew clean
cd ..
flutter run
```

---

## 📄 License

This project is for educational purposes.

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push to branch
5. Open a Pull Request

---

**Made with ❤️ using Flutter**
