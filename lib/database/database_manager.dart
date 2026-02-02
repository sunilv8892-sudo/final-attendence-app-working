import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/student_model.dart';
import '../models/embedding_model.dart';
import '../models/attendance_model.dart';

/// Database manager for offline local storage
/// Handles Students, Face Embeddings, and Attendance records
class DatabaseManager {
  static const String dbName = 'attendance.db';
  static const int dbVersion = 1;

  // Table names
  static const String studentsTable = 'students';
  static const String embeddingsTable = 'embeddings';
  static const String attendanceTable = 'attendance';

  Database? _database;

  /// Get or initialize database
  Future<Database> get database async {
    _database ??= await _initializeDatabase();
    return _database!;
  }

  /// Initialize database and create tables
  Future<Database> _initializeDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);
    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: _createTables,
    );
  }

  /// Create all necessary tables
  Future<void> _createTables(Database db, int version) async {
    // Students table
    await db.execute('''
      CREATE TABLE $studentsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        roll_number TEXT UNIQUE NOT NULL,
        class TEXT NOT NULL,
        enrollment_date TEXT NOT NULL
      )
    ''');

    // Face Embeddings table (multiple embeddings per student)
    await db.execute('''
      CREATE TABLE $embeddingsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        vector TEXT NOT NULL,
        capture_date TEXT NOT NULL,
        FOREIGN KEY(student_id) REFERENCES $studentsTable(id) ON DELETE CASCADE
      )
    ''');

    // Attendance table
    await db.execute('''
      CREATE TABLE $attendanceTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        date TEXT NOT NULL,
        time TEXT,
        status TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        FOREIGN KEY(student_id) REFERENCES $studentsTable(id) ON DELETE CASCADE,
        UNIQUE(student_id, date)
      )
    ''');

    // Create indexes for faster queries
    await db.execute('CREATE INDEX idx_student_id ON $embeddingsTable(student_id)');
    await db.execute('CREATE INDEX idx_attendance_date ON $attendanceTable(date)');
  }

  // ==================== STUDENT OPERATIONS ====================

  /// Insert a new student
  Future<int> insertStudent(Student student) async {
    final db = await database;
    return await db.insert(
      studentsTable,
      student.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all students
  Future<List<Student>> getAllStudents() async {
    final db = await database;
    final maps = await db.query(studentsTable, orderBy: 'name ASC');
    return List.generate(maps.length, (i) => Student.fromMap(maps[i]));
  }

  /// Get student by ID
  Future<Student?> getStudentById(int id) async {
    final db = await database;
    final maps = await db.query(
      studentsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty ? Student.fromMap(maps[0]) : null;
  }

  /// Get student by roll number
  Future<Student?> getStudentByRollNumber(String rollNumber) async {
    final db = await database;
    final maps = await db.query(
      studentsTable,
      where: 'roll_number = ?',
      whereArgs: [rollNumber],
    );
    return maps.isNotEmpty ? Student.fromMap(maps[0]) : null;
  }

  /// Update student
  Future<int> updateStudent(Student student) async {
    final db = await database;
    return await db.update(
      studentsTable,
      student.toMap(),
      where: 'id = ?',
      whereArgs: [student.id],
    );
  }

  /// Delete student
  Future<int> deleteStudent(int id) async {
    final db = await database;
    return await db.delete(
      studentsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== EMBEDDING OPERATIONS ====================

  /// Insert face embedding
  Future<int> insertEmbedding(FaceEmbedding embedding) async {
    final db = await database;
    return await db.insert(embeddingsTable, embedding.toMap());
  }

  /// Get embeddings for a student
  Future<List<FaceEmbedding>> getEmbeddingsForStudent(int studentId) async {
    final db = await database;
    final maps = await db.query(
      embeddingsTable,
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'capture_date DESC',
    );
    return List.generate(maps.length, (i) => FaceEmbedding.fromMap(maps[i]));
  }

  /// Get all embeddings (for matching)
  Future<List<FaceEmbedding>> getAllEmbeddings() async {
    final db = await database;
    final maps = await db.query(embeddingsTable);
    return List.generate(maps.length, (i) => FaceEmbedding.fromMap(maps[i]));
  }

  /// Delete embeddings for a student
  Future<int> deleteEmbeddingsForStudent(int studentId) async {
    final db = await database;
    return await db.delete(
      embeddingsTable,
      where: 'student_id = ?',
      whereArgs: [studentId],
    );
  }

  // ==================== ATTENDANCE OPERATIONS ====================

  /// Insert or update attendance record (prevent duplicates)
  Future<int> recordAttendance(AttendanceRecord record) async {
    final db = await database;
    return await db.insert(
      attendanceTable,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Get attendance for a student on a specific date
  Future<AttendanceRecord?> getAttendanceForStudentOnDate(int studentId, DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];
    final maps = await db.query(
      attendanceTable,
      where: 'student_id = ? AND date = ?',
      whereArgs: [studentId, dateStr],
    );
    return maps.isNotEmpty ? AttendanceRecord.fromMap(maps[0]) : null;
  }

  /// Get all attendance records for a student
  Future<List<AttendanceRecord>> getAttendanceForStudent(int studentId) async {
    final db = await database;
    final maps = await db.query(
      attendanceTable,
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => AttendanceRecord.fromMap(maps[i]));
  }

  /// Get attendance records for a specific date
  Future<List<AttendanceRecord>> getAttendanceForDate(DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];
    final maps = await db.query(
      attendanceTable,
      where: 'date = ?',
      whereArgs: [dateStr],
      orderBy: 'time ASC',
    );
    return List.generate(maps.length, (i) => AttendanceRecord.fromMap(maps[i]));
  }

  /// Get attendance statistics for a student
  Future<Map<String, dynamic>> getAttendanceStats(int studentId) async {
    final records = await getAttendanceForStudent(studentId);
    final presentCount = records.where((r) => r.status == AttendanceStatus.present).length;
    final absentCount = records.where((r) => r.status == AttendanceStatus.absent).length;
    final lateCount = records.where((r) => r.status == AttendanceStatus.late).length;
    final totalClasses = records.length;
    final percentage = totalClasses > 0 ? (presentCount / totalClasses * 100).toStringAsFixed(1) : '0.0';

    return {
      'total_classes': totalClasses,
      'present': presentCount,
      'absent': absentCount,
      'late': lateCount,
      'attendance_percentage': double.parse(percentage),
    };
  }

  /// Delete all data (reset database)
  Future<void> resetDatabase() async {
    final db = await database;
    await db.delete(attendanceTable);
    await db.delete(embeddingsTable);
    await db.delete(studentsTable);
  }

  /// Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
