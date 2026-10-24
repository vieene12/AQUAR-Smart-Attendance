import 'package:flutter/material.dart';
import 'package:smart_attendance/core/theme/app_theme.dart';
import 'package:smart_attendance/features/admin/accounts/presentation/account_list_screen.dart';
import 'package:smart_attendance/features/admin/attendance_location/data/attendance_location_repository.dart';
import 'package:smart_attendance/features/admin/attendance_location/presentation/attendance_location_screen.dart';
import 'package:smart_attendance/features/admin/nfc_cards/data/nfc_card_repository.dart';
import 'package:smart_attendance/features/admin/nfc_cards/presentation/nfc_card_screen.dart';
import 'package:smart_attendance/features/attendance/data/nfc_availability_checker.dart';
import 'package:smart_attendance/features/attendance/data/nfc_tag_reader.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';
import 'package:smart_attendance/features/attendance/data/location_service.dart';
import 'package:smart_attendance/features/attendance/presentation/attendance_history_screen.dart';
import 'package:smart_attendance/features/attendance/presentation/attendance_screen.dart';
import 'package:smart_attendance/features/kiosk/data/nfc_kiosk_repository.dart';
import 'package:smart_attendance/features/kiosk/presentation/nfc_kiosk_screen.dart';
import 'package:smart_attendance/features/kiosk/data/kiosk_attendance_repository.dart';
import 'package:smart_attendance/features/manual_attendance/data/manual_attendance_repository.dart';
import 'package:smart_attendance/features/manual_attendance/presentation/manual_attendance_screen.dart';
import 'package:smart_attendance/features/payroll/data/payroll_repository.dart';
import 'package:smart_attendance/features/payroll/data/my_salary_repository.dart';
import 'package:smart_attendance/features/payroll/presentation/my_salary_screen.dart';
import 'package:smart_attendance/features/payroll/presentation/payroll_screen.dart';
import 'package:smart_attendance/features/statistics/data/attendance_report_repository.dart';
import 'package:smart_attendance/features/statistics/presentation/attendance_report_screen.dart';
import 'package:smart_attendance/features/statistics/data/my_attendance_report_repository.dart';
import 'package:smart_attendance/features/statistics/presentation/my_attendance_report_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({
    required this.profile,
    required this.onSignOut,
    this.locationRepository,
    this.locationService,
    this.nfcCardRepository,
    this.nfcChecker,
    this.nfcReader,
    this.kioskRepository,
    this.kioskWriter,
    this.manualAttendanceRepository,
    this.payrollRepository,
    this.attendanceReportRepository,
    super.key,
  });

  final UserProfile profile;
  final VoidCallback onSignOut;
  final AttendanceLocationRepository? locationRepository;
  final LocationService? locationService;
  final NfcCardRepository? nfcCardRepository;
  final NfcAvailabilityChecker? nfcChecker;
  final NfcTagReader? nfcReader;
  final KioskLookupRepository? kioskRepository;
  final KioskAttendanceWriter? kioskWriter;
  final ManualAttendanceRepository? manualAttendanceRepository;
  final PayrollRepository? payrollRepository;
  final AttendanceReportRepository? attendanceReportRepository;

  @override
  Widget build(BuildContext context) => _RoleHomeScaffold(
    profile: profile,
    onSignOut: onSignOut,
    locationRepository: locationRepository,
    locationService: locationService,
    nfcCardRepository: nfcCardRepository,
    nfcChecker: nfcChecker,
    nfcReader: nfcReader,
    kioskRepository: kioskRepository,
    kioskWriter: kioskWriter,
    manualAttendanceRepository: manualAttendanceRepository,
    payrollRepository: payrollRepository,
    attendanceReportRepository: attendanceReportRepository,
    roleIcon: Icons.admin_panel_settings_outlined,
    sections: const [
      _HomeSection(
        'Tổng quan',
        'Tổng quan',
        Icons.dashboard_rounded,
        Color(0xFF3D5AF1),
      ),
      _HomeSection(
        'Nhân viên',
        'Quản lý nhân viên',
        Icons.groups_rounded,
        Color(0xFF7B2FBE),
      ),
      _HomeSection(
        'Báo cáo',
        'Báo cáo thống kê',
        Icons.assessment_rounded,
        Color(0xFF00897B),
      ),
      _HomeSection(
        'Lương',
        'Bảng lương',
        Icons.payments_rounded,
        Color(0xFFE65100),
      ),
      _HomeSection(
        'Email',
        'Gửi email',
        Icons.mail_rounded,
        Color(0xFF0277BD),
      ),
      _HomeSection(
        'Vị trí',
        'Vị trí chấm công',
        Icons.place_rounded,
        Color(0xFFC62828),
      ),
      _HomeSection(
        'Thẻ NFC',
        'Quản lý thẻ NFC',
        Icons.nfc_rounded,
        Color(0xFF00838F),
      ),
      _HomeSection(
        'NFC quầy',
        'Chấm công NFC tại quầy',
        Icons.contactless_rounded,
        Color(0xFF4527A0),
      ),
      _HomeSection(
        'Thủ công',
        'Chấm công thủ công',
        Icons.edit_calendar_rounded,
        Color(0xFF558B2F),
      ),
    ],
  );
}

class ManagerHomeScreen extends StatelessWidget {
  const ManagerHomeScreen({
    required this.profile,
    required this.onSignOut,
    this.kioskRepository,
    this.kioskWriter,
    this.nfcChecker,
    this.nfcReader,
    this.manualAttendanceRepository,
    this.payrollRepository,
    this.attendanceReportRepository,
    super.key,
  });

  final UserProfile profile;
  final VoidCallback onSignOut;
  final KioskLookupRepository? kioskRepository;
  final KioskAttendanceWriter? kioskWriter;
  final NfcAvailabilityChecker? nfcChecker;
  final NfcTagReader? nfcReader;
  final ManualAttendanceRepository? manualAttendanceRepository;
  final PayrollRepository? payrollRepository;
  final AttendanceReportRepository? attendanceReportRepository;

  @override
  Widget build(BuildContext context) => _RoleHomeScaffold(
    profile: profile,
    onSignOut: onSignOut,
    kioskRepository: kioskRepository,
    kioskWriter: kioskWriter,
    nfcChecker: nfcChecker,
    nfcReader: nfcReader,
    manualAttendanceRepository: manualAttendanceRepository,
    payrollRepository: payrollRepository,
    attendanceReportRepository: attendanceReportRepository,
    roleIcon: Icons.manage_accounts_outlined,
    sections: const [
      _HomeSection(
        'Tổng quan',
        'Tổng quan',
        Icons.dashboard_rounded,
        Color(0xFF3D5AF1),
      ),
      _HomeSection(
        'Nhân viên',
        'Nhân viên phụ trách',
        Icons.groups_rounded,
        Color(0xFF7B2FBE),
      ),
      _HomeSection(
        'Chấm công',
        'Chấm công thủ công',
        Icons.edit_calendar_rounded,
        Color(0xFF558B2F),
      ),
      _HomeSection(
        'Lịch sử',
        'Lịch sử',
        Icons.history_rounded,
        Color(0xFF00838F),
      ),
      _HomeSection(
        'Báo cáo',
        'Báo cáo thống kê',
        Icons.assessment_rounded,
        Color(0xFF00897B),
      ),
      _HomeSection(
        'Lương',
        'Bảng lương',
        Icons.payments_rounded,
        Color(0xFFE65100),
      ),
      _HomeSection(
        'NFC quầy',
        'Chấm công NFC tại quầy',
        Icons.contactless_rounded,
        Color(0xFF4527A0),
      ),
    ],
  );
}

class EmployeeHomeScreen extends StatelessWidget {
  const EmployeeHomeScreen({
    required this.profile,
    required this.onSignOut,
    this.attendanceRepository,
    this.mySalaryRepository,
    this.myAttendanceReportRepository,
    super.key,
  });

  final UserProfile profile;
  final VoidCallback onSignOut;
  final AttendanceRepository? attendanceRepository;
  final MySalaryRepository? mySalaryRepository;
  final MyAttendanceReportRepository? myAttendanceReportRepository;

  @override
  Widget build(BuildContext context) => _RoleHomeScaffold(
    profile: profile,
    onSignOut: onSignOut,
    attendanceRepository: attendanceRepository,
    mySalaryRepository: mySalaryRepository,
    myAttendanceReportRepository: myAttendanceReportRepository,
    roleIcon: Icons.badge_outlined,
    sections: const [
      _HomeSection(
        'Tổng quan',
        'Tổng quan',
        Icons.dashboard_rounded,
        Color(0xFF3D5AF1),
      ),
      _HomeSection(
        'Chấm công',
        'Chấm công',
        Icons.fact_check_rounded,
        Color(0xFF00897B),
      ),
      _HomeSection(
        'Lịch sử',
        'Lịch sử chấm công',
        Icons.history_rounded,
        Color(0xFF7B2FBE),
      ),
      _HomeSection(
        'Giờ làm',
        'Giờ làm',
        Icons.schedule_rounded,
        Color(0xFF0277BD),
      ),
      _HomeSection(
        'Lương',
        'Lương của tôi',
        Icons.payments_rounded,
        Color(0xFFE65100),
      ),
      _HomeSection(
        'Báo cáo',
        'Báo cáo của tôi',
        Icons.assessment_rounded,
        Color(0xFF558B2F),
      ),
    ],
  );
}

class _HomeSection {
  const _HomeSection(
    this.navigationLabel,
    this.title,
    this.icon,
    this.color,
  );

  final String navigationLabel;
  final String title;
  final IconData icon;
  final Color color;
}

class _RoleHomeScaffold extends StatefulWidget {
  const _RoleHomeScaffold({
    required this.profile,
    required this.onSignOut,
    required this.roleIcon,
    required this.sections,
    this.attendanceRepository,
    this.mySalaryRepository,
    this.myAttendanceReportRepository,
    this.locationRepository,
    this.locationService,
    this.nfcCardRepository,
    this.nfcChecker,
    this.nfcReader,
    this.kioskRepository,
    this.kioskWriter,
    this.manualAttendanceRepository,
    this.payrollRepository,
    this.attendanceReportRepository,
  });

  final UserProfile profile;
  final VoidCallback onSignOut;
  final IconData roleIcon;
  final List<_HomeSection> sections;
  final AttendanceRepository? attendanceRepository;
  final MySalaryRepository? mySalaryRepository;
  final MyAttendanceReportRepository? myAttendanceReportRepository;
  final AttendanceLocationRepository? locationRepository;
  final LocationService? locationService;
  final NfcCardRepository? nfcCardRepository;
  final NfcAvailabilityChecker? nfcChecker;
  final NfcTagReader? nfcReader;
  final KioskLookupRepository? kioskRepository;
  final KioskAttendanceWriter? kioskWriter;
  final ManualAttendanceRepository? manualAttendanceRepository;
  final PayrollRepository? payrollRepository;
  final AttendanceReportRepository? attendanceReportRepository;

  @override
  State<_RoleHomeScaffold> createState() => _RoleHomeScaffoldState();
}

class _RoleHomeScaffoldState extends State<_RoleHomeScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppTheme.darkPrimaryGradient
                : AppTheme.primaryGradient,
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withAlpha(50),
                  width: 1,
                ),
              ),
              child: Icon(Icons.fact_check_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'Smart Attendance',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          if (wide)
            TextButton.icon(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
              label: const Text(
                'Đăng xuất',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            )
          else
            IconButton(
              onPressed: widget.onSignOut,
              tooltip: 'Đăng xuất',
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectSection,
                    extended: true,
                    destinations: _railDestinations(),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildContent()),
              ],
            )
          : _buildContent(),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectSection,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              destinations: _bottomDestinations(),
            ),
    );
  }

  void _selectSection(int index) {
    if (widget.profile.role == UserRole.employee && index == 5) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MyAttendanceReportScreen(
            profile: widget.profile,
            repository: widget.myAttendanceReportRepository,
          ),
        ),
      );
      return;
    }
    if ((widget.profile.role == UserRole.admin && index == 2) ||
        (widget.profile.role == UserRole.manager && index == 4)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AttendanceReportScreen(
            profile: widget.profile,
            repository: widget.attendanceReportRepository,
          ),
        ),
      );
      return;
    }
    if (widget.profile.role == UserRole.employee && index == 4) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MySalaryScreen(
            profile: widget.profile,
            repository: widget.mySalaryRepository,
          ),
        ),
      );
      return;
    }
    if ((widget.profile.role == UserRole.admin && index == 3) ||
        (widget.profile.role == UserRole.manager && index == 5)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PayrollScreen(
            profile: widget.profile,
            repository: widget.payrollRepository,
          ),
        ),
      );
      return;
    }
    if (widget.profile.role == UserRole.admin && index == 1) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AccountListScreen(profile: widget.profile),
        ),
      );
      return;
    }

    if (widget.profile.role == UserRole.admin && index == 5) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AttendanceLocationScreen(
            repository: widget.locationRepository,
            locationService: widget.locationService,
          ),
        ),
      );
      return;
    }

    if (widget.profile.role == UserRole.admin && index == 6) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NfcCardScreen(
            profile: widget.profile,
            repository: widget.nfcCardRepository,
            checker: widget.nfcChecker,
            reader: widget.nfcReader,
          ),
        ),
      );
      return;
    }

    if ((widget.profile.role == UserRole.admin && index == 7) ||
        (widget.profile.role == UserRole.manager && index == 6)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NfcKioskScreen(
            profile: widget.profile,
            repository: widget.kioskRepository,
            writer: widget.kioskWriter,
            checker: widget.nfcChecker,
            reader: widget.nfcReader,
          ),
        ),
      );
      return;
    }

    if ((widget.profile.role == UserRole.admin && index == 8) ||
        (widget.profile.role == UserRole.manager && index == 2)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ManualAttendanceScreen(
            profile: widget.profile,
            repository: widget.manualAttendanceRepository,
          ),
        ),
      );
      return;
    }

    setState(() => _selectedIndex = index);
  }

  List<NavigationRailDestination> _railDestinations() => [
    for (final section in widget.sections)
      NavigationRailDestination(
        icon: Icon(section.icon),
        label: Text(section.navigationLabel),
      ),
  ];

  List<NavigationDestination> _bottomDestinations() => [
    for (final section in widget.sections)
      NavigationDestination(
        icon: Icon(section.icon),
        label: section.navigationLabel,
        tooltip: section.title,
      ),
  ];

  Widget _buildContent() {
    final theme = Theme.of(context);
    final section = widget.sections[_selectedIndex];
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── User profile card ────────────────────────────────────
                _UserProfileCard(
                  profile: widget.profile,
                  roleIcon: widget.roleIcon,
                  isDark: isDark,
                ),
                const SizedBox(height: 20),

                // ── Section header ────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(section.title, style: theme.textTheme.headlineSmall),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Content ───────────────────────────────────────────────
                if (_selectedIndex == 0) ...[
                  _buildFeatureCards(),
                ] else if (widget.profile.role == UserRole.employee &&
                    _selectedIndex == 1)
                  AttendanceScreen(
                    employeeId: widget.profile.uid,
                    repository: widget.attendanceRepository,
                  )
                else if (widget.profile.role == UserRole.employee &&
                    _selectedIndex == 2)
                  AttendanceHistoryScreen(
                    employeeId: widget.profile.uid,
                    repository: widget.attendanceRepository,
                  )
                else
                  _buildComingSoon(section),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCards() => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 14.0;
      final width = constraints.maxWidth;
      final columns = width >= 760 ? 3 : (width >= 500 ? 2 : 1);
      final cardWidth = (width - (columns - 1) * gap) / columns;

      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var index = 1; index < widget.sections.length; index++)
            SizedBox(
              width: cardWidth,
              child: _FeatureCard(
                section: widget.sections[index],
                subtitle: _cardSubtitle(index),
                onTap: () => _selectSection(index),
              ),
            ),
        ],
      );
    },
  );

  String _cardSubtitle(int index) {
    if (widget.profile.role == UserRole.admin && index == 1) {
      return 'Xem danh sách tài khoản';
    } else if (widget.profile.role == UserRole.admin && index == 5) {
      return 'Thiết lập vị trí chấm công';
    } else if (widget.profile.role == UserRole.admin && index == 6) {
      return 'Đăng ký và thu hồi thẻ NFC';
    } else if ((widget.profile.role == UserRole.admin && index == 7) ||
        (widget.profile.role == UserRole.manager && index == 6)) {
      return 'Quét thẻ và xem trạng thái chấm công hôm nay';
    } else if ((widget.profile.role == UserRole.admin && index == 8) ||
        (widget.profile.role == UserRole.manager && index == 2)) {
      return 'Xem và điều chỉnh chấm công thủ công';
    } else if ((widget.profile.role == UserRole.admin && index == 3) ||
        (widget.profile.role == UserRole.manager && index == 5)) {
      return 'Xem giờ công và lương tạm tính';
    } else if ((widget.profile.role == UserRole.admin && index == 2) ||
        (widget.profile.role == UserRole.manager && index == 4)) {
      return 'Xem thống kê chấm công theo kỳ';
    } else if (widget.profile.role == UserRole.employee && index == 1) {
      return 'Xem giờ hiện tại và chấm công';
    } else if (widget.profile.role == UserRole.employee && index == 2) {
      return 'Xem các lần chấm công đã ghi nhận';
    } else if (widget.profile.role == UserRole.employee && index == 5) {
      return 'Xem thống kê chấm công của bạn';
    }
    return 'Đang phát triển';
  }

  Widget _buildComingSoon(_HomeSection section) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2444) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 12),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: section.color.withAlpha(25),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(section.icon, size: 38, color: section.color),
          ),
          const SizedBox(height: 20),
          Text(
            section.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF3D5AF1).withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Đang phát triển',
              style: TextStyle(
                color: const Color(0xFF3D5AF1),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _UserProfileCard extends StatelessWidget {
  const _UserProfileCard({
    required this.profile,
    required this.roleIcon,
    required this.isDark,
  });

  final UserProfile profile;
  final IconData roleIcon;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark
            ? AppTheme.darkPrimaryGradient
            : AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3D5AF1).withAlpha(isDark ? 50 : 70),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withAlpha(60),
                width: 1.5,
              ),
            ),
            child: Icon(roleIcon, size: 28, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    profile.role.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Online indicator
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF69F0AE),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x5569F0AE),
                      blurRadius: 6,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Online',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({
    required this.section,
    required this.subtitle,
    required this.onTap,
  });

  final _HomeSection section;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = widget.section.color;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -4.0 : 0.0, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A2444) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(_hovered ? 60 : 20),
                blurRadius: _hovered ? 24 : 12,
                offset: Offset(0, _hovered ? 8.0 : 4.0),
              ),
            ],
            border: Border.all(
              color: _hovered ? color.withAlpha(80) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon container
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withAlpha(isDark ? 40 : 25),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(widget.section.icon, size: 28, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                widget.section.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              // Arrow chip
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Xem thêm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
