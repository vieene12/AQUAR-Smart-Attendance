import 'package:flutter/material.dart';
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
      _HomeSection('Tổng quan', 'Tổng quan', Icons.dashboard_outlined),
      _HomeSection('Nhân viên', 'Quản lý nhân viên', Icons.groups_outlined),
      _HomeSection(
        'Báo cáo thống kê',
        'Báo cáo thống kê',
        Icons.assessment_outlined,
      ),
      _HomeSection('Lương', 'Bảng lương', Icons.payments_outlined),
      _HomeSection('Email', 'Gửi email', Icons.mail_outline),
      _HomeSection(
        'Vị trí chấm công',
        'Vị trí chấm công',
        Icons.place_outlined,
      ),
      _HomeSection('Thẻ NFC', 'Quản lý thẻ NFC', Icons.nfc_outlined),
      _HomeSection(
        'NFC tại quầy',
        'Chấm công NFC tại quầy',
        Icons.contactless_outlined,
      ),
      _HomeSection(
        'Thủ công',
        'Chấm công thủ công',
        Icons.edit_calendar_outlined,
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
      _HomeSection('Tổng quan', 'Tổng quan', Icons.dashboard_outlined),
      _HomeSection('Nhân viên', 'Nhân viên phụ trách', Icons.groups_outlined),
      _HomeSection(
        'Chấm công',
        'Chấm công thủ công',
        Icons.edit_calendar_outlined,
      ),
      _HomeSection('Lịch sử', 'Lịch sử', Icons.history_outlined),
      _HomeSection(
        'Báo cáo thống kê',
        'Báo cáo thống kê',
        Icons.assessment_outlined,
      ),
      _HomeSection('Lương', 'Bảng lương', Icons.payments_outlined),
      _HomeSection(
        'NFC tại quầy',
        'Chấm công NFC tại quầy',
        Icons.contactless_outlined,
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
      _HomeSection('Tổng quan', 'Tổng quan', Icons.dashboard_outlined),
      _HomeSection('Chấm công', 'Chấm công', Icons.fact_check_outlined),
      _HomeSection('Lịch sử', 'Lịch sử chấm công', Icons.history_outlined),
      _HomeSection('Giờ làm', 'Giờ làm', Icons.schedule_outlined),
      _HomeSection('Lương của tôi', 'Lương của tôi', Icons.payments_outlined),
      _HomeSection(
        'Báo cáo của tôi',
        'Báo cáo của tôi',
        Icons.assessment_outlined,
      ),
    ],
  );
}

class _HomeSection {
  const _HomeSection(this.navigationLabel, this.title, this.icon);

  final String navigationLabel;
  final String title;
  final IconData icon;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Attendance'),
        actions: [
          if (wide)
            TextButton.icon(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('Đăng xuất'),
            )
          else
            IconButton(
              onPressed: widget.onSignOut,
              tooltip: 'Đăng xuất',
              icon: const Icon(Icons.logout_outlined),
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
    final colors = theme.colorScheme;
    final section = widget.sections[_selectedIndex];

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card.filled(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: colors.primaryContainer,
                          foregroundColor: colors.onPrimaryContainer,
                          child: Icon(widget.roleIcon, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.profile.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.profile.role.label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(section.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                if (_selectedIndex == 0) ...[
                  Text(
                    'Chọn một mục để tiếp tục.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
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
      const gap = 12.0;
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
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _selectSection(index),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(widget.sections[index].icon, size: 30),
                        const SizedBox(height: 20),
                        Text(
                          widget.sections[index].title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.profile.role == UserRole.admin && index == 1
                              ? 'Xem danh sách tài khoản'
                              : widget.profile.role == UserRole.admin &&
                                    index == 5
                              ? 'Thiết lập vị trí chấm công'
                              : widget.profile.role == UserRole.admin &&
                                    index == 6
                              ? 'Đăng ký và thu hồi thẻ NFC'
                              : (widget.profile.role == UserRole.admin &&
                                        index == 7) ||
                                    (widget.profile.role == UserRole.manager &&
                                        index == 6)
                              ? 'Quét thẻ và xem trạng thái chấm công hôm nay'
                              : (widget.profile.role == UserRole.admin &&
                                        index == 8) ||
                                    (widget.profile.role == UserRole.manager &&
                                        index == 2)
                              ? 'Xem và điều chỉnh chấm công thủ công'
                              : (widget.profile.role == UserRole.admin &&
                                        index == 3) ||
                                    (widget.profile.role == UserRole.manager &&
                                        index == 5)
                              ? 'Xem giờ công và lương tạm tính'
                              : (widget.profile.role == UserRole.admin &&
                                        index == 2) ||
                                    (widget.profile.role == UserRole.manager &&
                                        index == 4)
                              ? 'Xem thống kê chấm công theo kỳ'
                              : widget.profile.role == UserRole.employee &&
                                    index == 1
                              ? 'Xem giờ hiện tại và chấm công'
                              : widget.profile.role == UserRole.employee &&
                                    index == 2
                              ? 'Xem các lần chấm công đã ghi nhận'
                              : widget.profile.role == UserRole.employee &&
                                    index == 5
                              ? 'Xem thống kê chấm công của bạn'
                              : 'Đang phát triển',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _buildComingSoon(_HomeSection section) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Icon(section.icon, size: 52, color: colors.primary),
            const SizedBox(height: 16),
            Text(
              section.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Đang phát triển', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
