import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../database/database_manager.dart';

/// Settings Screen
/// Configure app behavior and access information
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseManager _dbManager = DatabaseManager();
  double _similarityThreshold = AppConstants.similarityThreshold;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Recognition Settings
            _buildSectionHeader('Face Recognition'),
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: AppConstants.paddingSmall,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Similarity Threshold:'),
                        Text(
                          _similarityThreshold.toStringAsFixed(2),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.paddingMedium),
                    Slider(
                      value: _similarityThreshold,
                      min: 0.4,
                      max: 0.9,
                      divisions: 10,
                      onChanged: (value) {
                        setState(() => _similarityThreshold = value);
                      },
                    ),
                    const SizedBox(height: AppConstants.paddingSmall),
                    Text(
                      'Lower = More matches, Higher = More strict',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppConstants.paddingLarge),

            // Database Settings
            _buildSectionHeader('Database'),
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: AppConstants.paddingSmall,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Database Size'),
                      subtitle: const Text('~5.2 MB'),
                      leading: const Icon(Icons.storage),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () {},
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Backup Database'),
                      subtitle: const Text('Export database backup'),
                      leading: const Icon(Icons.backup),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () {},
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('Reset Database'),
                      subtitle: const Text('Delete all data and start fresh'),
                      leading: const Icon(Icons.delete, color: AppConstants.errorColor),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () => _confirmResetDatabase(context),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppConstants.paddingLarge),

            // Model Information
            _buildSectionHeader('Models & Information'),
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: AppConstants.paddingSmall,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('Face Detector:', 'YOLO TFLite'),
                    _infoRow('Embedding Model:', 'MobileFaceNet'),
                    _infoRow('Matching Method:', 'Cosine Similarity'),
                    _infoRow('Embedding Dimension:', '192'),
                    _infoRow('Enrollment Samples:', '20-30'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppConstants.paddingLarge),

            // About
            _buildSectionHeader('About'),
            Card(
              margin: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: AppConstants.paddingSmall,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoRow('App Name:', AppConstants.appName),
                    _infoRow('Version:', AppConstants.appVersion),
                    const SizedBox(height: AppConstants.paddingMedium),
                    const Text(
                      'Description:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppConstants.paddingSmall),
                    const Text(
                      AppConstants.subtitle,
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppConstants.paddingLarge),

            // Developer Info
            Container(
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
              child: Center(
                child: Text(
                  '© 2026 Offline Face Recognition System',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.paddingMedium,
        AppConstants.paddingLarge,
        AppConstants.paddingMedium,
        AppConstants.paddingSmall,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppConstants.primaryColor,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.paddingSmall),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _confirmResetDatabase(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Database?'),
        content: const Text(
          'This will delete all students, embeddings, and attendance records. After doing this, you can enroll fresh data with the fixed recognition logic.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              
              try {
                final db = await _dbManager.database;
                
                // Clear all tables
                await db.delete('students');
                await db.delete('embeddings');
                await db.delete('attendance');
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Database cleared successfully! You can now start fresh.'),
                      backgroundColor: AppConstants.successColor,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error clearing database: $e'),
                      backgroundColor: AppConstants.errorColor,
                    ),
                  );
                }
              }
            },
            child: const Text('Reset All Data', style: TextStyle(color: AppConstants.errorColor)),
          ),
        ],
      ),
    );
  }
}
