import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_repository.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';
import 'package:smart_attendance/features/admin/accounts/presentation/add_account_screen.dart';
import 'package:smart_attendance/features/admin/accounts/presentation/edit_account_screen.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/attendance/data/team_attendance_repository.dart';
import 'package:smart_attendance/features/attendance/presentation/team_attendance_history_screen.dart';

enum _RoleFilter { all, manager, employee, admin }

enum _StatusFilter { all, active, locked }

class AccountListScreen extends StatefulWidget {
  const AccountListScreen({
    required this.profile,
    this.teamAttendanceRepository,
    super.key,
  });

  final UserProfile profile;
  final TeamAttendanceRepository? teamAttendanceRepository;

  @override
  State<AccountListScreen> createState() => _AccountListScreenState();
}

class _AccountListScreenState extends State<AccountListScreen> {
  final _repository = AccountRepository();
  final _searchController = TextEditingController();
  Future<List<AccountRecord>>? _accounts;
  String? _changingStatusUid;
  String _searchQuery = '';
  _RoleFilter _roleFilter = _RoleFilter.all;
  _StatusFilter _statusFilter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.profile.role == UserRole.admin) {
      _accounts = _repository.getAccounts();
    }
  }

  void _retry() {
    setState(() => _accounts = _repository.getAccounts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AccountRecord> _filterAccounts(List<AccountRecord> accounts) {
    return accounts.where((account) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          (account.name?.toLowerCase().contains(_searchQuery) ?? false) ||
          (account.email?.toLowerCase().contains(_searchQuery) ?? false);
      final matchesRole =
          _roleFilter == _RoleFilter.all || account.role == _roleFilter.name;
      final matchesStatus =
          _statusFilter == _StatusFilter.all ||
          account.status == _statusFilter.name;
      return matchesSearch && matchesRole && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý nhân viên'),
        actions: [
          IconButton(
            tooltip: 'Lịch sử chấm công',
            icon: const Icon(Icons.history_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Lịch sử chấm công')),
                  body: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: TeamAttendanceHistoryScreen(
                        profile: widget.profile,
                        repository: widget.teamAttendanceRepository,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: widget.profile.role == UserRole.admin
          ? FloatingActionButton.extended(
              onPressed: _openAddAccount,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Thêm tài khoản'),
            )
          : null,
      body: SafeArea(
        child: widget.profile.role != UserRole.admin
            ? const Center(child: Text('Bạn không có quyền xem danh sách này.'))
            : FutureBuilder<List<AccountRecord>>(
                future: _accounts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.wifi_off_outlined,
                      message: _errorMessage(snapshot.error),
                      onRetry: _retry,
                    );
                  }

                  final accounts = snapshot.data ?? const <AccountRecord>[];
                  final filteredAccounts = _filterAccounts(accounts);

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(child: _buildFilters()),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Text(
                                '${filteredAccounts.length} kết quả',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ),
                          if (filteredAccounts.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _MessageState(
                                icon: accounts.isEmpty
                                    ? Icons.groups_outlined
                                    : Icons.search_off_outlined,
                                message: accounts.isEmpty
                                    ? 'Chưa có tài khoản nào trong danh sách.'
                                    : 'Không tìm thấy tài khoản phù hợp.',
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              sliver: SliverList.builder(
                                itemCount: filteredAccounts.length,
                                itemBuilder: (context, index) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _buildAccountCard(
                                    filteredAccounts[index],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildAccountCard(AccountRecord account) {
    final canEdit = account.role == 'manager' || account.role == 'employee';
    final canChangeStatus =
        canEdit &&
        account.uid != widget.profile.uid &&
        (account.status == 'active' || account.status == 'locked');
    return _AccountCard(
      account: account,
      onTap: canEdit && _changingStatusUid == null
          ? () => _openEditAccount(account)
          : null,
      onStatusPressed: canChangeStatus && _changingStatusUid == null
          ? () => _changeStatus(account)
          : null,
      showStatusAction: canChangeStatus,
      statusLoading: _changingStatusUid == account.uid,
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final filterWidth = constraints.maxWidth < 560
              ? constraints.maxWidth
              : (constraints.maxWidth - 12) / 2;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                onChanged: (value) =>
                    setState(() => _searchQuery = value.trim().toLowerCase()),
                decoration: InputDecoration(
                  labelText: 'Tìm theo họ tên hoặc email',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Xóa tìm kiếm',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: filterWidth,
                    child: DropdownButtonFormField<_RoleFilter>(
                      initialValue: _roleFilter,
                      decoration: const InputDecoration(
                        labelText: 'Vai trò',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _RoleFilter.all,
                          child: Text('Tất cả'),
                        ),
                        DropdownMenuItem(
                          value: _RoleFilter.manager,
                          child: Text('Quản lý'),
                        ),
                        DropdownMenuItem(
                          value: _RoleFilter.employee,
                          child: Text('Nhân viên'),
                        ),
                        DropdownMenuItem(
                          value: _RoleFilter.admin,
                          child: Text('Admin'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _roleFilter = value);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: filterWidth,
                    child: DropdownButtonFormField<_StatusFilter>(
                      initialValue: _statusFilter,
                      decoration: const InputDecoration(
                        labelText: 'Trạng thái',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _StatusFilter.all,
                          child: Text('Tất cả'),
                        ),
                        DropdownMenuItem(
                          value: _StatusFilter.active,
                          child: Text('Hoạt động'),
                        ),
                        DropdownMenuItem(
                          value: _StatusFilter.locked,
                          child: Text('Đã khóa'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _statusFilter = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openAddAccount() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddAccountScreen()));
    if (!mounted || created != true) return;

    _retry();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã tạo tài khoản thành công.')),
    );
  }

  Future<void> _openEditAccount(AccountRecord account) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditAccountScreen(account: account)),
    );
    if (!mounted || updated != true) return;

    _retry();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã cập nhật tài khoản thành công.')),
    );
  }

  Future<void> _changeStatus(AccountRecord account) async {
    if (_changingStatusUid != null) return;
    final locking = account.status == 'active';
    if (!locking && account.status != 'locked') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(locking ? 'Khóa tài khoản?' : 'Mở khóa tài khoản?'),
        content: Text(
          locking
              ? 'Khóa ${account.name ?? account.email ?? 'tài khoản này'}? Người dùng sẽ bị chặn truy cập ứng dụng khi phiên được xác minh lại.'
              : 'Mở khóa ${account.name ?? account.email ?? 'tài khoản này'}? Người dùng có thể đăng nhập lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(locking ? 'Khóa' : 'Mở khóa'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _changingStatusUid != null) return;

    setState(() => _changingStatusUid = account.uid);
    try {
      await _repository.setAccountLocked(uid: account.uid, locked: locking);
      if (!mounted) return;
      _retry();
      _showMessage(locking ? 'Đã khóa tài khoản.' : 'Đã mở khóa tài khoản.');
    } on FirebaseException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'permission-denied' => 'Không có quyền đổi trạng thái. Hãy kiểm tra quyền Admin và Security Rules.',
        'not-found' => 'Tài khoản không còn tồn tại trong Firestore.',
        'unavailable' ||
        'deadline-exceeded' => 'Không thể kết nối Firestore. Vui lòng thử lại.',
        _ => 'Không thể đổi trạng thái tài khoản. Vui lòng thử lại.',
      };
      _showMessage(message);
    } catch (_) {
      if (mounted) {
        _showMessage('Không thể đổi trạng thái tài khoản. Vui lòng thử lại.');
      }
    } finally {
      if (mounted) setState(() => _changingStatusUid = null);
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorMessage(Object? error) {
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'Không có quyền xem danh sách tài khoản. Vui lòng kiểm tra Security Rules.',
        'unavailable' || 'network-request-failed' || 'deadline-exceeded' =>
          'Không thể kết nối Firestore. Vui lòng kiểm tra mạng và thử lại.',
        _ => 'Không thể tải danh sách tài khoản. Vui lòng thử lại.',
      };
    }
    return 'Không thể tải danh sách tài khoản. Vui lòng thử lại.';
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.showStatusAction,
    required this.statusLoading,
    this.onTap,
    this.onStatusPressed,
  });

  final AccountRecord account;
  final VoidCallback? onTap;
  final VoidCallback? onStatusPressed;
  final bool showStatusAction;
  final bool statusLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = switch (account.status) {
      'active' => colors.primaryContainer,
      'locked' => colors.errorContainer,
      _ => colors.surfaceContainerHighest,
    };
    final statusTextColor = switch (account.status) {
      'active' => colors.onPrimaryContainer,
      'locked' => colors.onErrorContainer,
      _ => colors.onSurfaceVariant,
    };

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.person_outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name ?? 'Chưa cập nhật họ tên',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      account.email ?? 'Chưa cập nhật email',
                      softWrap: true,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.verified_user_outlined),
                          label: Text(account.role ?? 'Vai trò chưa xác định'),
                        ),
                        Chip(
                          backgroundColor: statusColor,
                          label: Text(
                            account.status ?? 'Trạng thái chưa xác định',
                            style: TextStyle(color: statusTextColor),
                          ),
                        ),
                      ],
                    ),
                    if (showStatusAction) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: onStatusPressed,
                        icon: statusLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                account.status == 'active'
                                    ? Icons.lock_outline
                                    : Icons.lock_open_outlined,
                              ),
                        label: Text(
                          statusLoading
                              ? 'Đang cập nhật...'
                              : account.status == 'active'
                              ? 'Khóa'
                              : 'Mở khóa',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
