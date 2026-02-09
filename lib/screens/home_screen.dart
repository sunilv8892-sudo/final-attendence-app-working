import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/animated_background.dart';

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
              _heroHeader(context),
              const SizedBox(height: AppConstants.paddingLarge),

              _sectionHeader('Quick Actions'),
              Row(
                children: [
                  Expanded(
                    child: _actionCard(
                      context,
                      icon: Icons.person_add,
                      label: 'Enroll',
                      subtitle: 'Add students',
                      route: AppConstants.routeEnroll,
                      color: AppConstants.primaryColor,
                    ),
                  ),
                  const SizedBox(width: AppConstants.paddingMedium),
                  Expanded(
                    child: _actionCard(
                      context,
                      icon: Icons.camera_alt,
                      label: 'Attendance',
                      subtitle: 'Scan faces',
                      route: AppConstants.routeAttendance,
                      color: AppConstants.successColor,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              _sectionHeader('Tools'),
              Row(
                children: [
                  Expanded(
                    child: _toolCard(
                      context,
                      icon: Icons.storage,
                      label: 'Database',
                      route: AppConstants.routeDatabase,
                    ),
                  ),
                  const SizedBox(width: AppConstants.paddingMedium),
                  Expanded(
                    child: _toolCard(
                      context,
                      icon: Icons.download_rounded,
                      label: 'Export',
                      route: AppConstants.routeExport,
                    ),
                  ),
                  const SizedBox(width: AppConstants.paddingMedium),
                  Expanded(
                    child: _toolCard(
                      context,
                      icon: Icons.tune,
                      label: 'Settings',
                      route: AppConstants.routeSettings,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.paddingLarge),

              _sectionHeader('Features'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _FeatureChip(label: 'Offline'),
                  _FeatureChip(label: 'Real-time Detection'),
                  _FeatureChip(label: 'Embeddings'),
                  _FeatureChip(label: 'Smart Matching'),
                  _FeatureChip(label: 'Attendance Logs'),
                  _FeatureChip(label: 'CSV/PDF Export'),
                ],
              ),
              const SizedBox(height: AppConstants.paddingLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.paddingLarge),
      decoration: BoxDecoration(
        gradient: AppConstants.blueGradient,
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
        boxShadow: [AppConstants.buttonShadow],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.face_retouching_natural, color: Colors.white, size: 36),
          ),
          const SizedBox(width: AppConstants.paddingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Smart, offline face attendance',
                  style: TextStyle(
                    color: Colors.white.withAlpha(220),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        ],
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
          Widget _actionCard(
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
            return InkWell(
    required String label,
    required String subtitle,
    required String route,
    required Color color,
                  borderRadius: BorderRadius.circular(14),
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
                  padding: const EdgeInsets.all(AppConstants.paddingMedium),
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
          border: Border.all(color: AppConstants.cardBorder),
                        padding: const EdgeInsets.all(10),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Row(
            children: [
                        child: Icon(icon, size: 24, color: color),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(width: AppConstants.paddingMedium),
              Expanded(
                                fontSize: 14,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                                fontSize: 12,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                      Icon(Icons.arrow_forward_ios, color: color, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: color),
            ],
          Widget _toolCard(
        ),
      ),
    );
  }

  Widget _smallActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
                  borderRadius: BorderRadius.circular(12),
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
                        fontSize: 11,
            const SizedBox(height: AppConstants.paddingSmall),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),

        class _FeatureChip extends StatelessWidget {
          final String label;

          const _FeatureChip({required this.label});

          @override
          Widget build(BuildContext context) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppConstants.cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppConstants.cardBorder),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppConstants.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }
        }
          ),
        ],
      ),
    );
  }
}
