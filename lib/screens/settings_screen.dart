import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

/// Settings Screen
/// Configure app behavior and access information
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _similarityThreshold = AppConstants.similarityThreshold;
  bool? _enableVideo;
  bool? _enableGradient;

  @override
  void initState() {
    super.initState();
    _loadThreshold();
    _loadVisualPreferences();
  }

  Future<void> _loadVisualPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enableVideo = prefs.getBool('enable_background_video') ?? false;
      _enableGradient = prefs.getBool('enable_animated_gradient') ?? true;
    });
  }

  Future<void> _loadThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _similarityThreshold = prefs.getDouble('similarity_threshold') ?? AppConstants.similarityThreshold;
    });
  }

  Future<void> _saveThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('similarity_threshold', value);
    debugPrint('💾 Saved similarity threshold: $value');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedBackground(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Face Recognition Settings
              _buildSettingsSection(
                title: 'Face Recognition',
                icon: Icons.face,
                child: Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                    vertical: AppConstants.paddingSmall,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.paddingLarge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Similarity Threshold',
                              style: TextStyle(fontSize: 14),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppConstants.primaryColor.withAlpha(26),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _similarityThreshold.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppConstants.primaryColor,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppConstants.paddingMedium),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppConstants.primaryColor,
                            thumbColor: AppConstants.primaryColor,
                            overlayColor: AppConstants.primaryColor.withAlpha(64),
                          ),
                          child: Slider(
                            value: _similarityThreshold,
                            min: 0.4,
                            max: 0.9,
                            divisions: 10,
                            onChanged: (value) {
                              setState(() => _similarityThreshold = value);
                              _saveThreshold(value);
                            },
                          ),
                        ),
                        const SizedBox(height: AppConstants.paddingSmall),
                        Container(
                          padding: const EdgeInsets.all(AppConstants.paddingSmall),
                          decoration: BoxDecoration(
                            color: AppConstants.inputFill,
                            borderRadius: BorderRadius.circular(
                              AppConstants.borderRadius,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info,
                                size: 16,
                                color: AppConstants.textTertiary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Lower = More matches · Higher = More strict',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppConstants.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Database Settings
              _buildSettingsSection(
                title: 'Database',
                icon: Icons.storage,
                child: Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                    vertical: AppConstants.paddingSmall,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.paddingMedium),
                    child: Column(
                      children: [
                        _settingsListTile(
                          icon: Icons.storage,
                          title: 'Database Size',
                          subtitle: '~5.2 MB',
                          onTap: () {},
                        ),
                        const Divider(height: 1, color: AppConstants.dividerColor),
                        _settingsListTile(
                          icon: Icons.backup,
                          title: 'Backup Database',
                          subtitle: 'Export database backup',
                          onTap: () {},
                        ),
                        const Divider(height: 1, color: AppConstants.dividerColor),
                        _settingsListTile(
                          icon: Icons.delete_sweep,
                          title: 'Reset Database',
                          subtitle: 'Delete all data and start fresh',
                          onTap: () => _confirmResetDatabase(context),
                          color: AppConstants.errorColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Model Information
              _buildSettingsSection(
                title: 'Models & Information',
                icon: Icons.info,
                child: Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                    vertical: AppConstants.paddingSmall,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.paddingLarge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow('Face Detector:', 'ML Kit Face Detector'),
                        _infoRow('Embedding Model:', 'MobileFaceNet'),
                        _infoRow('Matching Method:', 'Cosine Similarity'),
                        _infoRow('Embedding Dimension:', '192'),
                        _infoRow('Enrollment Samples:', '20-30'),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Visuals
              _buildSettingsSection(
                title: 'Visuals',
                icon: Icons.palette,
                child: Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                    vertical: AppConstants.paddingSmall,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.paddingLarge),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Enable Background Video (opt-in)'),
                          value: _enableVideo ?? false,
                          onChanged: (v) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('enable_background_video', v);
                            setState(() => _enableVideo = v);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v ? 'Background video enabled' : 'Background video disabled')));
                          },
                          secondary: const Icon(Icons.video_library),
                        ),
                        const Divider(height: 1, color: AppConstants.dividerColor),
                        SwitchListTile(
                          title: const Text('Enable Animated Gradient Background'),
                          value: _enableGradient ?? true,
                          onChanged: (v) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('enable_animated_gradient', v);
                            setState(() => _enableGradient = v);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(v ? 'Animated gradient enabled' : 'Animated gradient disabled')));
                          },
                          secondary: const Icon(Icons.gradient),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // About
              _buildSettingsSection(
                title: 'About',
                icon: Icons.app_registration,
                child: Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium,
                    vertical: AppConstants.paddingSmall,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.paddingLarge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow('App Name:', AppConstants.appName),
                        const SizedBox(height: AppConstants.paddingSmall),
                        _infoRow('Version:', AppConstants.appVersion),
                        const SizedBox(height: AppConstants.paddingMedium),
                        Container(
                          padding: const EdgeInsets.all(AppConstants.paddingMedium),
                          decoration: BoxDecoration(
                            color: AppConstants.inputFill,
                            borderRadius: BorderRadius.circular(
                              AppConstants.borderRadius,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Description:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: AppConstants.paddingSmall),
                              Text(
                                AppConstants.subtitle,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppConstants.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Footer
              Container(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Center(
                  child: Text(
                    '© 2026 Offline Face Recognition System',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppConstants.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.paddingMedium,
            AppConstants.paddingLarge,
            AppConstants.paddingMedium,
            AppConstants.paddingSmall,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: AppConstants.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppConstants.paddingSmall),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        child,
      ],
    );
  }

  Widget _settingsListTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color color = AppConstants.textPrimary,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.paddingMedium,
          vertical: AppConstants.paddingSmall,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppConstants.paddingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppConstants.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward,
              color: AppConstants.textTertiary,
              size: 18,
            ),
          ],
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
          Text(value, style: const TextStyle(color: AppConstants.textSecondary)),
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
                // Clear all SharedPreferences data
                final prefs = await SharedPreferences.getInstance();
                
                // Delete all stored data
                await prefs.remove('students');
                await prefs.remove('embeddings');
                await prefs.remove('attendance');
                await prefs.remove('subjects');
                await prefs.remove('teacherSessions');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Database cleared successfully! You can now start fresh.',
                      ),
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
            child: const Text(
              'Reset All Data',
              style: TextStyle(color: AppConstants.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}
