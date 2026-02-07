import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../modules/m4_attendance_management.dart';
import '../models/attendance_model.dart';
import '../utils/constants.dart';

class DatabaseScreen extends StatefulWidget {
  const DatabaseScreen({super.key});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final DatabaseManager _dbManager;
  late final AttendanceManagementModule _attendanceModule;

  late Future<SystemStatistics> _systemStatsFuture;
  late Future<List<AttendanceDetails>> _studentDetailsFuture;
  late Future<List<DailyAttendanceEntry>> _todayEntriesFuture;
  late Future<List<AttendanceDetails>> _enrolledStudentsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _dbManager = DatabaseManager();
    _attendanceModule = AttendanceManagementModule(_dbManager);
    _reloadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload data when screen comes into focus
    _reloadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Overview'),
            Tab(icon: Icon(Icons.people), text: 'Enrolled'),
            Tab(icon: Icon(Icons.today), text: 'Today'),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppConstants.backgroundGradient),
        child: TabBarView(
          controller: _tabController,
          children: [_buildOverviewTab(), _buildEnrolledStudentsTab(), _buildTodayTab()],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Statistics Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bar_chart,
                  color: AppConstants.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppConstants.paddingMedium),
              const Text(
                'System Statistics',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.paddingMedium),
          FutureBuilder<SystemStatistics>(
            future: _systemStatsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final stats = snapshot.data;
              if (stats == null) {
                return Container(
                  padding: const EdgeInsets.all(AppConstants.paddingLarge),
                  child: const Text('Statistics are not available yet.'),
                );
              }
              return _buildStatsCards(stats);
            },
          ),
          const SizedBox(height: AppConstants.paddingLarge),
          // Students Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.successColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.people,
                  color: AppConstants.successColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppConstants.paddingMedium),
              const Text(
                'Students & Attendance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.paddingSmall),
          FutureBuilder<List<AttendanceDetails>>(
            future: _studentDetailsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final students = snapshot.data ?? [];
              if (students.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(AppConstants.paddingLarge),
                  child: const Text('No students or attendance data is recorded yet.'),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: students.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppConstants.paddingSmall),
                itemBuilder: (context, index) => _studentTile(students[index]),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEnrolledStudentsTab() {
    return FutureBuilder<List<AttendanceDetails>>(
      future: _enrolledStudentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final enrolledStudents = snapshot.data ?? [];
        if (enrolledStudents.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(AppConstants.paddingLarge),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_add,
                    size: 48,
                    color: AppConstants.textTertiary,
                  ),
                  SizedBox(height: AppConstants.paddingMedium),
                  Text('No enrolled students yet.'),
                  SizedBox(height: AppConstants.paddingSmall),
                  Text(
                    'Students need to complete face enrollment first',
                    style: TextStyle(color: AppConstants.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.people,
                    color: AppConstants.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppConstants.paddingMedium),
                Text(
                  'Enrolled Students (${enrolledStudents.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.paddingMedium),
            ...enrolledStudents
                .map((detail) => _enrolledStudentCard(detail)),
          ],
        );
      },
    );
  }

  Widget _enrolledStudentCard(AttendanceDetails detail) {
    final student = detail.student;
    final ratio = detail.totalClasses > 0
        ? '${detail.presentCount}/${detail.totalClasses}'
        : '0/0';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: AppConstants.paddingSmall / 2),
                  Text(
                    'Roll: ${student.rollNumber} · Class: ${student.className}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: AppConstants.paddingSmall / 2),
                  Text(
                    'Enrolled: ${student.enrollmentDate.toLocal().toString().split(' ')[0]}',
                    style: const TextStyle(fontSize: 12, color: AppConstants.textTertiary),
                  ),
                  const SizedBox(height: AppConstants.paddingSmall / 2),
                  Text(
                    'Attendance: $ratio (${detail.attendancePercentage.toStringAsFixed(1)}%)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_StudentAction>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Student actions',
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _StudentAction.deleteStudent,
                  child: Text('Delete student'),
                ),
                const PopupMenuItem(
                  value: _StudentAction.clearEmbeddings,
                  child: Text('Clear embeddings'),
                ),
              ],
              onSelected: (action) => _handleStudentAction(detail, action),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTab() {
    return FutureBuilder<List<DailyAttendanceEntry>>(
      future: _todayEntriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data ?? [];
        final counts = _countEntriesByStatus(entries);
        final children = <Widget>[
          Padding(
            padding: const EdgeInsets.only(
              bottom: AppConstants.paddingMedium,
              top: AppConstants.paddingMedium,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.accentColor.withAlpha(26),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.today,
                    color: AppConstants.accentColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppConstants.paddingMedium),
                const Text(
                  "Today's Attendance",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          _buildStatusChips(counts),
          const SizedBox(height: AppConstants.paddingLarge),
        ];
        if (entries.isEmpty) {
          children.add(
            Container(
              padding: const EdgeInsets.all(AppConstants.paddingLarge),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                border: Border.all(color: AppConstants.cardBorder),
              ),
              child: const Center(
                child: Text('No attendance has been recorded today yet.'),
              ),
            ),
          );
        } else {
          children.addAll(entries.map(_todayEntryTile));
        }
        return ListView(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          children: children,
        );
      },
    );
  }

  Widget _buildStatsCards(SystemStatistics stats) {
    final statItems = [
      _StatData(
        label: 'Students',
        value: stats.totalStudents.toString(),
        color: AppConstants.primaryColor,
        icon: Icons.people,
      ),
      _StatData(
        label: 'Embeddings',
        value: stats.totalEmbeddings.toString(),
        color: AppConstants.accentColor,
        icon: Icons.memory,
      ),
      _StatData(
        label: 'Records',
        value: stats.totalAttendanceRecords.toString(),
        color: AppConstants.successColor,
        icon: Icons.check_circle,
      ),
      _StatData(
        label: 'Avg Attendance',
        value: '${stats.averageAttendance.toStringAsFixed(1)}%',
        color: AppConstants.warningColor,
        icon: Icons.trending_up,
      ),
    ];
    return Wrap(
      spacing: AppConstants.paddingMedium,
      runSpacing: AppConstants.paddingMedium,
      children: statItems.map((stat) => _statCard(stat)).toList(),
    );
  }

  Widget _statCard(_StatData stat) {
    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: AppConstants.cardColor,
        border: Border.all(color: AppConstants.cardBorder),
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        boxShadow: [AppConstants.cardShadow],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: stat.color.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                stat.icon,
                color: stat.color,
                size: 20,
              ),
            ),
            const SizedBox(height: AppConstants.paddingSmall),
            Text(
              stat.label,
              style: const TextStyle(
                color: AppConstants.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppConstants.paddingSmall / 2),
            Text(
              stat.value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: stat.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _studentTile(AttendanceDetails details) {
    final ratio = details.totalClasses > 0
        ? '${details.presentCount}/${details.totalClasses}'
        : '0/0';
    return Card(
      child: InkWell(
        onTap: () => _showStudentDetails(details),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      details.student.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: AppConstants.paddingSmall / 2),
                    Text(
                      'Roll: ${details.student.rollNumber} · Class: ${details.student.className}',
                    ),
                    const SizedBox(height: AppConstants.paddingSmall / 2),
                    Text(
                      'Present: ${details.presentCount} · Absent: ${details.absentCount} · Late: ${details.lateCount}',
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    ratio,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppConstants.paddingSmall / 2),
                  Text(
                    '${details.attendancePercentage.toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: AppConstants.paddingSmall / 2),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              const SizedBox(width: AppConstants.paddingSmall),
              PopupMenuButton<_StudentAction>(
                icon: const Icon(Icons.more_vert, color: Colors.white70),
                tooltip: 'Student actions',
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _StudentAction.deleteStudent,
                    child: Text('Delete student'),
                  ),
                  const PopupMenuItem(
                    value: _StudentAction.clearEmbeddings,
                    child: Text('Clear embeddings'),
                  ),
                ],
                onSelected: (action) => _handleStudentAction(details, action),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleStudentAction(
    AttendanceDetails details,
    _StudentAction action,
  ) async {
    final student = details.student;
    if (student.id == null) return;

    final title = action == _StudentAction.deleteStudent
        ? 'Delete student'
        : 'Clear embeddings';
    final description = action == _StudentAction.deleteStudent
        ? 'Delete ${student.name} and all their attendance data?'
        : 'Remove all saved embeddings for ${student.name}? They will need to re-enroll their face.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (action == _StudentAction.deleteStudent) {
        await _dbManager.deleteStudent(student.id!);
      } else {
        await _dbManager.deleteEmbeddingsForStudent(student.id!);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title completed for ${student.name}'),
          backgroundColor: AppConstants.successColor,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to perform action: $e'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    } finally {
      _reloadData();
    }
  }

  Widget _todayEntryTile(DailyAttendanceEntry entry) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.paddingMedium,
          vertical: AppConstants.paddingSmall,
        ),
        title: Text(
          entry.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Roll: ${entry.rollNumber} · ${entry.className} · ${entry.formattedDate}',
        ),
        trailing: Chip(
          label: Text(entry.status.displayName),
          backgroundColor: _statusColor(entry.status),
        ),
      ),
    );
  }

  Widget _buildStatusChips(Map<AttendanceStatus, int> counts) {
    return Wrap(
      spacing: AppConstants.paddingSmall,
      runSpacing: AppConstants.paddingSmall,
      children: AttendanceStatus.values.map((status) {
        final count = counts[status] ?? 0;
        return Chip(
          avatar: CircleAvatar(
            backgroundColor: Colors.white70,
            child: Text(count.toString()),
          ),
          label: Text(status.displayName),
          backgroundColor: _statusColor(status),
        );
      }).toList(),
    );
  }

  Map<AttendanceStatus, int> _countEntriesByStatus(
    List<DailyAttendanceEntry> entries,
  ) {
    final counts = <AttendanceStatus, int>{};
    for (final entry in entries) {
      counts[entry.status] = (counts[entry.status] ?? 0) + 1;
    }
    return counts;
  }

  void _reloadData() {
    if (!mounted) return;
    setState(() {
      _systemStatsFuture = _attendanceModule.getSystemStatistics();
      _studentDetailsFuture = _loadStudentDetails();
      _enrolledStudentsFuture = _loadEnrolledStudents();
      _todayEntriesFuture = _loadTodayEntries();
    });
  }

  Future<List<AttendanceDetails>> _loadStudentDetails() async {
    try {
      final students = await _dbManager.getAllStudents();
      print('📊 Overview: ${students.length} students found');
      
      final records = <AttendanceDetails>[];
      for (final student in students) {
        try {
          final detail = await _attendanceModule.getAttendanceDetails(student.id!);
          if (detail != null) {
            records.add(detail);
            print('   ✅ ${student.name}: ${detail.presentCount}/${detail.totalClasses}');
          } else {
            print('   ⚠️  ${student.name}: getAttendanceDetails returned null');
            records.add(
              AttendanceDetails(
                student: student,
                totalClasses: 0,
                presentCount: 0,
                absentCount: 0,
                lateCount: 0,
                attendancePercentage: 0.0,
                records: [],
              ),
            );
          }
        } catch (e) {
          print('   ❌ ${student.name}: $e');
          records.add(
            AttendanceDetails(
              student: student,
              totalClasses: 0,
              presentCount: 0,
              absentCount: 0,
              lateCount: 0,
              attendancePercentage: 0.0,
              records: [],
            ),
          );
        }
      }
      records.sort((a, b) => a.student.name.compareTo(b.student.name));
      print('✅ Loaded ${records.length} students for overview');
      return records;
    } catch (e) {
      print('❌ Error in _loadStudentDetails: $e');
      return [];
    }
  }

  Future<List<AttendanceDetails>> _loadEnrolledStudents() async {
    try {
      final enrolledStudents = await _dbManager.getEnrolledStudents();
      print('👥 Enrolled: ${enrolledStudents.length} students found');
      
      final records = <AttendanceDetails>[];
      for (final student in enrolledStudents) {
        try {
          final detail = await _attendanceModule.getAttendanceDetails(student.id!);
          if (detail != null) {
            records.add(detail);
            print('   ✅ ${student.name}: enrolled');
          } else {
            print('   ⚠️  ${student.name}: getAttendanceDetails returned null');
            records.add(
              AttendanceDetails(
                student: student,
                totalClasses: 0,
                presentCount: 0,
                absentCount: 0,
                lateCount: 0,
                attendancePercentage: 0.0,
                records: [],
              ),
            );
          }
        } catch (e) {
          print('   ❌ ${student.name}: $e');
          records.add(
            AttendanceDetails(
              student: student,
              totalClasses: 0,
              presentCount: 0,
              absentCount: 0,
              lateCount: 0,
              attendancePercentage: 0.0,
              records: [],
            ),
          );
        }
      }
      records.sort((a, b) => a.student.name.compareTo(b.student.name));
      print('✅ Loaded ${records.length} enrolled students');
      return records;
    } catch (e) {
      print('❌ Error in _loadEnrolledStudents: $e');
      return [];
    }
  }

  Future<List<DailyAttendanceEntry>> _loadTodayEntries() async {
    final now = DateTime.now();
    final records = await _dbManager.getAttendanceForDate(
      DateTime(now.year, now.month, now.day),
    );
    final entries = <DailyAttendanceEntry>[];
    for (final record in records) {
      final student = await _dbManager.getStudentById(record.studentId);
      if (student == null) continue;
      entries.add(
        DailyAttendanceEntry(
          name: student.name,
          rollNumber: student.rollNumber,
          className: student.className,
          status: record.status,
          date: record.date,
          time: record.time ?? '',
        ),
      );
    }
    return entries;
  }

  void _showStudentDetails(AttendanceDetails details) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(details.student.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dialogRow('Roll', details.student.rollNumber),
              _dialogRow('Class', details.student.className),
              const SizedBox(height: AppConstants.paddingMedium),
              _dialogRow('Total Classes', details.totalClasses.toString()),
              _dialogRow('Present', details.presentCount.toString()),
              _dialogRow('Absent', details.absentCount.toString()),
              _dialogRow('Late', details.lateCount.toString()),
              _dialogRow(
                'Attendance %',
                '${details.attendancePercentage.toStringAsFixed(1)}%',
              ),
              const SizedBox(height: AppConstants.paddingMedium),
              const Text(
                'Full record',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppConstants.paddingSmall),
              ...details.records.map(_recordRow),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppConstants.paddingSmall / 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _recordRow(AttendanceRecord record) {
    final dateLabel =
        '${record.date.day.toString().padLeft(2, '0')}-${record.date.month.toString().padLeft(2, '0')}-${record.date.year % 100}';
    final timeLabel = (record.time?.isNotEmpty ?? false)
        ? ' (${record.time})'
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppConstants.paddingSmall / 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$dateLabel$timeLabel'),
          Chip(
            label: Text(record.status.displayName),
            backgroundColor: _statusColor(record.status),
          ),
        ],
      ),
    );
  }

  Color _statusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return AppConstants.successColor.withValues(alpha: 0.15);
      case AttendanceStatus.absent:
        return AppConstants.errorColor.withValues(alpha: 0.15);
      case AttendanceStatus.late:
        return AppConstants.warningColor.withValues(alpha: 0.15);
    }
  }
}

class _StatData {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  _StatData({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
}

class DailyAttendanceEntry {
  final String name;
  final String rollNumber;
  final String className;
  final AttendanceStatus status;
  final DateTime date;
  final String time;

  DailyAttendanceEntry({
    required this.name,
    required this.rollNumber,
    required this.className,
    required this.status,
    required this.date,
    required this.time,
  });

  String get formattedDate {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final timeLabel = time.isNotEmpty ? ' • $time' : '';
    return '$day/$month/$year$timeLabel';
  }
}

enum _StudentAction { deleteStudent, clearEmbeddings }
