import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/animated_background.dart';
import '../database/database_manager.dart';
import '../modules/m4_attendance_management.dart';
import '../models/attendance_model.dart';

/// Home Screen (Page 1)
/// Main navigation hub with buttons to all features
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DatabaseManager _dbManager;
  late final AttendanceManagementModule _attendanceModule;

  int _totalStudents = 0;
  int _presentToday = 0;
  int _totalSessions = 0;

  @override
  void initState() {
    super.initState();
    _dbManager = DatabaseManager();
    _attendanceModule = AttendanceManagementModule(_dbManager);
    _loadStats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload stats when screen comes into focus
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      // Get total students count
      final students = await _dbManager.getAllStudents();
      final totalStudents = students.length;

      // Get today's attendance count (unique students marked present)
      final today = DateTime.now();
      final todayRecords = await _dbManager.getAttendanceForDate(today);
      
      // Count unique students who are marked as present today
      final presentStudentIds = todayRecords
          .where((record) => record.status == AttendanceStatus.present)
          .map((record) => record.studentId)
          .toSet(); // Use Set to get unique student IDs
      
      final presentToday = presentStudentIds.length;

      // Get total sessions (unique dates with attendance records)
      final allAttendance = await _dbManager.getAllAttendance();
      final uniqueDates = allAttendance
          .map(
            (record) =>
                DateTime(record.date.year, record.date.month, record.date.day),
          )
          .toSet()
          .length;

      setState(() {
        _totalStudents = totalStudents;
        _presentToday = presentToday;
        _totalSessions = uniqueDates;
      });
    } catch (e) {
      // Handle errors gracefully
      setState(() {
        _totalStudents = 0;
        _presentToday = 0;
        _totalSessions = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.cardColor,
      appBar: AppBar(
        title: const Text('Face Attendance'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppConstants.textPrimary,
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: AppConstants.primaryColor),
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppConstants.cardColor,
              AppConstants.cardColor.withAlpha(245),
              AppConstants.cardColor.withAlpha(240),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                // Header Section
                _buildHeaderSection(),

                const SizedBox(height: 24),

                // Main Dashboard Grid
                Expanded(child: _buildDashboardGrid(context)),

                // Bottom Stats Bar
                _buildBottomStatsBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppConstants.primaryColor.withAlpha(20),
            AppConstants.primaryColor.withAlpha(10),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppConstants.primaryColor.withAlpha(30),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppConstants.primaryColor,
                  AppConstants.primaryColor.withAlpha(180),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppConstants.primaryColor.withAlpha(100),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.face_retouching_natural,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Attendance',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'AI-powered face recognition system',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppConstants.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.1,
      children: [
        // Primary Actions
        _buildHexagonalCard(
          context,
          icon: Icons.person_add,
          title: 'Enroll\nStudents',
          subtitle: 'Add faces',
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          route: AppConstants.routeEnroll,
        ),

        _buildHexagonalCard(
          context,
          icon: Icons.camera_alt,
          title: 'Take\nAttendance',
          subtitle: 'Scan faces',
          gradient: const LinearGradient(
            colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          route: AppConstants.routeAttendance,
        ),

        // Management Tools
        _buildCircularCard(
          context,
          icon: Icons.storage,
          title: 'Database',
          subtitle: 'Manage students',
          color: const Color(0xFFFFA726),
          route: AppConstants.routeDatabase,
        ),

        _buildCircularCard(
          context,
          icon: Icons.download_rounded,
          title: 'Export',
          subtitle: 'Reports',
          color: const Color(0xFF42A5F5),
          route: AppConstants.routeExport,
        ),

        _buildCircularCard(
          context,
          icon: Icons.tune,
          title: 'Settings',
          subtitle: 'Configure',
          color: const Color(0xFFAB47BC),
          route: AppConstants.routeSettings,
        ),

        // Feature Highlight
        _buildFeatureHighlightCard(),
      ],
    );
  }

  Widget _buildQuickToolsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.paddingMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(
              left: AppConstants.paddingSmall,
              bottom: AppConstants.paddingMedium,
            ),
            child: Text(
              'Management Tools',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppConstants.textPrimary,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  icon: Icons.storage,
                  title: 'Database',
                  subtitle: 'View & manage students',
                  route: AppConstants.routeDatabase,
                ),
              ),
              const SizedBox(width: AppConstants.paddingMedium),
              Expanded(
                child: _buildToolCard(
                  context,
                  icon: Icons.download_rounded,
                  title: 'Export',
                  subtitle: 'Generate reports',
                  route: AppConstants.routeExport,
                ),
              ),
              const SizedBox(width: AppConstants.paddingMedium),
              Expanded(
                child: _buildToolCard(
                  context,
                  icon: Icons.tune,
                  title: 'Settings',
                  subtitle: 'Configure app',
                  route: AppConstants.routeSettings,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesPreview() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.paddingMedium,
      ),
      padding: const EdgeInsets.all(AppConstants.paddingLarge),
      decoration: BoxDecoration(
        color: AppConstants.cardColor,
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
        border: Border.all(color: AppConstants.cardBorder),
        boxShadow: [AppConstants.cardShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: AppConstants.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Key Features',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.paddingMedium),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildFeatureItem(Icons.offline_bolt, 'Offline Operation'),
              _buildFeatureItem(Icons.speed, 'Real-time Detection'),
              _buildFeatureItem(Icons.memory, 'Smart Embeddings'),
              _buildFeatureItem(Icons.verified, 'Accurate Matching'),
              _buildFeatureItem(Icons.history, 'Attendance Logs'),
              _buildFeatureItem(Icons.file_download, 'Export Reports'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
    required Gradient gradient,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withAlpha(100),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withAlpha(220),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
          border: Border.all(color: AppConstants.cardBorder),
          boxShadow: [AppConstants.cardShadow],
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: AppConstants.primaryColor),
              ),
              const SizedBox(height: AppConstants.paddingSmall),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppConstants.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppConstants.inputFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppConstants.cardBorder.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppConstants.primaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppConstants.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatsBar() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.cardColor,
        borderRadius: BorderRadius.circular(AppConstants.borderRadiusLarge),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: RepaintBoundary(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              icon: Icons.people,
              value: _totalStudents.toString(),
              label: 'Students',
              color: const Color(0xFF667EEA),
            ),
            _buildStatItem(
              icon: Icons.check_circle,
              value: _presentToday.toString(),
              label: 'Present Today',
              color: const Color(0xFF11998E),
            ),
            _buildStatItem(
              icon: Icons.schedule,
              value: _totalSessions.toString(),
              label: 'Sessions',
              color: const Color(0xFFFFA726),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppConstants.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: AppConstants.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildHexagonalCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required LinearGradient gradient,
    required String route,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withAlpha(100),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha(220),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircularCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String route,
  }) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, route),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppConstants.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(50)),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(20),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppConstants.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureHighlightCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.primaryColor.withAlpha(30)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.offline_bolt,
              color: AppConstants.primaryColor,
              size: 24,
            ),
            const SizedBox(height: 8),
            const Text(
              'Offline\nOperation',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Works without internet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppConstants.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Face Attendance'),
        content: const Text(
          'AI-powered face recognition system for seamless attendance tracking. '
          'Works completely offline with high accuracy and real-time detection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
