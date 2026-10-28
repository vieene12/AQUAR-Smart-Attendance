import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_api_client.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_creation_repository.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_repository.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';
import 'package:smart_attendance/features/admin/accounts/presentation/account_list_screen.dart';
import 'package:smart_attendance/features/admin/accounts/presentation/add_account_screen.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';

const _adminProfile = UserProfile(
  uid: 'admin-1',
  displayName: 'Admin',
  role: UserRole.admin,
);

void main() {
  testWidgets('danh sách giữ Admin chỉ đọc và giữ bộ lọc Admin', (
    tester,
  ) async {
    final repository = _FakeAccountRepository([
      const AccountRecord(
        uid: 'admin-1',
        name: 'Quản trị viên',
        email: null,
        role: 'admin',
        status: 'active',
        hourlyRate: null,
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: AccountListScreen(profile: _adminProfile, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quản trị viên'), findsOneWidget);
    await tester.tap(find.text('Tất cả').first);
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsWidgets);
    await tester.tap(find.text('Tất cả').last);
    await tester.pumpAndSettle();
    expect(find.text('Khóa'), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('POST conflict hiển thị thông báo email đã dùng', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AddAccountScreen(repository: _FailingCreationRepository()),
      ),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Nguyễn Văn A');
    await tester.enterText(fields.at(1), 'a@example.com');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.tap(find.byType(DropdownButtonFormField<UserRole>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhân viên').last);
    await tester.enterText(fields.at(3), '50000');
    await tester.ensureVisible(find.text('Lưu'));
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(
      find.text('Email đã được sử dụng hoặc tài khoản đã tồn tại.'),
      findsOneWidget,
    );
  });

  testWidgets('Thử lại tải danh sách sau lỗi mạng', (tester) async {
    final repository = _RetryAccountRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: AccountListScreen(profile: _adminProfile, repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Không thể kết nối Backend API. Vui lòng kiểm tra mạng và thử lại.',
      ),
      findsOneWidget,
    );
    expect(find.text('Thử lại'), findsOneWidget);

    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(find.text('Nhân viên Retry'), findsOneWidget);
  });
}

class _FakeAccountRepository implements AccountRepositoryContract {
  _FakeAccountRepository(this.accounts);

  final List<AccountRecord> accounts;

  @override
  Future<List<AccountRecord>> getAccounts() async => accounts;

  @override
  Future<void> setAccountLocked({
    required String uid,
    required bool locked,
  }) async {}

  @override
  Future<void> updateAccount({
    required String uid,
    required String fullName,
    required int hourlyRate,
  }) async {}
}

class _FailingCreationRepository implements AccountCreationRepositoryContract {
  @override
  Future<String> createAccount({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required int hourlyRate,
  }) {
    throw const AccountApiException(AccountApiFailure.conflict);
  }
}

class _RetryAccountRepository implements AccountRepositoryContract {
  int calls = 0;

  @override
  Future<List<AccountRecord>> getAccounts() async {
    calls++;
    if (calls == 1) {
      throw const AccountApiException(AccountApiFailure.network);
    }
    return const [
      AccountRecord(
        uid: 'employee-retry',
        name: 'Nhân viên Retry',
        email: 'retry@example.test',
        role: 'employee',
        status: 'active',
        hourlyRate: 50000,
      ),
    ];
  }

  @override
  Future<void> setAccountLocked({
    required String uid,
    required bool locked,
  }) async {}

  @override
  Future<void> updateAccount({
    required String uid,
    required String fullName,
    required int hourlyRate,
  }) async {}
}
