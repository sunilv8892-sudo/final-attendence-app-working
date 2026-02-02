import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../database/database_manager.dart';
import '../modules/m4_attendance_management.dart';
import '../utils/constants.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final DatabaseManager _dbManager;
  late final AttendanceManagementModule _attendanceModule;
  final List<ExportRecord> _history = [];
  Directory? _exportDirectory;
  bool _isInitializing = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _setupExportEnvironment();
  }

  Future<void> _setupExportEnvironment() async {
    _dbManager = DatabaseManager();
    await _dbManager.database;
    _attendanceModule = AttendanceManagementModule(_dbManager);

    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/FaceAttendanceExports');
    await dir.create(recursive: true);

    final existing = dir
        .listSync()
        .whereType<File>()
        .map((file) => ExportRecord(
              format: file.path.split('.').last.toUpperCase(),
              path: file.path,
              timestamp: FileStat.statSync(file.path).modified,
            ))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (!mounted) return;
    setState(() {
      _exportDirectory = dir;
      _history.addAll(existing);
      _isInitializing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Data')),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _glassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.paddingMedium),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Export Format', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: AppConstants.paddingMedium),
                          const Text('Files are saved inside FaceAttendanceExports under your documents folder.'),
                          const SizedBox(height: AppConstants.paddingMedium),
                          ElevatedButton.icon(
                            onPressed: _isExporting ? null : () => _exportData('CSV'),
                            icon: const Icon(Icons.text_fields),
                            label: const Text('Export as CSV'),
                          ),
                          const SizedBox(height: AppConstants.paddingSmall),
                          ElevatedButton.icon(
                            onPressed: _isExporting ? null : () => _exportData('Excel'),
                            icon: const Icon(Icons.table_chart),
                            label: const Text('Export as Excel'),
                          ),
                          const SizedBox(height: AppConstants.paddingSmall),
                          ElevatedButton.icon(
                            onPressed: _isExporting ? null : () => _exportData('PDF'),
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('Export as PDF'),
                          ),
                          const SizedBox(height: AppConstants.paddingMedium),
                          Text(
                            'Location: ${_exportDirectory?.path ?? 'Preparing folder...'}',
                            style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: AppConstants.paddingSmall),
                          Text(
                            _isExporting ? 'Exporting...' : 'Ready for export',
                            style: TextStyle(
                              fontSize: 12,
                              color: _isExporting ? AppConstants.warningColor : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.paddingLarge),
                  _glassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppConstants.paddingMedium),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Recent exports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: AppConstants.paddingMedium),
                          if (_history.isEmpty)
                            const Text('No exports yet. Tap a button above to create one.')
                          else
                            Column(
                              children: _history.map(_historyRow).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Card(
      color: Colors.white.withAlpha((0.18 * 255).round()),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.borderRadius)),
      clipBehavior: Clip.antiAlias,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: child,
        ),
      ),
    );
  }

  Widget _historyRow(ExportRecord record) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.paddingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(record.format, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(_friendlyTimestamp(record.timestamp), style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
          const SizedBox(height: AppConstants.paddingSmall / 2),
          SelectableText(record.path, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          if (record != _history.last) Divider(color: Colors.white24)
        ],
      ),
    );
  }

  String _friendlyTimestamp(DateTime timestamp) {
    final year = timestamp.year;
    final month = timestamp.month.toString().padLeft(2, '0');
    final day = timestamp.day.toString().padLeft(2, '0');
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  Future<void> _exportData(String format) async {
    if (_isExporting || _exportDirectory == null) return;
    setState(() {
      _isExporting = true;
    });

    final extension = format == 'PDF'
        ? 'pdf'
        : format == 'Excel'
            ? 'xlsx'
            : 'csv';
    final timeStamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:\\.]'), '-');
    final file = File('${_exportDirectory!.path}/attendance_${format.toLowerCase()}_$timeStamp.$extension');

    try {
      if (format == 'PDF') {
        await _writePdf(file);
      } else {
        final csv = await _attendanceModule.exportAsCSV();
        await file.writeAsString(csv, flush: true);
      }

      final record = ExportRecord(format: format, path: file.path, timestamp: DateTime.now());
      if (mounted) {
        setState(() {
          _history.insert(0, record);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ${file.path}'),
            backgroundColor: AppConstants.successColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppConstants.errorColor),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Future<void> _writePdf(File file) async {
    final csv = await _attendanceModule.exportAsCSV();
    final lines = LineSplitter().convert(csv).where((line) => line.trim().isNotEmpty).toList();
    final headers = lines.isEmpty ? <String>[] : lines.first.split(',');
    final data = lines.length > 1
        ? lines.skip(1).map((line) => line.split(',')).toList()
        : <List<String>>[];

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(24),
        build: (context) {
          final children = <pw.Widget>[
            pw.Text('Attendance Export', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('Generated from ${AppConstants.appName} on ${_friendlyTimestamp(DateTime.now())}'),
            pw.SizedBox(height: 16),
          ];
          if (headers.isNotEmpty) {
            children.add(
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: PdfColors.blueGrey900),
                cellAlignment: pw.Alignment.centerLeft,
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              ),
            );
          } else {
              children.add(pw.Text('No attendance data available.'));
          }
          return children;
        },
      ),
    );

    final bytes = await pdf.save();
    await file.writeAsBytes(bytes, flush: true);
  }
}

class ExportRecord {
  final String format;
  final String path;
  final DateTime timestamp;

  ExportRecord({
    required this.format,
    required this.path,
    required this.timestamp,
  });
}
