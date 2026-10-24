import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/core/nfc/nfc_uid.dart';
import 'package:smart_attendance/features/attendance/data/attendance_repository.dart';

void main() {
  test('UID quét và UID Admin nhập có cùng dạng chuẩn', () {
    expect(normalizeCardUid(' 04:aa-bb:cc:dd '), '04AABBCCDD');
    expect(normalizeCardUid('04AABBCCDD'), '04AABBCCDD');
    expect(() => normalizeCardUid('04XX'), throwsFormatException);
  });

  test('thẻ đã gán cho đúng tài khoản được chấp nhận', () {
    expect(
      () => validateEmployeeNfcCard(
        employeeId: 'employee-a',
        cardUid: '04AABBCCDD',
        assignedUid: '04AABBCCDD',
        cardData: {'employeeUid': 'employee-a'},
      ),
      returnsNormally,
    );
  });

  test('thẻ của Employee B không chấm công cho Employee A', () {
    expect(
      () => validateEmployeeNfcCard(
        employeeId: 'employee-a',
        cardUid: '0411223344',
        assignedUid: '04AABBCCDD',
        cardData: {'employeeUid': 'employee-b'},
      ),
      throwsA(isA<AttendanceNfcCardNotOwnedException>()),
    );
  });

  test('thẻ chưa đăng ký và tài khoản chưa có thẻ có lỗi riêng', () {
    expect(
      () => validateEmployeeNfcCard(
        employeeId: 'employee-a',
        cardUid: '0411223344',
        assignedUid: '04AABBCCDD',
        cardData: null,
      ),
      throwsA(isA<AttendanceNfcCardUnregisteredException>()),
    );
    expect(
      () => validateEmployeeNfcCard(
        employeeId: 'employee-a',
        cardUid: '0411223344',
        assignedUid: null,
        cardData: {'employeeUid': 'employee-b'},
      ),
      throwsA(isA<AttendanceNfcNotAssignedException>()),
    );
  });
}
