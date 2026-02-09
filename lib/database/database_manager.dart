import 'dart:convert';
import 'dart:math' show sqrt;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student_model.dart' as model;
import '../models/embedding_model.dart' as model;
import '../models/attendance_model.dart' as model;
import '../models/subject_model.dart' as model;

/// Database manager using SharedPreferences for data persistence
class DatabaseManager {
  static final DatabaseManager _instance = DatabaseManager._internal();

  factory DatabaseManager() {
    return _instance;
  }

  DatabaseManager._internal();

  /// Database placeholder - not used with SharedPreferences approach
  Future<void> get database async {
    // Initialization handled implicitly by SharedPreferences
  }

  /// Initialize database
  Future<void> initialize() async {
    // SharedPreferences initializes on first use
  }

  /// Close database
  Future<void> close() async {
    // SharedPreferences doesn't require explicit closing
  }

  // ==================== STUDENT OPERATIONS ====================

  /// Insert a new student
  Future<int> insertStudent(model.Student student) async {
    final prefs = await SharedPreferences.getInstance();
    final students = await getAllStudents();
    
    // Generate new ID
    final newId = students.isEmpty ? 1 : (students.map((s) => s.id!).reduce((a, b) => a > b ? a : b) + 1);
    final newStudent = model.Student(
      id: newId,
      name: student.name,
      rollNumber: student.rollNumber,
      className: student.className,
      enrollmentDate: student.enrollmentDate,
    );
    
    students.add(newStudent);
    final jsonList = students
        .map((s) => jsonEncode({
          'id': s.id,
          'name': s.name,
          'rollNumber': s.rollNumber,
          'className': s.className,
          'enrollmentDate': s.enrollmentDate.toIso8601String(),
        }))
        .toList();
    await prefs.setStringList('students', jsonList);
    return newId;
  }

  /// Get all students
  Future<List<model.Student>> getAllStudents() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('students') ?? [];
    
    return jsonList
        .map((json) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final id = data['id'];
          if (id == null) {
            debugPrint('⚠️ Student missing ID: ${data['name']}');
            return null;
          }
          return model.Student(
            id: id is int ? id : int.tryParse(id.toString()),
            name: data['name'] as String,
            rollNumber: data['rollNumber'] as String,
            className: data['className'] as String,
            enrollmentDate: DateTime.parse(data['enrollmentDate'] as String),
          );
        })
        .whereType<model.Student>()
        .toList();
  }

  /// Get student by ID
  Future<model.Student?> getStudentById(int id) async {
    final students = await getAllStudents();
    try {
      return students.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Update student
  Future<int> updateStudent(int id, model.Student student) async {
    final prefs = await SharedPreferences.getInstance();
    final students = await getAllStudents();
    
    final index = students.indexWhere((s) => s.id == id);
    if (index == -1) return 0;
    
    students[index] = student;
    final jsonList = students
        .map((s) => jsonEncode({
          'id': s.id,
          'name': s.name,
          'rollNumber': s.rollNumber,
          'className': s.className,
          'enrollmentDate': s.enrollmentDate.toIso8601String(),
        }))
        .toList();
    await prefs.setStringList('students', jsonList);
    return 1;
  }

  /// Delete student
  Future<int> deleteStudent(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final students = await getAllStudents();
    
    final initialLength = students.length;
    students.removeWhere((s) => s.id == id);
    
    final jsonList = students
        .map((s) => jsonEncode({
          'id': s.id,
          'name': s.name,
          'rollNumber': s.rollNumber,
          'className': s.className,
          'enrollmentDate': s.enrollmentDate.toIso8601String(),
        }))
        .toList();
    await prefs.setStringList('students', jsonList);
    return initialLength - students.length;
  }

  // ==================== FACE EMBEDDING OPERATIONS ====================

  /// Insert face embedding
  Future<int> insertEmbedding(model.FaceEmbedding embedding) async {
    final prefs = await SharedPreferences.getInstance();
    final embeddings = await getAllEmbeddings();
    
    // Generate new ID
    final newId = embeddings.isEmpty ? 1 : (embeddings.map((e) => e.id!).reduce((a, b) => a > b ? a : b) + 1);
    final newEmbedding = model.FaceEmbedding(
      id: newId,
      studentId: embedding.studentId,
      vector: embedding.vector,
      captureDate: embedding.captureDate,
    );
    
    embeddings.add(newEmbedding);
    final jsonList = embeddings
        .map((e) => jsonEncode({
          'id': e.id,
          'studentId': e.studentId,
          'vector': e.vector,
          'captureDate': e.captureDate.toIso8601String(),
        }))
        .toList();
    await prefs.setStringList('embeddings', jsonList);
    return newId;
  }

  /// Get embeddings for a student
  Future<List<model.FaceEmbedding>> getEmbeddingsForStudent(int studentId) async {
    final embeddings = await getAllEmbeddings();
    return embeddings.where((e) => e.studentId == studentId).toList();
  }

  /// Get all embeddings
  Future<List<model.FaceEmbedding>> getAllEmbeddings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('embeddings') ?? [];

    int? parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    return jsonList
        .map((json) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final id = parseInt(data['id']);
          final studentId = parseInt(data['studentId']);
          if (studentId == null) return null;
          final vectorRaw = data['vector'];
          final vector = vectorRaw is List
              ? List<double>.from(vectorRaw.map((v) => (v as num).toDouble()))
              : <double>[];
          return model.FaceEmbedding(
            id: id,
            studentId: studentId,
            vector: vector,
            captureDate: DateTime.tryParse(data['captureDate'] as String? ?? '') ?? DateTime.now(),
          );
        })
        .whereType<model.FaceEmbedding>()
        .toList();
  }



  /// Find similar embeddings using vector similarity
  Future<List<model.FaceEmbedding>> findSimilarEmbeddings(
    List<double> queryVector,
    double threshold,
  ) async {
    // Simple cosine similarity implementation
    final allEmbeddings = await getAllEmbeddings();
    final similar = <model.FaceEmbedding>[];
    
    for (final embedding in allEmbeddings) {
      final similarity = _cosineSimilarity(queryVector, embedding.vector);
      if (similarity >= threshold) {
        similar.add(embedding);
      }
    }
    
    // Sort by similarity descending
    similar.sort((a, b) => _cosineSimilarity(queryVector, b.vector)
        .compareTo(_cosineSimilarity(queryVector, a.vector)));
    
    return similar;
  }

  /// Cosine similarity calculator
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  // ==================== ATTENDANCE OPERATIONS ====================

  /// Insert attendance record
  Future<int> insertAttendance(model.AttendanceRecord attendance) async {
    final prefs = await SharedPreferences.getInstance();
    final records = await getAllAttendance();
    
    // Generate new ID
    final existingIds = records.where((r) => r.id != null).map((r) => r.id!).toList();
    final newId = existingIds.isEmpty ? 1 : (existingIds.reduce((a, b) => a > b ? a : b) + 1);
    final newRecord = model.AttendanceRecord(
      id: newId,
      studentId: attendance.studentId,
      date: attendance.date,
      time: attendance.time,
      status: attendance.status,
      recordedAt: attendance.recordedAt,
    );
    
    records.add(newRecord);
    final jsonList = records
        .map((r) => jsonEncode({
          'id': r.id,
          'studentId': r.studentId,
          'date': r.date.toIso8601String(),
          'time': r.time,
          'status': r.status.name,
          'recordedAt': r.recordedAt.toIso8601String(),
        }))
        .toList();
    await prefs.setStringList('attendance', jsonList);
    return newId;
  }

  /// Get attendance for student
  Future<List<model.AttendanceRecord>> getAttendanceForStudent(int studentId) async {
    final records = await getAllAttendance();
    return records.where((r) => r.studentId == studentId).toList();
  }

  /// Get attendance for date
  Future<List<model.AttendanceRecord>> getAttendanceForDate(DateTime date) async {
    final records = await getAllAttendance();
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return records.where((r) {
      final recordDateStr = '${r.date.year}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}';
      return recordDateStr == dateStr;
    }).toList();
  }

  /// Get attendance for student on specific date
  Future<model.AttendanceRecord?> getAttendanceForStudentOnDate(
    int studentId,
    DateTime date,
  ) async {
    final records = await getAttendanceForDate(date);
    try {
      return records.firstWhere((r) => r.studentId == studentId);
    } catch (e) {
      return null;
    }
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
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('attendance') ?? [];

    int? parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    return jsonList
        .map((json) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final id = parseInt(data['id']);
          final studentId = parseInt(data['studentId']);
          if (studentId == null) return null; // skip corrupted entries
          return model.AttendanceRecord(
            id: id,
            studentId: studentId,
            date: DateTime.tryParse(data['date'] as String? ?? '') ?? DateTime.now(),
            time: data['time'] as String?,
            status: model.AttendanceStatus.values.firstWhere(
              (e) => e.name == data['status'],
              orElse: () => model.AttendanceStatus.present,
            ),
            recordedAt: DateTime.tryParse(data['recordedAt'] as String? ?? '') ?? DateTime.now(),
          );
        })
        .whereType<model.AttendanceRecord>()
        .toList();
  }

  /// Delete all embeddings for a student
  Future<int> deleteEmbeddingsForStudent(int studentId) async {
    final prefs = await SharedPreferences.getInstance();
    final embeddings = await getAllEmbeddings();
    
    final initialLength = embeddings.length;
    embeddings.removeWhere((e) => e.studentId == studentId);
    
    final jsonList = embeddings
        .map((e) => jsonEncode({
          'id': e.id,
          'studentId': e.studentId,
          'vector': e.vector,
          'captureDate': e.captureDate.toIso8601String(),
        }))
        .toList();
    await prefs.setStringList('embeddings', jsonList);
    return initialLength - embeddings.length;
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

  // ==================== SUBJECT OPERATIONS (SharedPreferences) ====================

  /// Insert a new subject
  Future<void> insertSubject(model.Subject subject) async {
    final prefs = await SharedPreferences.getInstance();
    final subjects = await getAllSubjects();
    subjects.add(subject);
    
    final jsonList = subjects
        .map((s) => jsonEncode({'id': s.id, 'name': s.name, 'createdAt': s.createdAt.toIso8601String()}))
        .toList();
    await prefs.setStringList('subjects', jsonList);
  }

  /// Get all subjects
  Future<List<model.Subject>> getAllSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('subjects') ?? [];
    
    return jsonList
        .map((json) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          return model.Subject(
            id: data['id'] as int,
            name: data['name'] as String,
            createdAt: DateTime.parse(data['createdAt'] as String),
          );
        })
        .toList();
  }

  /// Get or create subject by name
  Future<model.Subject> getOrCreateSubject(String subjectName) async {
    final subjects = await getAllSubjects();
    
    try {
      return subjects.firstWhere((s) => s.name.toLowerCase() == subjectName.toLowerCase());
    } catch (e) {
      final newSubject = model.Subject(
        id: DateTime.now().millisecondsSinceEpoch,
        name: subjectName,
      );
      await insertSubject(newSubject);
      return newSubject;
    }
  }

  // ==================== TEACHER SESSION OPERATIONS (SharedPreferences) ====================

  /// Insert a new teacher session
  Future<void> insertTeacherSession(model.TeacherSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await getAllTeacherSessions();
    sessions.add(session);
    
    final jsonList = sessions
        .map((s) => jsonEncode({
              'id': s.id,
              'teacherName': s.teacherName,
              'subjectId': s.subjectId,
              'subjectName': s.subjectName,
              'date': s.date.toIso8601String(),
              'createdAt': s.createdAt.toIso8601String(),
            }))
        .toList();
    await prefs.setStringList('teacherSessions', jsonList);
  }

  /// Get all teacher sessions
  Future<List<model.TeacherSession>> getAllTeacherSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList('teacherSessions') ?? [];

    int? parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
    }

    return jsonList
        .map((json) {
          final data = jsonDecode(json) as Map<String, dynamic>;
          final id = parseInt(data['id']);
          final subjectId = parseInt(data['subjectId']);
          if (id == null || subjectId == null) return null;
          return model.TeacherSession(
            id: id,
            teacherName: data['teacherName'] as String? ?? '',
            subjectId: subjectId,
            subjectName: data['subjectName'] as String? ?? '',
            date: DateTime.tryParse(data['date'] as String? ?? '') ?? DateTime.now(),
            createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now(),
          );
        })
        .whereType<model.TeacherSession>()
        .toList();
  }

  /// Get teacher sessions by date
  Future<List<model.TeacherSession>> getTeacherSessionsByDate(DateTime date) async {
    final sessions = await getAllTeacherSessions();
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return sessions.where((s) {
      final sessionDateStr = '${s.date.year}-${s.date.month.toString().padLeft(2, '0')}-${s.date.day.toString().padLeft(2, '0')}';
      return sessionDateStr == dateStr;
    }).toList();
  }

  /// Get teacher sessions for a specific subject
  Future<List<model.TeacherSession>> getTeacherSessionsBySubject(int subjectId) async {
    final sessions = await getAllTeacherSessions();
    return sessions.where((s) => s.subjectId == subjectId).toList();
  }
}
