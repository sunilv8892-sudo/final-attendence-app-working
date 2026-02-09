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
      totalClasses: stats['total'] as int? ?? 0,
      presentCount: stats['present'] as int? ?? 0,
      absentCount: stats['absent'] as int? ?? 0,
      lateCount: stats['late'] as int? ?? 0,
      attendancePercentage: (stats['attendance_rate'] as double?) ?? 0.0,
      records: records,
    );
  }

  /// Get attendance for all students on a date
  Future<List<Map<String, dynamic>>> getDailyAttendanceReport(
    DateTime date,
  ) async {
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
  Future<List<Map<String, dynamic>>> getMonthlyReport(
    int month,
    int year,
  ) async {
    final allStudents = await dbManager.getAllStudents();
    final report = <Map<String, dynamic>>[];

    for (final student in allStudents) {
      final details = await getAttendanceDetails(student.id!);
      if (details != null) {
        report.add({'student': student, 'attendance': details});
      }
    }

    return report;
  }

  /// Export attendance data as CSV format
  Future<String> exportAsCSV() async {
    final allStudents = await dbManager.getAllStudents();
    final allRecords = await dbManager.getAllAttendance();
    final buffer = StringBuffer();

    if (allStudents.isEmpty || allRecords.isEmpty) {
      return 'No data to export';
    }

    // Get all unique dates and sort them
    final dates = <DateTime>{};
    for (final record in allRecords) {
      dates.add(DateTime(record.date.year, record.date.month, record.date.day));
    }
    final sortedDates = dates.toList()..sort();

    // Create header row with dates in DD/MM/YYYY format
    final header = StringBuffer('Student Name');
    for (final date in sortedDates) {
      final formattedDate =
          '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
      header.write(',$formattedDate');
    }
    header.write(',Total_Attended,Total_Absent');
    buffer.writeln(header);

    // Create a map for quick lookup of attendance status
    final attendanceMap = <int, Map<DateTime, String>>{};
    for (final student in allStudents) {
      attendanceMap[student.id!] = {};
      for (final date in sortedDates) {
        attendanceMap[student.id!]![date] = '0'; // Default to absent
      }
    }

    // Fill in the attendance data
    for (final record in allRecords) {
      final dateKey = DateTime(record.date.year, record.date.month, record.date.day);
      if (attendanceMap[record.studentId] != null) {
        attendanceMap[record.studentId]![dateKey] = 
            record.status == AttendanceStatus.present ? '1' : '0';
      }
    }

    // Write student rows
    for (final student in allStudents) {
      int attended = 0;
      int absent = 0;
      
      final row = StringBuffer(student.name);
      for (final date in sortedDates) {
        final status = attendanceMap[student.id]?[date] ?? '0';
        row.write(',$status');
        if (status == '1') {
          attended++;
        } else {
          absent++;
        }
      }
      row.write(',$attended,$absent');
      buffer.writeln(row);
    }

    return buffer.toString();
  }

  /// Export embeddings only as CSV
  Future<String> exportEmbeddingsCSV() async {
    final buffer = StringBuffer();
    buffer.writeln('id,student_id,student_name,capture_date,dimension,vector');
    final embeddings = await dbManager.getAllEmbeddings();
    for (final emb in embeddings) {
      // Get student name for this embedding
      final student = await dbManager.getStudentById(emb.studentId);
      final studentName = student?.name ?? 'Unknown';
      
      final vecStr = emb.vector.map((v) => v.toStringAsFixed(6)).join(';');
      buffer.writeln(
        '${emb.id ?? ''},${emb.studentId},$studentName,${emb.captureDate.toIso8601String()},${emb.dimension},"$vecStr"',
      );
    }
    return buffer.toString();
  }

  /// Export detailed attendance records (all dates)
  Future<String> exportAttendanceDetailsCSV() async {
    final buffer = StringBuffer();
    buffer.writeln('Date,Student Name,Roll Number,Class,Status,Time');
    
    final students = await dbManager.getAllStudents();
    final allRecords = await dbManager.getAllAttendance();
    
    // Group by date
    final recordsByDate = <DateTime, List<dynamic>>{};
    for (final record in allRecords) {
      final dateKey = DateTime(record.date.year, record.date.month, record.date.day);
      if (!recordsByDate.containsKey(dateKey)) {
        recordsByDate[dateKey] = [];
      }
      recordsByDate[dateKey]!.add(record);
    }
    
    // Sort by date
    final sortedDates = recordsByDate.keys.toList()..sort();
    
    for (final date in sortedDates) {
      for (final record in recordsByDate[date]!) {
        final student = students.firstWhere(
          (s) => s.id == record.studentId,
          orElse: () => students.first,
        );
        buffer.writeln(
          '${date.toIso8601String().split('T')[0]},'
          '${student.name},${student.rollNumber},${student.className},'
          '${record.status},${record.time ?? 'N/A'}',
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
      totalAttendanceRecords += stats['total'] as int? ?? 0;
      avgAttendance += stats['attendance_rate'] as double? ?? 0.0;
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

/// Export a subject-based attendance report as CSV
Future<String> exportSubjectAttendanceAsCSV(
  DatabaseManager dbManager,
  String teacherName,
  String subjectName,
  DateTime date,
  {Map<int, AttendanceStatus>? sessionAttendance,
  }
) async {
  final allStudents = await dbManager.getAllStudents();
  final attendanceRecords = sessionAttendance == null
      ? await dbManager.getAttendanceForDate(date)
      : const <AttendanceRecord>[];
  
  final buffer = StringBuffer();
  
  // Header with teacher and subject info
  buffer.writeln('Teacher Name,Subject');
  buffer.writeln('"$teacherName","$subjectName"');
  buffer.writeln('');
  buffer.writeln('Date: ${date.toString().split(' ')[0]}');
  buffer.writeln('');
  
  // Get present and absent students
  final presentStudents = <Student>[];
  final absentStudents = <Student>[];
  
  // Build student lookup map (only students with valid IDs)
  final studentMap = <int, Student>{};
  for (final student in allStudents) {
    if (student.id != null) {
      studentMap[student.id!] = student;
    }
  }
  
  // Process all students; default absent if no record
  for (final studentEntry in studentMap.entries) {
    final studentId = studentEntry.key;
    final student = studentEntry.value;
    final status = sessionAttendance != null
        ? (sessionAttendance[studentId] ?? AttendanceStatus.absent)
        : attendanceRecords.firstWhere(
            (r) => r.studentId == studentId,
            orElse: () => AttendanceRecord(
              studentId: studentId,
              date: date,
              status: AttendanceStatus.absent,
            ),
          ).status;

    if (status == AttendanceStatus.present) {
      presentStudents.add(student);
    } else {
      absentStudents.add(student);
    }
  }
  
  // Column headers
  buffer.writeln('Present Students,Absent Students');
  
  // Write present and absent side by side
  final maxLines = presentStudents.length > absentStudents.length
      ? presentStudents.length
      : absentStudents.length;
  
  for (int i = 0; i < maxLines; i++) {
    final presentName = i < presentStudents.length
        ? presentStudents[i].name
        : '';
    final absentName = i < absentStudents.length
        ? absentStudents[i].name
        : '';
    
    buffer.writeln('"$presentName","$absentName"');
  }
  
  // Add totals
  buffer.writeln('');
  buffer.writeln('Total Present,Total Absent,Total Students');
  buffer.writeln('${presentStudents.length},${absentStudents.length},${allStudents.length}');
  
  return buffer.toString();
}
