import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Home Screen (Page 1)
/// Main navigation hub with buttons to all features
class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            Card(
              color: AppConstants.primaryColor,
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingLarge),
                child: Column(
                  children: [
                    const Icon(
                      Icons.face,
                      size: 64,
                      color: Colors.white,
                    ),
                    const SizedBox(height: AppConstants.paddingMedium),
                    const Text(
                      AppConstants.appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppConstants.paddingSmall),
                    Text(
                      'Offline Face Recognition System',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppConstants.paddingLarge),

            // Main Action Buttons
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppConstants.routeEnroll);
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Enroll Student'),
            ),

            const SizedBox(height: AppConstants.paddingMedium),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppConstants.routeAttendance);
              },
              icon: const Icon(Icons.camera),
              label: const Text('Take Attendance'),
            ),

            const SizedBox(height: AppConstants.paddingMedium),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppConstants.routeDatabase);
              },
              icon: const Icon(Icons.storage),
              label: const Text('View Database'),
            ),

            const SizedBox(height: AppConstants.paddingMedium),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppConstants.routeExport);
              },
              icon: const Icon(Icons.download),
              label: const Text('Export Data'),
            ),

            const SizedBox(height: AppConstants.paddingMedium),

            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, AppConstants.routeSettings);
              },
              icon: const Icon(Icons.settings),
              label: const Text('Settings'),
            ),

            const SizedBox(height: AppConstants.paddingLarge),

            // Info Cards
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.paddingMedium),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Features',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppConstants.paddingSmall),
                    _featureRow('✓', 'Offline Processing'),
                    _featureRow('✓', 'Real-time Face Detection'),
                    _featureRow('✓', 'Face Embedding Extraction'),
                    _featureRow('✓', 'Intelligent Face Matching'),
                    _featureRow('✓', 'Attendance Management'),
                    _featureRow('✓', 'Data Export (CSV/PDF)'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureRow(String icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.paddingSmall),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16, color: AppConstants.successColor)),
          const SizedBox(width: AppConstants.paddingMedium),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
