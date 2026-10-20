import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';
import 'package:smart_attendance/features/admin/nfc_cards/data/nfc_card_repository.dart';
import 'package:smart_attendance/features/admin/nfc_cards/presentation/nfc_card_screen.dart';
import 'package:smart_attendance/features/attendance/data/nfc_availability_checker.dart';
import 'package:smart_attendance/features/attendance/data/nfc_tag_reader.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/home/presentation/role_home_screens.dart';

const _admin = UserProfile(
  uid: 'admin-1',
  displayName: 'Admin',
  role: UserRole.admin,
);

void main() {
  test(
    'đăng ký, chặn trùng, thay thế và thu hồi dùng một transaction mỗi lần',
    () async {
      final store = _FakeNfcCardStore();
      final repository = NfcCardRepository(store);
      await repository.register('employee-1', ' 04aB01 ');
      expect(store.cards['04AB01'], 'employee-1');
      expect(store.links['employee-1'], '04AB01');
      expect(store.transactions, 1);

      await expectLater(
        repository.register('employee-2', '04ab01'),
        throwsA(isA<NfcCardConflict>()),
      );
      expect(store.links['employee-2'], isNull);

      await repository.register('employee-1', 'AABB');
      expect(store.cards['04AB01'], isNull);
      expect(store.cards['AABB'], 'employee-1');
      expect(store.links['employee-1'], 'AABB');

      await repository.revoke('employee-1');
      expect(store.cards, isEmpty);
      expect(store.links, isEmpty);
      await repository.register('employee-2', 'AABB');
      expect(store.cards['AABB'], 'employee-2');
    },
  );

  test('không đăng ký cho tài khoản khóa hoặc UID sai', () async {
    final store = _FakeNfcCardStore();
    store.users['employee-1'] = _employee('employee-1', status: 'locked');
    final repository = NfcCardRepository(store);
    await expectLater(
      repository.register('employee-1', 'AABB'),
      throwsA(isA<NfcEmployeeUnavailable>()),
    );
    await expectLater(
      repository.register('employee-2', 'AAB'),
      throwsFormatException,
    );
    expect(store.cards, isEmpty);
  });

  testWidgets(
    'Admin quét thẻ, xem trạng thái, thu hồi và đăng ký thẻ thay thế',
    (tester) async {
      final store = _FakeNfcCardStore();
      final reader = _FakeNfcReader();
      await _pumpScreen(tester, store, reader);
      expect(find.textContaining('Chưa đăng ký thẻ'), findsNWidgets(2));
      await tester.tap(find.text('Nhân viên 1'));
      await tester.pump();
      await tester.tap(find.text('Đăng ký thẻ'));
      await tester.pump();
      expect(find.textContaining('Đưa thẻ đến mặt lưng'), findsOneWidget);
      reader.discover([0x04, 0xAB, 0x01]);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(store.links['employee-1'], '04AB01');
      expect(reader.stops, 1);
      expect(find.textContaining('Đã đăng ký thẻ: 04AB01'), findsOneWidget);

      await tester.tap(find.text('Đăng ký thẻ thay thế'));
      await tester.pump();
      reader.discover([0xAA, 0xBB]);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(store.links['employee-1'], 'AABB');
      expect(store.cards['04AB01'], isNull);

      await tester.tap(find.text('Thu hồi thẻ'));
      await tester.pump();
      await tester.tap(find.text('Thu hồi'));
      await tester.pump();
      await tester.pump();
      expect(store.links['employee-1'], isNull);
      expect(store.cards, isEmpty);
    },
  );

  testWidgets('thiết bị không hỗ trợ NFC vẫn hiện danh sách và tắt nút quét', (
    tester,
  ) async {
    final store = _FakeNfcCardStore();
    await _pumpScreen(
      tester,
      store,
      _FakeNfcReader(),
      NfcAvailability.unsupported,
    );
    expect(find.textContaining('Thiết bị không hỗ trợ NFC'), findsOneWidget);
    expect(find.text('Nhân viên 1'), findsOneWidget);
    await tester.tap(find.text('Nhân viên 1'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Đăng ký thẻ'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Manager không thể mở màn hình chỉnh thẻ', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NfcCardScreen(
          profile: UserProfile(
            uid: 'manager',
            displayName: 'Manager',
            role: UserRole.manager,
          ),
        ),
      ),
    );
    expect(find.text('Bạn không có quyền quản lý thẻ NFC.'), findsOneWidget);
  });

  testWidgets('Admin có mục Quản lý thẻ NFC trên trang chủ', (tester) async {
    final store = _FakeNfcCardStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminHomeScreen(
          profile: _admin,
          onSignOut: () {},
          nfcCardRepository: NfcCardRepository(store),
          nfcChecker: _FakeNfcChecker(NfcAvailability.enabled),
          nfcReader: _FakeNfcReader(),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Đăng ký và thu hồi thẻ NFC'));
    await tester.tap(find.text('Đăng ký và thu hồi thẻ NFC'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(NfcCardScreen), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeNfcCardStore store,
  _FakeNfcReader reader, [
  NfcAvailability availability = NfcAvailability.enabled,
]) async {
  await tester.pumpWidget(
    MaterialApp(
      home: NfcCardScreen(
        profile: _admin,
        repository: NfcCardRepository(store),
        checker: _FakeNfcChecker(availability),
        reader: reader,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

AccountRecord _employee(String uid, {String status = 'active'}) =>
    AccountRecord(
      uid: uid,
      name: uid == 'employee-1' ? 'Nhân viên 1' : 'Nhân viên 2',
      email: '$uid@example.com',
      role: 'employee',
      status: status,
      hourlyRate: 0,
    );

class _FakeNfcCardStore implements NfcCardStore {
  final users = {
    'employee-1': _employee('employee-1'),
    'employee-2': _employee('employee-2'),
  };
  Map<String, String> cards = {};
  Map<String, String> links = {};
  int transactions = 0;

  @override
  Future<List<EmployeeNfcCard>> loadEmployees() async => [
    for (final account in users.values)
      EmployeeNfcCard(account: account, cardUid: links[account.uid]),
  ];

  @override
  Future<void> transact(
    Future<void> Function(NfcCardTransaction tx) action,
  ) async {
    transactions++;
    final nextCards = Map<String, String>.of(cards);
    final nextLinks = Map<String, String>.of(links);
    await action(_FakeTransaction(users, nextCards, nextLinks));
    cards = nextCards;
    links = nextLinks;
  }
}

class _FakeTransaction implements NfcCardTransaction {
  _FakeTransaction(this.users, this.cards, this.links);
  final Map<String, AccountRecord> users;
  final Map<String, String> cards;
  final Map<String, String> links;

  @override
  Future<AccountRecord?> employee(String employeeUid) async =>
      users[employeeUid];
  @override
  Future<String?> employeeCard(String employeeUid) async => links[employeeUid];
  @override
  Future<String?> cardOwner(String cardUid) async => cards[cardUid];
  @override
  void putCard(String cardUid, String employeeUid) =>
      cards[cardUid] = employeeUid;
  @override
  void deleteCard(String cardUid) => cards.remove(cardUid);
  @override
  void putEmployeeCard(String employeeUid, String cardUid) =>
      links[employeeUid] = cardUid;
  @override
  void deleteEmployeeCard(String employeeUid) => links.remove(employeeUid);
}

class _FakeNfcChecker implements NfcAvailabilityChecker {
  _FakeNfcChecker(this.availability);
  final NfcAvailability availability;
  @override
  Future<NfcAvailability> checkAvailability() async => availability;
}

class _FakeNfcReader implements NfcTagReader {
  void Function(Uint8List? uid)? onTag;
  int stops = 0;
  @override
  Future<void> start({required void Function(Uint8List? uid) onTag}) async {
    this.onTag = onTag;
  }

  void discover(List<int> uid) => onTag!(Uint8List.fromList(uid));

  @override
  Future<void> stop() async {
    stops++;
    onTag = null;
  }
}
