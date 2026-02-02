import '../database/database_manager.dart';
import '../models/student_model.dart';
import '../models/attendance_model.dart';

/// M4: Attendance Management Module
/// Handles attendance recording, statistics, and reporting
class AttendanceManagementModule {
  final DatabaseManager dbManager;

  AttendanceManagementModule(this.dbManager);

  /// Record attendance for a student
  /// Automatically prevents duplicate entries for the same day
  Future<bool> recordAttendance(
    int studentId,
    DateTime date,
    AttendanceStatus status,
  ) async {
    // Check if already marked today
    final existing = await dbManager.getAttendanceForDate(date);
    final alreadyMarked = existing.any((rec) => rec.studentId == studentId);
    if (alreadyMarked) {
      return false; // Already marked
    }

    final record = AttendanceRecord(
      studentId: studentId,
      date: date,
      status: status,
    );

    final result = await dbManager.recordAttendance(record);
    return result > 0;
  }

  /// Get full attendance details for a student
  Future<AttendanceDetails?> getAttendanceDetails(int studentId) async {
    final student = await dbManager.getStudentById(studentId);
    if (student == null) return null;

    final stats = await dbManager.getAttendanceStats(studentId);
    final records = await dbManager.getAttendanceForStudent(studentId);

    return AttendanceDetails(
      student: student,
      totalClasses: stats['total_classes'] as int,
      presentCount: stats['present'] as int,
      absentCount: stats['absent'] as int,
      lateCount: stats['late'] as int,
      attendancePercentage: stats['attendance_percentage'] as double,
      records: records,
    );
  }

  /// Get attendance for all students on a date
  Future<List<Map<String, dynamic>>> getDailyAttendanceReport(DateTime date) async {
    final records = await dbManager.getAttendanceForDate(date);
    final report = <Map<String, dynamic>>[];

    for (final record in records) {
      final student = await dbManager.getStudentById(record.studentId);
      if (student != null) {
        report.add({
          'student': student,
          'status': record.status,
          'time': record.time,
        });
      }
    }

    return report;
  }

  /// Get monthly report
  Future<List<Map<String, dynamic>>> getMonthlyReport(int month, int year) async {
    final allStudents = await dbManager.getAllStudents();
    final report = <Map<String, dynamic>>[];

    for (final student in allStudents) {
      final details = await getAttendanceDetails(student.id!);
      if (details != null) {
        report.add({
          'student': student,
          'attendance': details,
        });
      }
    }

    return report;
  }

  /// Export attendance data as CSV format
  Future<String> exportAsCSV() async {
    final allStudents = await dbManager.getAllStudents();
    final buffer = StringBuffer();

    // Header
    buffer.writeln('Name,Roll Number,Class,Total Classes,Present,Absent,Late,Attendance %');

    for (final student in allStudents) {
      final details = await getAttendanceDetails(student.id!);
      if (details != null) {
        buffer.writeln(
          '${student.name},${student.rollNumber},${student.className},'
          '${details.totalClasses},${details.presentCount},${details.absentCount},'
          '${details.lateCount},${details.attendancePercentage.toStringAsFixed(2)}%',
        );
      }
    }

    return buffer.toString();
  }

  /// Get summary statistics for entire system
  Future<SystemStatistics> getSystemStatistics() async {
    final students = await dbManager.getAllStudents();
    final allEmbeddings = await dbManager.getAllEmbeddings();

    int totalAttendanceRecords = 0;
    double avgAttendance = 0;

    for (final student in students) {
      final stats = await dbManager.getAttendanceStats(student.id!);
      totalAttendanceRecords += stats['total_classes'] as int;
      avgAttendance += stats['attendance_percentage'] as double;
    }

    if (students.isNotEmpty) {
      avgAttendance = avgAttendance / students.length;
    }

    return SystemStatistics(
      totalStudents: students.length,
      totalEmbeddings: allEmbeddings.length,
      totalAttendanceRecords: totalAttendanceRecords,
      averageAttendance: avgAttendance,
      lastUpdated: DateTime.now(),
    );
  }

  /// Mark today's attendance for automatic rollcall
  Future<AttendanceResult> markAttendanceForToday(
    int studentId,
    AttendanceStatus status,
  ) async {
    final today = DateTime.now();
    final marked = await recordAttendance(studentId, today, status);

    if (!marked) {
      return AttendanceResult(
        success: false,
        message: 'Already marked for today',
      );
    }

    final student = await dbManager.getStudentById(studentId);
    return AttendanceResult(
      success: true,
      message: '${student?.name} marked as ${status.displayName}',
      timestamp: today,
    );
  }
}

/// Attendance details for a student
class AttendanceDetails {
  final Student student;
  final int totalClasses;
  final int presentCount;
  final int absentCount;
  final int lateCount;
  final double attendancePercentage;
  final List<AttendanceRecord> records;

  AttendanceDetails({
    required this.student,
    required this.totalClasses,
    required this.presentCount,
    required this.absentCount,
    required this.lateCount,
    required this.attendancePercentage,
    required this.records,
  });
}

/// System-wide statistics
class SystemStatistics {
  final int totalStudents;
  final int totalEmbeddings;
  final int totalAttendanceRecords;
  final double averageAttendance;
  final DateTime lastUpdated;

  SystemStatistics({
    required this.totalStudents,
    required this.totalEmbeddings,
    required this.totalAttendanceRecords,
    required this.averageAttendance,
    required this.lastUpdated,
  });
}

/// Result of attendance recording
class AttendanceResult {
  final bool success;
  final String message;
  final DateTime? timestamp;

  AttendanceResult({
    required this.success,
    required this.message,
    this.timestamp,
  });
}
