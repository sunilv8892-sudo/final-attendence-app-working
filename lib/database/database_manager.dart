import 'package:drift/drift.dart';
import 'dart:convert';
import 'face_recognition_database.dart';
import '../models/student_model.dart' as model;
import '../models/embedding_model.dart' as model;
import '../models/attendance_model.dart' as model;

/// Database manager using Drift for SQLite with vector extension support
class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();
  FaceRecognitionDatabase? _database;

  factory DatabaseManager() {
    return _instance;
  }

  DatabaseManager._internal();

  /// Get database instance
  Future<FaceRecognitionDatabase> get database async {
    _database ??= FaceRecognitionDatabase();
    return _database!;
  }

  /// Initialize database (called automatically by Drift)
  Future<void> initialize() async {
    await database;
  }

  /// Close database
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  // ==================== STUDENT OPERATIONS ====================

  /// Insert a new student
  Future<int> insertStudent(model.Student student) async {
    final db = await database;
    return await db.insertStudent(
      StudentsCompanion(
        name: Value(student.name),
        rollNumber: Value(student.rollNumber),
        studentClass: Value(student.className),
        enrollmentDate: Value(student.enrollmentDate),
      ),
    );
  }

  /// Get all students
  Future<List<model.Student>> getAllStudents() async {
    final db = await database;
    final students = await db.getAllStudents();
    return students
        .map(
          (s) => model.Student(
            id: s.id,
            name: s.name,
            rollNumber: s.rollNumber,
            className: s.studentClass,
            enrollmentDate: s.enrollmentDate,
          ),
        )
        .toList();
  }

  /// Get student by ID
  Future<model.Student?> getStudentById(int id) async {
    final db = await database;
    final student = await db.getStudentById(id);
    return student != null
        ? model.Student(
            id: student.id,
            name: student.name,
            rollNumber: student.rollNumber,
            className: student.studentClass,
            enrollmentDate: student.enrollmentDate,
          )
        : null;
  }

  /// Update student
  Future<int> updateStudent(int id, model.Student student) async {
    final db = await database;
    return await db.updateStudent(
      id,
      StudentsCompanion(
        name: Value(student.name),
        rollNumber: Value(student.rollNumber),
        studentClass: Value(student.className),
        enrollmentDate: Value(student.enrollmentDate),
      ),
    );
  }

  /// Delete student
  Future<int> deleteStudent(int id) async {
    final db = await database;
    return await db.deleteStudent(id);
  }

  // ==================== FACE EMBEDDING OPERATIONS ====================

  /// Insert face embedding
  Future<int> insertEmbedding(model.FaceEmbedding embedding) async {
    final db = await database;
    // Convert List<double> to JSON string for storage
    final vectorJson = jsonEncode(embedding.vector);
    return await db.insertEmbedding(
      FaceEmbeddingsCompanion(
        studentId: Value(embedding.studentId),
        vector: Value(vectorJson),
        captureDate: Value(embedding.captureDate),
      ),
    );
  }

  /// Get embeddings for a student
  Future<List<model.FaceEmbedding>> getEmbeddingsForStudent(
    int studentId,
  ) async {
    final db = await database;
    final embeddings = await db.getEmbeddingsForStudent(studentId);
    return embeddings
        .map(
          (e) => model.FaceEmbedding(
            id: e.id,
            studentId: e.studentId,
            vector: _parseVector(e.vector),
            captureDate: e.captureDate,
          ),
        )
        .toList();
  }

  /// Get all embeddings
  Future<List<model.FaceEmbedding>> getAllEmbeddings() async {
    final db = await database;
    final embeddings = await db.getAllEmbeddings();
    return embeddings
        .map(
          (e) => model.FaceEmbedding(
            id: e.id,
            studentId: e.studentId,
            vector: _parseVector(e.vector),
            captureDate: e.captureDate,
          ),
        )
        .toList();
  }

  // Helper method to parse JSON vector strings
  List<double> _parseVector(String vectorStr) {
    try {
      final decoded = jsonDecode(vectorStr);
      if (decoded is List) {
        return List<double>.from(decoded.map((v) => (v as num).toDouble()));
      }
      return [];
    } catch (e) {
      print('⚠️ Error parsing vector: $e');
      print('   Vector string: $vectorStr');
      return [];
    }
  }

  /// Find similar embeddings using vector similarity
  Future<List<model.FaceEmbedding>> findSimilarEmbeddings(
    List<double> queryVector,
    double threshold,
  ) async {
    final db = await database;
    final embeddings = await db.findSimilarEmbeddings(queryVector, threshold);
    return embeddings
        .map(
          (e) => model.FaceEmbedding(
            id: e.id,
            studentId: e.studentId,
            vector: _parseVector(e.vector),
            captureDate: e.captureDate,
          ),
        )
        .toList();
  }

  // ==================== ATTENDANCE OPERATIONS ====================

  /// Insert attendance record
  Future<int> insertAttendance(model.AttendanceRecord attendance) async {
    final db = await database;
    return await db.insertAttendance(
      AttendanceCompanion(
        studentId: Value(attendance.studentId),
        date: Value(attendance.date),
        time: Value(attendance.time),
        status: Value(attendance.status.name),
        recordedAt: Value(attendance.recordedAt),
      ),
    );
  }

  /// Get attendance for student
  Future<List<model.AttendanceRecord>> getAttendanceForStudent(
    int studentId,
  ) async {
    final db = await database;
    final records = await db.getAttendanceForStudent(studentId);
    return records
        .map(
          (a) => model.AttendanceRecord(
            id: a.id,
            studentId: a.studentId,
            date: a.date,
            time: a.time,
            status: model.AttendanceStatus.values.firstWhere(
              (e) => e.name == a.status,
              orElse: () => model.AttendanceStatus.present,
            ),
            recordedAt: a.recordedAt,
          ),
        )
        .toList();
  }

  /// Get attendance for date
  Future<List<model.AttendanceRecord>> getAttendanceForDate(
    DateTime date,
  ) async {
    final db = await database;
    final records = await db.getAttendanceForDate(date);
    return records
        .map(
          (a) => model.AttendanceRecord(
            id: a.id,
            studentId: a.studentId,
            date: a.date,
            time: a.time,
            status: model.AttendanceStatus.values.firstWhere(
              (e) => e.name == a.status,
              orElse: () => model.AttendanceStatus.present,
            ),
            recordedAt: a.recordedAt,
          ),
        )
        .toList();
  }

  /// Get attendance for student on specific date
  Future<model.AttendanceRecord?> getAttendanceForStudentOnDate(
    int studentId,
    DateTime date,
  ) async {
    final db = await database;
    final record = await db.getAttendanceForStudentOnDate(studentId, date);
    return record != null
        ? model.AttendanceRecord(
            id: record.id,
            studentId: record.studentId,
            date: record.date,
            time: record.time,
            status: model.AttendanceStatus.values.firstWhere(
              (e) => e.name == record.status,
              orElse: () => model.AttendanceStatus.present,
            ),
            recordedAt: record.recordedAt,
          )
        : null;
  }

  /// Record attendance (convenience method)
  Future<int> recordAttendance(model.AttendanceRecord attendance) async {
    return await insertAttendance(attendance);
  }

  /// Get attendance statistics for a student
  Future<Map<String, dynamic>> getAttendanceStats(int studentId) async {
    final records = await getAttendanceForStudent(studentId);
    final total = records.length;
    final present = records
        .where((r) => r.status == model.AttendanceStatus.present)
        .length;
    final absent = records
        .where((r) => r.status == model.AttendanceStatus.absent)
        .length;
    final late = records
        .where((r) => r.status == model.AttendanceStatus.late)
        .length;

    return {
      'total': total,
      'present': present,
      'absent': absent,
      'late': late,
      'attendance_rate': total > 0 ? present / total : 0.0,
    };
  }

  /// Get all attendance records (for export)
  Future<List<model.AttendanceRecord>> getAllAttendance() async {
    final db = await database;
    final records = await db.select(db.attendance).get();
    return records
        .map(
          (a) => model.AttendanceRecord(
            id: a.id,
            studentId: a.studentId,
            date: a.date,
            time: a.time,
            status: model.AttendanceStatus.values.firstWhere(
              (e) => e.name == a.status,
              orElse: () => model.AttendanceStatus.present,
            ),
            recordedAt: a.recordedAt,
          ),
        )
        .toList();
  }

  /// Delete all embeddings for a student
  Future<int> deleteEmbeddingsForStudent(int studentId) async {
    final db = await database;
    return await (db.delete(
      db.faceEmbeddings,
    )..where((e) => e.studentId.equals(studentId))).go();
  }

  /// Get all students who have embeddings (enrolled students)
  Future<List<model.Student>> getEnrolledStudents() async {
    final allEmbeddings = await getAllEmbeddings();
    final uniqueStudentIds = <int>{};
    for (final embedding in allEmbeddings) {
      uniqueStudentIds.add(embedding.studentId);
    }
    
    final enrolledStudents = <model.Student>[];
    for (final studentId in uniqueStudentIds) {
      final student = await getStudentById(studentId);
      if (student != null) {
        enrolledStudents.add(student);
      }
    }
    
    return enrolledStudents;
  }
}
