import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Home Screen (Page 1)
/// Main navigation hub with buttons to all features
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        elevation: 0,
        flexibleSpace: Container(decoration: BoxDecoration(gradient: AppConstants.blueGradient)),
      ),
      body: AnimatedBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card with Gradient
              Container(
                decoration: BoxDecoration(
                  gradient: AppConstants.blueGradient,
                  borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
                  boxShadow: [AppConstants.buttonShadow],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.paddingLarge),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(26),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.face,
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: AppConstants.paddingMedium),
                      const Text(
                        'Face Recognition System',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppConstants.paddingSmall),
                      Text(
                        'Intelligent Offline Attendance Management',
                        style: TextStyle(
                          color: Colors.white.withAlpha(220),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Core Actions Section
              _sectionHeader('Core Actions'),
              _actionButton(
                context,
                icon: Icons.person_add,
                label: 'Enroll Student',
                subtitle: 'Add new student face',
                route: AppConstants.routeEnroll,
                color: AppConstants.primaryColor,
              ),

              const SizedBox(height: AppConstants.paddingMedium),

              _actionButton(
                context,
                icon: Icons.camera,
                label: 'Take Attendance',
                subtitle: 'Mark attendance via camera',
                route: AppConstants.routeAttendance,
                color: AppConstants.successColor,
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Management Section
              _sectionHeader('Management'),
              Row(
                children: [
                  Expanded(
                    child: _smallActionButton(
                      context,
                      icon: Icons.storage,
                      label: 'Database',
                      route: AppConstants.routeDatabase,
                    ),
                  ),
                  const SizedBox(width: AppConstants.paddingMedium),
                  Expanded(
                    child: _smallActionButton(
                      context,
                      icon: Icons.download,
                      label: 'Export',
                      route: AppConstants.routeExport,
                    ),
                  ),
                  const SizedBox(width: AppConstants.paddingMedium),
                  Expanded(
                    child: _smallActionButton(
                      context,
                      icon: Icons.settings,
                      label: 'Settings',
                      route: AppConstants.routeSettings,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              // Features Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.paddingMedium),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withAlpha(26),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.star,
                              size: 20,
                              color: AppConstants.primaryColor,
                            ),
                          ),
                          const SizedBox(width: AppConstants.paddingSmall),
                          const Text(
                            'Features',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.paddingMedium),
                      _featureRow('🔒', 'Offline Processing'),
                      _featureRow('📷', 'Real-time Face Detection'),
                      _featureRow('🧠', 'Face Embedding Extraction'),
                      _featureRow('🎯', 'Intelligent Face Matching'),
                      _featureRow('📝', 'Attendance Management'),
                      _featureRow('📊', 'Data Export (CSV/PDF)'),
                    ],
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

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.paddingSmall),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppConstants.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required String route,
    required Color color,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
          border: Border.all(color: AppConstants.cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: AppConstants.paddingMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppConstants.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          border: Border.all(color: AppConstants.cardBorder),
        ),
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: AppConstants.primaryColor),
            const SizedBox(height: AppConstants.paddingSmall),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: AppConstants.paddingMedium),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppConstants.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
