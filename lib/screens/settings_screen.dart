import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/export_utils.dart';
import '../widgets/animated_background.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _similarityIndex = 0; // 0=Low, 1=Medium, 2=High
  final List<String> _modes = ['Low', 'Medium', 'High'];
  final List<double> _thresholds = [0.75, 0.80, 0.90];
  final List<String> _descriptions = [
    'More lenient — fewer missed faces, may accept similar-looking people',
    'Balanced — good accuracy for most lighting and environments',
    'Strict — very high confidence required, may miss some detections',
  ];

  // Real stats
  int _totalStudents = 0;
  int _totalEmbeddings = 0;
  int _totalAttendance = 0;
  int _totalSubjects = 0;
  int _totalSessions = 0;
  String _dataSize = '...';
  bool _ttsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load threshold
    final savedThreshold = prefs.getDouble('similarity_threshold');
    if (savedThreshold != null) {
      if (savedThreshold == 0.75) {
        _similarityIndex = 0;
      } else if (savedThreshold == 0.80) {
        _similarityIndex = 1;
      } else if (savedThreshold == 0.90) {
        _similarityIndex = 2;
      }
    }

    // Load TTS preference
    _ttsEnabled = prefs.getBool('tts_enabled') ?? true;

    // Load real database stats
    final students = prefs.getStringList('students') ?? [];
    final embeddings = prefs.getStringList('embeddings') ?? [];
    final attendance = prefs.getStringList('attendance') ?? [];
    final subjects = prefs.getStringList('subjects') ?? [];
    final sessions = prefs.getStringList('teacherSessions') ?? [];

    // Calculate approximate data size
    int totalBytes = 0;
    for (final s in students) {
      totalBytes += s.length;
    }
    for (final s in embeddings) {
      totalBytes += s.length;
    }
    for (final s in attendance) {
      totalBytes += s.length;
    }
    for (final s in subjects) {
      totalBytes += s.length;
    }
    for (final s in sessions) {
      totalBytes += s.length;
    }

    String sizeStr;
    if (totalBytes < 1024) {
      sizeStr = '$totalBytes B';
    } else if (totalBytes < 1024 * 1024) {
      sizeStr = '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      sizeStr = '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    if (mounted) {
      setState(() {
        _totalStudents = students.length;
        _totalEmbeddings = embeddings.length;
        _totalAttendance = attendance.length;
        _totalSubjects = subjects.length;
        _totalSessions = sessions.length;
        _dataSize = sizeStr;
      });
    }
  }

  Future<void> _saveThreshold(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('similarity_threshold', _thresholds[index]);
  }

  Future<void> _toggleTts(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tts_enabled', enabled);
    setState(() => _ttsEnabled = enabled);
  }

  Future<void> _backupDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backup = <String, dynamic>{
        'version': 1,
        'exportDate': DateTime.now().toIso8601String(),
        'students': prefs.getStringList('students') ?? [],
        'embeddings': prefs.getStringList('embeddings') ?? [],
        'attendance': prefs.getStringList('attendance') ?? [],
        'subjects': prefs.getStringList('subjects') ?? [],
        'teacherSessions': prefs.getStringList('teacherSessions') ?? [],
      };

      final jsonStr = jsonEncode(backup);

      // Save to file
      final dir = await getExportDirectory();

      final dateStr = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:\\.]'), '-');
      final file = File('${dir.path}/backup_$dateStr.json');
      await file.writeAsString(jsonStr, flush: true);

      if (mounted) {
        // Offer to share
        final shouldShare = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Backup Created'),
            content: Text(
              'Backup saved successfully.\n\n'
              'Students: $_totalStudents\n'
              'Embeddings: $_totalEmbeddings\n'
              'Attendance Records: $_totalAttendance\n\n'
              'Share the backup file?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Done'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Share'),
              ),
            ],
          ),
        );

        if (shouldShare == true) {
          await Share.shareXFiles(
            [XFile(file.path)],
            text: 'Face Attendance Database Backup',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _clearAttendanceOnly() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Attendance Records?'),
        content: const Text(
          'This will delete all attendance records, sessions, and subjects.\n\n'
          'Students and their face embeddings will be kept.\n'
          'You can take fresh attendance afterward.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
            child: const Text('Clear Attendance'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('attendance');
      await prefs.remove('subjects');
      await prefs.remove('teacherSessions');

      // Also remove session_attendance_ keys
      final allKeys = prefs.getKeys();
      for (final key in allKeys) {
        if (key.startsWith('session_attendance_')) {
          await prefs.remove(key);
        }
      }

      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance records cleared. Students preserved.'),
            backgroundColor: AppConstants.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppConstants.errorColor),
        );
      }
    }
  }

  Future<void> _deleteExportedFiles() async {
    try {
      final dir = await getExportDirectory();

      if (!await dir.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No exported files found.')),
          );
        }
        return;
      }

      final files = dir.listSync().whereType<File>().toList();
      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No exported files found.')),
          );
        }
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete All Exported Files?'),
          content: Text(
            'This will delete ${files.length} exported CSV/backup files.\nThis cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
              child: const Text('Delete All'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      int deleted = 0;
      for (final file in files) {
        try {
          await file.delete();
          deleted++;
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $deleted exported files.'),
            backgroundColor: AppConstants.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppConstants.errorColor),
        );
      }
    }
  }

  void _confirmResetDatabase(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Everything?'),
        content: const Text(
          'This will permanently delete:\n\n'
          '• All enrolled students\n'
          '• All face embeddings\n'
          '• All attendance records\n'
          '• All subjects & sessions\n\n'
          'This action CANNOT be undone.\n'
          'Consider creating a backup first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final prefs = await SharedPreferences.getInstance();
                final allKeys = prefs.getKeys().toList();
                for (final key in allKeys) {
                  if (key == 'similarity_threshold' ||
                      key == 'tts_enabled' ||
                      key == 'required_samples') {
                    continue; // Keep settings
                  }
                  await prefs.remove(key);
                }
                await _loadSettings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All data cleared. Settings preserved.'),
                      backgroundColor: AppConstants.successColor,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: AppConstants.errorColor),
                  );
                }
              }
            },
            child: const Text(
              'Reset All Data',
              style: TextStyle(color: AppConstants.errorColor),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppConstants.blueGradient),
        ),
      ),
      body: AnimatedBackground(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ── Face Recognition ──
            _sectionHeader('Face Recognition', Icons.face),
            _buildThresholdCard(),

            const SizedBox(height: 8),

            // ── Voice Feedback ──
            _sectionHeader('Voice Feedback', Icons.volume_up),
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: 4,
              ),
              child: SwitchListTile(
                title: const Text('TTS Attendance Confirmation',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                  'Speak student name when attendance is marked',
                  style: TextStyle(
                      fontSize: 12, color: AppConstants.textTertiary),
                ),
                secondary: Icon(
                  _ttsEnabled
                      ? Icons.record_voice_over
                      : Icons.voice_over_off,
                  color: _ttsEnabled
                      ? AppConstants.primaryColor
                      : AppConstants.textTertiary,
                  size: 22,
                ),
                value: _ttsEnabled,
                activeColor: AppConstants.primaryColor,
                onChanged: _toggleTts,
              ),
            ),

            const SizedBox(height: 8),

            // ── Data Management ──
            _sectionHeader('Data Management', Icons.storage),
            _buildDataCard(),

            const SizedBox(height: 8),

            // ── Model Information ──
            _sectionHeader('Models & Algorithms', Icons.memory),
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: 4,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  children: [
                    _infoRow('Face Detector', 'Google ML Kit (MediaPipe)'),
                    const Divider(
                        height: 1, color: AppConstants.dividerColor),
                    _infoRow('Embedding Model', 'AdaFace-Mobile (TFLite)'),
                    const Divider(
                        height: 1, color: AppConstants.dividerColor),
                    _infoRow('Embedding Dimension', '512D vectors'),
                    const Divider(
                        height: 1, color: AppConstants.dividerColor),
                    _infoRow('Matching Algorithm', 'Cosine Similarity'),
                    const Divider(
                        height: 1, color: AppConstants.dividerColor),
                    _infoRow('Inference', 'XNNPack CPU, 4 threads'),
                    const Divider(
                        height: 1, color: AppConstants.dividerColor),
                    _infoRow('Enrollment Samples', '20 per student'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── About ──
            _sectionHeader('About', Icons.info_outline),
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: 4,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('App', AppConstants.appName),
                    const Divider(
                        height: 1, color: AppConstants.dividerColor),
                    _infoRow('Version', AppConstants.appVersion),
                    const Divider(
                        height: 1, color: AppConstants.dividerColor),
                    _infoRow('Storage', 'SharedPreferences (Offline)'),
                    const SizedBox(height: 12),
                    Text(
                      AppConstants.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppConstants.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            Center(
              child: Text(
                '© 2026 Face Recognition Attendance System',
                style: TextStyle(
                  fontSize: 11,
                  color: AppConstants.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Threshold Card with segmented buttons ──
  Widget _buildThresholdCard() {
    final Color indicatorColor;
    if (_similarityIndex == 0) {
      indicatorColor = AppConstants.successColor;
    } else if (_similarityIndex == 1) {
      indicatorColor = AppConstants.warningColor;
    } else {
      indicatorColor = AppConstants.errorColor;
    }

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.paddingMedium,
        vertical: 4,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Similarity Threshold',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // Segmented buttons
            Row(
              children: List.generate(3, (index) {
                final isSelected = _similarityIndex == index;
                final Color color;
                if (index == 0) {
                  color = AppConstants.successColor;
                } else if (index == 1) {
                  color = AppConstants.warningColor;
                } else {
                  color = AppConstants.errorColor;
                }

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : 4,
                      right: index == 2 ? 0 : 4,
                    ),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _similarityIndex = index);
                        _saveThreshold(index);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withAlpha(30)
                              : AppConstants.inputFill,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                isSelected ? color : AppConstants.cardBorder,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _modes[index],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? color
                                    : AppConstants.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _thresholds[index].toStringAsFixed(2),
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? color.withAlpha(180)
                                    : AppConstants.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),

            // Description
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: indicatorColor.withAlpha(12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: indicatorColor.withAlpha(40)),
              ),
              child: Text(
                _descriptions[_similarityIndex],
                style: TextStyle(
                  fontSize: 12,
                  color: AppConstants.textSecondary,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Data Management Card ──
  Widget _buildDataCard() {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.paddingMedium,
        vertical: 4,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Real data stats
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.inputFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _miniStat('Students', _totalStudents.toString()),
                      _miniStat('Embeddings', _totalEmbeddings.toString()),
                      _miniStat('Records', _totalAttendance.toString()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _miniStat('Subjects', _totalSubjects.toString()),
                      _miniStat('Sessions', _totalSessions.toString()),
                      _miniStat('Size', _dataSize),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Backup
            _actionTile(
              icon: Icons.backup,
              title: 'Backup Database',
              subtitle: 'Export all data as JSON (shareable)',
              color: AppConstants.primaryColor,
              onTap: _backupDatabase,
            ),
            const Divider(height: 1, color: AppConstants.dividerColor),

            // Clear attendance only
            _actionTile(
              icon: Icons.event_busy,
              title: 'Clear Attendance Records',
              subtitle: 'Keep students, remove attendance & sessions',
              color: AppConstants.warningColor,
              onTap: _clearAttendanceOnly,
            ),
            const Divider(height: 1, color: AppConstants.dividerColor),

            // Delete exports
            _actionTile(
              icon: Icons.folder_delete,
              title: 'Delete Exported Files',
              subtitle: 'Remove all saved CSV and backup files',
              color: AppConstants.warningColor,
              onTap: _deleteExportedFiles,
            ),
            const Divider(height: 1, color: AppConstants.dividerColor),

            // Full reset
            _actionTile(
              icon: Icons.delete_forever,
              title: 'Reset All Data',
              subtitle: 'Delete everything — students, faces, attendance',
              color: AppConstants.errorColor,
              onTap: () => _confirmResetDatabase(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper Widgets ──

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, color: AppConstants.primaryColor, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppConstants.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppConstants.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppConstants.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color == AppConstants.errorColor
                          ? color
                          : AppConstants.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppConstants.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppConstants.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppConstants.textSecondary,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: AppConstants.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
