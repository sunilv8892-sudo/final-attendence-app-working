# Face Recognition Attendance System — Complete Technical Documentation

## Table of Contents
1. [Overview](#1-overview)
2. [Prerequisites & Requirements](#2-prerequisites--requirements)
3. [Project Structure](#3-project-structure)
4. [Application Architecture](#4-application-architecture)
5. [AI/ML Models Used](#5-aiml-models-used)
6. [Data Flow — Step by Step](#6-data-flow--step-by-step)
7. [Screen-by-Screen Walkthrough](#7-screen-by-screen-walkthrough)
8. [Database Layer](#8-database-layer)
9. [Module System (M1–M5)](#9-module-system-m1m5)
10. [Data Models](#10-data-models)
11. [CSV Export System](#11-csv-export-system)
12. [Configuration & Settings](#12-configuration--settings)
13. [Performance Optimizations](#13-performance-optimizations)
14. [Dependencies & Packages](#14-dependencies--packages)
15. [Build & Run Instructions](#15-build--run-instructions)
16. [Troubleshooting](#16-troubleshooting)

---

## 1. Overview

**App Name:** Face Recognition Attendance  
**Package Name:** `vision_id`  
**Version:** 1.0.0  
**Platform:** Android (primary), iOS (secondary)  
**Framework:** Flutter (Dart)  
**SDK:** `^3.10.7`

This is a **fully offline** mobile face recognition attendance system. It uses AI-powered face detection and embedding generation to automatically identify enrolled students via the device camera and mark their attendance. No internet connection is required for any feature.

### Key Capabilities
- Enroll students with facial embeddings (20+ samples per person)
- Multi-face simultaneous attendance marking (detects and marks ALL visible faces)
- Subject-based attendance tracking with teacher sessions
- Text-to-Speech voice confirmation when attendance is marked
- Automatic CSV report generation on attendance submission
- Export attendance and embeddings data as CSV
- Configurable face matching sensitivity (Low/Medium/High)
- Per-student attendance history and statistics

---

## 2. Prerequisites & Requirements

### Development Environment
| Tool | Version |
|------|---------|
| Flutter SDK | 3.10.7+ |
| Dart SDK | 3.10.7+ (bundled with Flutter) |
| Android Studio / VS Code | Latest |
| Android SDK | API 21+ (minSdkVersion) |
| Java JDK | 17+ (for Gradle) |

### Hardware Requirements (Android Device)
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| RAM | 2 GB | 4 GB+ |
| Camera | Front-facing | Front + Rear |
| Storage | 100 MB free | 500 MB+ free |
| Android OS | 5.0 (API 21) | 8.0+ (API 26+) |
| GPU | Any (XNNPack CPU fallback) | Adreno/Mali/PowerVR |

### Permissions Required
| Permission | Purpose |
|------------|---------|
| `CAMERA` | Face detection and enrollment capture |
| `WRITE_EXTERNAL_STORAGE` | Saving CSV export files |
| `READ_EXTERNAL_STORAGE` | Loading saved CSV files |

### Model Files
Place inside `assets/models/`:
- `embedding_model.tflite` — AdaFace-Mobile model (512-dimension face embeddings, ~5 MB)

---

## 3. Project Structure

```
lib/
├── main.dart                          # App entry point, MaterialApp, route table
├── main_app.dart                      # (Backup/alternate entry)
│
├── database/
│   ├── database_manager.dart          # SharedPreferences-backed data layer (singleton)
│   ├── database_connection.dart       # Connection helpers
│   └── face_recognition_database.dart # Legacy Drift database (unused)
│
├── models/
│   ├── student_model.dart             # Student data class (name, roll, class, gender, age, phone)
│   ├── embedding_model.dart           # FaceEmbedding data class (vector, studentId, captureDate)
│   ├── attendance_model.dart          # AttendanceRecord + AttendanceStatus enum
│   ├── face_detection_model.dart      # DetectedFace bounding box model
│   ├── match_result_model.dart        # MatchResult from face matching
│   └── subject_model.dart             # Subject + TeacherSession data classes
│
├── modules/
│   ├── m1_face_detection.dart         # Google ML Kit Face Detection wrapper
│   ├── m2_face_embedding.dart         # AdaFace-Mobile TFLite inference engine
│   ├── m3_face_matching.dart          # Cosine Similarity + KNN matching algorithms
│   ├── m4_attendance_management.dart  # Attendance recording, stats, CSV export logic
│   └── m5_liveness_detection.dart     # Blink-based liveness detection (EAR algorithm)
│
├── screens/
│   ├── home_screen.dart               # Dashboard with navigation grid + live stats
│   ├── enrollment_screen.dart         # Student registration + face capture
│   ├── attendance_prep_screen.dart    # Teacher name + subject selection before scan
│   ├── attendance_screen.dart         # Camera-based face scanning + attendance marking
│   ├── database_screen.dart           # Attendance Dashboard (Overview + Enrolled tabs)
│   ├── export_screen.dart             # CSV export + saved files management
│   └── settings_screen.dart           # Similarity threshold + database management
│
├── utils/
│   ├── constants.dart                 # Colors, gradients, sizing, routes, theme
│   ├── csv_export_service.dart        # Standalone CSV generation utility
│   └── theme.dart                     # (Additional theme utilities)
│
└── widgets/
    └── animated_background.dart       # Lightweight background wrapper widget

assets/
├── models/
│   └── embedding_model.tflite         # AdaFace-Mobile TFLite model
├── lottie/
│   └── success.json                   # Success animation
└── icons/
    └── vision_id.png                  # App icon

android/app/src/main/kotlin/.../MainActivity.kt
    # Native MethodChannel handler for MediaStore CSV saving
```

---

## 4. Application Architecture

### High-Level Flow

```
┌─────────────┐      ┌──────────────────┐      ┌───────────────────┐
│  main.dart   │─────>│   HomeScreen     │─────>│  Enroll Students  │
│ (MaterialApp)│      │   (Dashboard)    │      │  (Camera + Form)  │
└─────────────┘      └──────────────────┘      └───────────────────┘
                           │    │    │
                           │    │    └──────────>┌──────────────────┐
                           │    │                │  Take Attendance │
                           │    │                │  (Prep → Scan)   │
                           │    │                └──────────────────┘
                           │    └───────────────>┌──────────────────┐
                           │                     │  Database Screen │
                           │                     │  (Stats + List)  │
                           │                     └──────────────────┘
                           │
                           ├────────────────────>┌──────────────────┐
                           │                     │  Export Screen   │
                           │                     │  (CSV + Files)   │
                           │                     └──────────────────┘
                           └────────────────────>┌──────────────────┐
                                                 │  Settings Screen │
                                                 │  (Threshold etc) │
                                                 └──────────────────┘
```

### Technology Stack
| Layer | Technology |
|-------|-----------|
| UI Framework | Flutter (Material 3, Dark Theme) |
| State Management | `setState()` (StatefulWidget) |
| AI Face Detection | Google ML Kit (`google_ml_kit` — MediaPipe backend) |
| AI Face Embedding | AdaFace-Mobile via TFLite (`tflite_flutter`) |
| Face Matching | Cosine Similarity (pure Dart, no ML needed) |
| Database | `SharedPreferences` (JSON-encoded key-value storage) |
| File Export | `path_provider` + MethodChannel (Android MediaStore) |
| Voice Feedback | `flutter_tts` (Text-to-Speech) |
| Camera | `camera` plugin (CameraX backend on Android) |
| Image Processing | `image` package (crop, resize, encode) |
| Permissions | `permission_handler` |
| File Sharing | `share_plus` |

---

## 5. AI/ML Models Used

### Model 1: Google ML Kit Face Detector (M1)
- **Type:** On-device face detection neural network
- **Backend:** MediaPipe (bundled inside `google_ml_kit`)
- **Input:** JPEG image file path
- **Output:** List of `Face` objects with bounding boxes (`Rect`)
- **Configuration:**
  - `enableContours: false` — disabled for speed
  - `enableClassification: false` — no smile/eyes-open detection
  - `enableLandmarks: false` — disabled for speed
  - `enableTracking: false` — stateless per-frame
  - `minFaceSize: 0.1` — detects faces as small as 10% of image
  - `performanceMode: FaceDetectorMode.fast` — optimized for real-time
- **Performance:** ~30-50ms per frame on mid-range devices
- **Location:** `lib/modules/m1_face_detection.dart`

### Model 2: AdaFace-Mobile Embedding Model (M2)
- **Type:** TFLite face embedding neural network
- **File:** `assets/models/embedding_model.tflite`
- **Input:** 112×112×3 RGB float32 tensor (pixel values normalized to 0.0–1.0)
- **Output:** 512-dimensional float32 embedding vector
- **Normalization:** L2-normalized (unit vector) for cosine similarity
- **Interpreter:** TFLite via `tflite_flutter` package, XNNPack delegate, 4 threads
- **Performance:** ~20-40ms per face on mid-range devices
- **Location:** `lib/modules/m2_face_embedding.dart`

### Algorithm: Cosine Similarity Matching (M3)
- **Type:** Mathematical comparison (NOT a neural network)
- **Formula:** `similarity = dot(A, B) / (||A|| × ||B||)`
- **Range:** -1.0 to 1.0 (1.0 = identical vectors)
- **Thresholds:**
  - Low: 0.75 (more lenient, fewer false negatives)
  - Medium: 0.80 (balanced)
  - High: 0.90 (strict, fewer false positives)
- **Also supports:** KNN (K-Nearest Neighbors) for multi-embedding matching
- **Location:** `lib/modules/m3_face_matching.dart`

### Algorithm: Liveness Detection (M5)
- **Type:** Blink detection using Eye Aspect Ratio (EAR)
- **Method:** Monitors eye landmark distances over time to detect blink patterns
- **Threshold:** EAR < 0.3 indicates closed eyes
- **Required:** 2 blinks within 10 seconds
- **Note:** Currently available but not enforced during attendance
- **Location:** `lib/modules/m5_liveness_detection.dart`

---

## 6. Data Flow — Step by Step

### A. Student Enrollment Flow
```
1. User opens Enrollment Screen
2. Fills student info: Name, Roll Number, Class, Gender, Age, Phone
3. Camera initializes (front-facing, 480p medium resolution)
4. User clicks "Capture" or "Auto Capture":
   a. Camera takes picture → JPEG bytes
   b. ML Kit detects faces in the image
   c. Quality checks:
      - Face must be ≥ 150×150 pixels
      - Face must be centered (within 25% of image center)
   d. Face bounding box is cropped from full image
   e. Cropped face → AdaFace-Mobile generates 512D embedding vector
   f. Embedding is L2-normalized
   g. Embedding stored in memory list
5. Repeat 20 times (required enrollment samples)
6. User clicks "Save Student":
   a. Student record saved to SharedPreferences ('students' key)
   b. All 20 embedding vectors saved to SharedPreferences ('embeddings' key)
   c. Each embedding linked to student via studentId
7. Student is now enrolled and ready for attendance
```

### B. Attendance Taking Flow
```
1. User opens "Take Attendance" (navigates to Attendance Prep Screen)
2. Enters Teacher Name, selects or creates a Subject
3. Clicks "Start Attendance" → navigates to Attendance Screen
4. System initializes:
   a. Loads similarity threshold from SharedPreferences
   b. Initializes ML Kit Face Detector
   c. Initializes AdaFace-Mobile embedding model
   d. Loads ALL enrolled students from database
   e. Loads ALL embeddings for each student into memory
   f. Initializes Text-to-Speech engine
   g. Initializes front camera
5. User clicks "Scan" button → continuous scanning starts (1 frame/second):
   a. Camera takes picture → JPEG bytes
   b. ML Kit detects ALL faces in the image
   c. Filter: only faces ≥ 80×80 pixels are processed
   d. FOR EACH detected face:
      i.   Crop face from full image
      ii.  Generate 512D embedding via AdaFace-Mobile
      iii. Compare against ALL stored student embeddings using cosine similarity
      iv.  Find best match (highest similarity above threshold)
      v.   If match found:
           - Increment per-student consecutive detection counter
           - After 3 consecutive detections of SAME student:
             * Check 3-second cooldown (prevents duplicate marking)
             * Mark student as PRESENT
             * TTS announces: "[Name]'s attendance marked successfully"
             * Green circle overlay shown on face
           - While building up consecutive count: orange circle with name
      vi.  If no match: red circle overlay with "Unknown"
   e. Overlay boxes drawn on camera preview with name labels
   f. Overlays clear after 3 seconds
6. Student list at bottom shows real-time attendance status
   - Tap a student to manually toggle present/absent
7. User clicks "Submit Attendance":
   a. All marked students' attendance records saved to SharedPreferences
   b. Teacher session record created (teacherName + subjectId + date)
   c. Session attendance JSON saved (for per-subject CSV)
   d. CSV file auto-generated:
      - Format: SubjectName_YYYY-MM-DD.csv
      - Contains: Teacher Name, Subject, Date, Present/Absent student lists, totals
      - Saved to FaceAttendanceExports directory
      - Also saved to Downloads via Android MediaStore
   e. Success animation displayed
   f. Screen closes and returns to home
```

### C. Export Flow
```
1. User opens Export Screen
2. System requests storage permission
3. Resolves FaceAttendanceExports directory
4. Loads all .csv files from that directory → shows in "Saved Files"
5. "Quick Export" buttons:
   a. "Attendance CSV" → exports all-time attendance matrix (students × dates)
   b. "Embeddings CSV" → exports all embeddings with full student details
6. Each file can be shared (via share_plus) or deleted
```

---

## 7. Screen-by-Screen Walkthrough

### 7.1 Home Screen (`home_screen.dart`)
- **Route:** `/` (initial route)
- **Purpose:** Main navigation hub
- **Layout:** Header banner + 2×3 grid of navigation cards + bottom stats bar
- **Live Stats:**
  - Total enrolled students (from `getAllStudents()`)
  - Present today (unique students marked present today)
  - Total sessions (unique dates in attendance records)
- **Navigation Cards:**
  - Enroll Students → `/enroll`
  - Take Attendance → `/attendance` (goes to prep screen first)
  - Database → `/database`
  - Export → `/export`
  - Settings → `/settings`
  - Offline Operation (info card)

### 7.2 Enrollment Screen (`enrollment_screen.dart`)
- **Route:** `/enroll`
- **Purpose:** Register new students with face data
- **Sections:**
  1. **Student Information Form** — Name, Roll Number, Class, Gender dropdown, Age, Phone
  2. **Camera Preview** — Live front camera feed
  3. **Capture Controls:**
     - Manual capture button (single shot)
     - Auto-capture button (captures every ~600ms until 20 samples)
     - Progress indicator (X/20 samples)
  4. **Save Button** — Validates 20+ samples, saves student + embeddings
- **Quality Checks:** Minimum face size 150×150px, face must be centered

### 7.3 Attendance Prep Screen (`attendance_prep_screen.dart`)
- **Route:** `/attendance`
- **Purpose:** Collect teacher name and subject before scanning
- **Fields:**
  - Teacher Name (text input)
  - Subject (dropdown of existing subjects, or "Create New Subject")
- **Action:** "Start Attendance" → navigates to AttendanceScreen with teacher/subject data

### 7.4 Attendance Screen (`attendance_screen.dart`)
- **Purpose:** Camera-based face recognition and attendance marking
- **Key Features:**
  - Multi-face support (detects and marks ALL faces simultaneously)
  - Per-student consecutive detection tracking (Map<int, int>)
  - 3 consecutive detections required before marking present
  - 3-second cooldown between marks for same student
  - Face overlay boxes (green=present, orange=confirming, red=unknown)
  - Text-to-Speech voice confirmation
  - Camera switch button (front/rear)
  - Manual student toggle in list
- **Bottom Bar:** Scan/Stop button
- **FAB:** Submit Attendance (saves records + generates CSV)

### 7.5 Database Screen (`database_screen.dart`)
- **Route:** `/database`
- **Purpose:** View attendance data and enrolled students
- **Tabs:**
  1. **Overview:** System statistics (total students, sessions, records, unique dates), Attendance History grouped by date, Student Attendance summary with percentages
  2. **Enrolled:** List of all enrolled students with details, edit/delete actions, embedding count per student

### 7.6 Export Screen (`export_screen.dart`)
- **Route:** `/export`
- **Purpose:** Generate and manage CSV reports
- **Quick Export:**
  - "Attendance CSV" — Full attendance matrix (all students × all dates)
  - "Embeddings CSV" — All face embeddings with full student details (name, roll, class, gender, age, phone, enrollment date)
- **Saved Files:** Lists all CSV files in FaceAttendanceExports directory with share and delete buttons

### 7.7 Settings Screen (`settings_screen.dart`)
- **Route:** `/settings`
- **Purpose:** Configure app behavior
- **Settings:**
  - **Similarity Threshold:** Slider with 3 levels — Low (0.75), Medium (0.80), High (0.90)
  - **Database Management:** Database size info, Backup, Reset (wipe all data)
  - **Model Information:** Face detector, embedding model, matching method, dimension info
  - **About:** App version, description

---

  ### 7.8 Expression Detection Screen (`expression_detection_screen.dart`)
  - **Route:** `/expression_detection` (registered as `AppConstants.routeExpressionDetection`)
  - **Purpose:** Lightweight camera screen that detects faces using Google ML Kit and displays a simple expression label for each detected face. This screen does NOT perform attendance marking or enrollment — it is for quick expression/affect inspection and testing.
  - **Key Behavior:**
    - Initializes the ML Kit Face Detector with classification enabled and processes frames from the camera preview.
    - For each detected face, computes an expression label (e.g., "Happy", "Neutral", "Sad", "Winking", "Eyes Closed") using the heuristic in `lib/modules/m1_face_detection.dart` and stores the label on `DetectedFace.expression`.
    - Draws bounding boxes and the expression label as an overlay on the camera preview.
    - Starts/stops continuous scanning via an on-screen control; overlays update in real time.
  - **Implementation Notes:**
    - Uses the existing ML Kit wrapper at `lib/modules/m1_face_detection.dart` with classification enabled (smile/eye probabilities) and a lightweight heuristic mapping to textual labels.
    - No stateful attendance logic; UI intentionally simplified to avoid layout constraint issues seen in other screens.
    - Useful for QA, model verification, and demonstrations.


## 8. Database Layer

### Storage Engine: SharedPreferences
Instead of SQLite/Drift, the app uses `SharedPreferences` with JSON-encoded lists for simplicity and reliability. Data is stored as string lists:

| Key | Type | Contents |
|-----|------|----------|
| `students` | `List<String>` | JSON-encoded Student objects |
| `embeddings` | `List<String>` | JSON-encoded FaceEmbedding objects (contains vector arrays) |
| `attendance` | `List<String>` | JSON-encoded AttendanceRecord objects |
| `subjects` | `List<String>` | JSON-encoded Subject objects |
| `teacherSessions` | `List<String>` | JSON-encoded TeacherSession objects |
| `similarity_threshold` | `double` | Current similarity threshold (0.75/0.80/0.90) |
| `session_attendance_*` | `String` | Per-session attendance map (JSON: studentId → status) |

### Singleton Pattern
`DatabaseManager` is a singleton via factory constructor. All screens share the same instance, ensuring data consistency.

### Deduplication
- `getAttendanceForDate()` — Deduplicates by keeping latest record per student per date
- `getAttendanceStats()` — Deduplicates by keeping latest record per date per student

---

## 9. Module System (M1–M5)

### M1: Face Detection (`m1_face_detection.dart`)
- **Wraps:** Google ML Kit Face Detector (MediaPipe backend)
- **Input:** Image bytes → writes to temp file → `InputImage.fromFilePath()`
- **Output:** `List<DetectedFace>` with `Rect boundingBox`, head angles, landmarks
- **Quality Check:** `isFaceSuitableForEmbedding()` — validates face area > 10000px² and head angle < 30°

### M2: Face Embedding (`m2_face_embedding.dart`)
- **Wraps:** TFLite interpreter for AdaFace-Mobile
- **Pipeline:**
  1. Decode image bytes → `img.Image`
  2. Resize to 112×112 pixels
  3. Convert to RGB float32 array (normalized 0.0–1.0)
  4. Reshape to [1, 112, 112, 3] tensor
  5. Run TFLite inference
  6. Extract 512D output vector
  7. L2-normalize to unit vector
- **Thread Config:** 4 threads, XNNPack delegate

### M3: Face Matching (`m3_face_matching.dart`)
- **Cosine Similarity:** Compares two embedding vectors
- **KNN Match:** Compares against all database embeddings, returns top-K matches
- **Euclidean Distance:** Available as alternative metric
- **Statistics:** Can compute best/worst similarity across database

### M4: Attendance Management (`m4_attendance_management.dart`)
- **Record Attendance:** Prevents duplicate entries for same student on same day
- **Attendance Details:** Full stats per student (total, present, absent, late, rate)
- **Daily Report:** All attendance records for a specific date
- **Monthly Report:** All students with their attendance details
- **Export CSV:** All-time attendance matrix
- **Export Embeddings CSV:** All embeddings with full student profile data
- **Export Subject CSV:** Per-subject attendance with teacher info, present/absent lists
- **System Statistics:** Aggregated stats for overview dashboard

### M5: Liveness Detection (`m5_liveness_detection.dart`)
- **Eye Aspect Ratio (EAR):** Monitors 6 eye landmarks to detect blinks
- **Formula:** `EAR = (||p2-p6|| + ||p3-p5||) / (2 × ||p1-p4||)`
- **Blink Detection:** EAR drops below 0.3, then recovers
- **Requirement:** 2 blinks within 10 seconds
- **Status:** Available but not currently enforced during attendance flow

---

## 10. Data Models

### Student (`student_model.dart`)
```dart
class Student {
  int? id;                // Auto-generated unique ID
  String name;            // Full name
  String rollNumber;      // Roll/registration number
  String className;       // Class/section
  String gender;          // Male/Female/Other
  int age;                // Age in years
  String phoneNumber;     // Contact number
  DateTime enrollmentDate; // When enrolled
}
```

### FaceEmbedding (`embedding_model.dart`)
```dart
class FaceEmbedding {
  int? id;                // Auto-generated unique ID
  int studentId;          // References Student.id
  List<double> vector;    // 512-dimensional float vector
  DateTime captureDate;   // When captured
  int get dimension;      // vector.length (512)
}
```

### AttendanceRecord (`attendance_model.dart`)
```dart
class AttendanceRecord {
  int? id;                // Auto-generated unique ID
  int studentId;          // References Student.id
  DateTime date;          // Date of attendance
  String? time;           // Time of marking
  AttendanceStatus status; // present / absent / late
  DateTime recordedAt;    // When record was created
}

enum AttendanceStatus { present, absent, late }
```

### Subject (`subject_model.dart`)
```dart
class Subject {
  int? id;                // Unique ID (timestamp-based)
  String name;            // Subject name (e.g., "Mathematics")
  DateTime createdAt;     // When created
}

class TeacherSession {
  int? id;                // Unique ID
  String teacherName;     // Teacher who took attendance
  int subjectId;          // References Subject.id
  String subjectName;     // Subject name (denormalized)
  DateTime date;          // Session date
  DateTime createdAt;     // When session was created
}
```

### DetectedFace (`face_detection_model.dart`)
```dart
class DetectedFace {
  double x, y;            // Top-left corner
  double width, height;   // Bounding box size
  double confidence;      // Detection confidence (0.0–1.0)
}
```

### MatchResult (`match_result_model.dart`)
```dart
class MatchResult {
  String identityType;    // "known" or "unknown"
  int? studentId;         // Matched student ID (if known)
  String? studentName;    // Matched student name
  double similarity;      // Cosine similarity score
  DateTime timestamp;     // When match was computed
}
```

---

## 11. CSV Export System

### Auto-Generated Subject CSV (on attendance submit)
**Filename:** `SubjectName_YYYY-MM-DD.csv`  
**Format:**
```csv
Teacher Name,Subject
"John","Mathematics"

Date: 2026-02-12

Absentees,Attendees,Expression
"Charlie","Alice","Happy"
"","Bob","Neutral"

Total Absent,Total Present,Total Students
1,2,3
```

Note: Subject CSV column order has been updated to `Absentees,Attendees,Expression` (rows map absentee → attendee → expression label).

### Manual Attendance Export
**Filename:** `attendance_csv_TIMESTAMP.csv`  
**Format:** Student × Date matrix with 1/0 values and totals

### Manual Embeddings Export
**Filename:** `embeddings_csv_TIMESTAMP.csv`  
**Columns:** id, student_id, student_name, roll_number, class, gender, age, phone_number, enrollment_date, capture_date, dimension, vector

### File Storage
- **Primary:** `<ExternalStorage>/FaceAttendanceExports/`
- **Fallback:** `<AppDocuments>/FaceAttendanceExports/`
- **Android MediaStore:** Files also saved to Downloads via MethodChannel (`com.coad.faceattendance/save`)

---

## 12. Configuration & Settings

### Similarity Thresholds
| Level | Value | Behavior |
|-------|-------|----------|
| Low | 0.75 | More lenient — fewer false negatives, may accept similar-looking people |
| Medium | 0.80 | Balanced — good for most environments |
| High | 0.90 | Strict — high confidence required, may miss some detections |

### Enrollment Requirements
| Parameter | Value |
|-----------|-------|
| Required samples | 20 |
| Recommended samples | 30 |
| Minimum face size (enrollment) | 150×150 pixels |
| Minimum face size (attendance) | 80×80 pixels |

### Attendance Detection
| Parameter | Value |
|-----------|-------|
| Consecutive detections required | 3 |
| Cooldown between marks | 3 seconds |
| Scan interval | 1 frame per second |
| Camera resolution | Medium (480p) |

---

## 13. Performance Optimizations

### GPU & Rendering
- **Removed BackdropFilter blur** from app-wide builder (was applying 24σ Gaussian blur on every frame — extremely heavy on low-end GPUs)
- **Lightweight AnimatedBackground** — replaced Stack + 2 Containers with single `ColoredBox`
- **RepaintBoundary** on camera preview — isolates camera repainting from UI repaints
- **RepaintBoundary** on stats bar — prevents stats updates from triggering full-screen repaints
- **Replaced `withOpacity()` calls with `withAlpha()`** — avoids creating extra `Opacity` layer nodes

### Memory & CPU
- **Medium camera resolution** (480p) — balances quality vs. memory on low-end phones
- **1-second scan interval** — prevents CPU overload from continuous processing
- **4-thread TFLite inference** — utilizes multi-core CPUs efficiently
- **XNNPack delegate** — hardware-optimized neural network inference
- **Face minimum size filter** (80×80) — skips tiny/distant faces to save processing time
- **Temporary files cleaned up** — ML Kit temp files deleted after detection

### Data
- **SharedPreferences storage** — lightweight, no SQLite overhead
- **Singleton database manager** — single instance, no duplicate connections
- **Deduplication** — prevents duplicate attendance records from inflating counts

---

## 14. Dependencies & Packages

### Core Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | UI framework |
| `camera` | ^0.11.0+1 | Camera access (CameraX on Android) |
| `google_ml_kit` | ^0.18.0 | MediaPipe face detection |
| `tflite_flutter` | ^0.11.0 | TensorFlow Lite inference engine |
| `image` | ^4.0.0 | Image decoding, cropping, resizing |
| `shared_preferences` | ^2.2.0 | Local key-value persistent storage |
| `permission_handler` | ^11.3.1 | Runtime permission requests |
| `flutter_tts` | ^4.2.5 | Text-to-Speech voice feedback |
| `path_provider` | ^2.0.15 | Platform-specific directory paths |
| `path` | ^1.8.3 | Path manipulation utilities |
| `share_plus` | ^7.0.0 | Share files to other apps |
| `pdf` | ^3.11.0 | PDF generation (available) |
| `lottie` | ^2.3.2 | Lottie animations |
| `google_fonts` | ^5.0.0 | Google Fonts integration |
| `vector_math` | ^2.1.4 | Vector math operations |
| `cupertino_icons` | ^1.0.8 | iOS-style icons |

### Build Dependencies
| Package | Version | Purpose |
|---------|---------|---------|
| `drift` | ^2.15.0 | (Legacy) SQL database builder |
| `drift_dev` | ^2.15.0 | (Legacy) Code generator for Drift |
| `sqlite3_flutter_libs` | ^0.5.15 | (Legacy) SQLite native libs |
| `build_runner` | ^2.4.7 | Code generation runner |
| `flutter_lints` | ^6.0.0 | Lint rules |
| `flutter_launcher_icons` | ^0.13.0 | App icon generation |

### Native Dependencies (Android)
- CameraX — via camera plugin
- ML Kit Face Detection — via google_ml_kit
- TFLite runtime — via tflite_flutter (XNNPack CPU delegate)
- MediaStore API — via custom MethodChannel for saving to Downloads

---

## 15. Build & Run Instructions

### First-Time Setup
```bash
# 1. Clone the repository
git clone <repo-url>
cd multi-model-support-yolo-main

# 2. Install Flutter dependencies
flutter pub get

# 3. Ensure the model file exists
# Place embedding_model.tflite in assets/models/

# 4. Connect an Android device (USB debugging enabled)
flutter devices

# 5. Run in debug mode
flutter run

# 6. Or build a debug APK
flutter build apk --debug

# 7. Or build a release APK
flutter build apk --release
```

### APK Location
- Debug: `build/app/outputs/flutter-apk/app-debug.apk`
- Release: `build/app/outputs/flutter-apk/app-release.apk`

### Common Build Issues
| Issue | Solution |
|-------|----------|
| `minSdkVersion` error | Ensure `android/app/build.gradle.kts` has `minSdk = 21` or higher |
| ML Kit download failure | Run on physical device (ML Kit may not work on emulator) |
| TFLite model not found | Verify `assets/models/embedding_model.tflite` exists and is listed in `pubspec.yaml` |
| Camera not initializing | Grant camera permission manually in device settings |
| CSV not saving | Grant storage permission manually in device settings |

---

## 16. Troubleshooting

### Face Not Detecting
1. Ensure adequate lighting (not too dark, not too bright)
2. Face the camera directly (avoid extreme angles >30°)
3. Move closer — face must be at least 80×80 pixels in frame
4. Try switching cameras (front/rear)

### Attendance Not Marking
1. Student must be enrolled with 20+ face samples
2. Similarity threshold may be too high — try "Low" (0.75) in Settings
3. Multiple faces: each face needs 3 consecutive detections (hold still for ~3 seconds)
4. Cooldown: same student can't be re-marked within 3 seconds

### CSV Files Not Appearing in Export
1. Ensure storage permission is granted
2. Check that attendance was submitted (not just scanned)
3. Tap refresh button on export screen
4. Files are in: `<ExternalStorage>/Android/data/com.example.vision_id/files/downloads/FaceAttendanceExports/`

### Low Performance on Budget Phones
1. The app is optimized for 2GB+ RAM devices
2. Ensure no other heavy apps are running
3. Use "Low" similarity threshold (fewer comparison iterations)
4. Close and reopen the app if it becomes sluggish

---

*Document generated for Face Recognition Attendance System v1.0.0*  
*Framework: Flutter | AI: ML Kit + AdaFace-Mobile TFLite | Storage: SharedPreferences*
