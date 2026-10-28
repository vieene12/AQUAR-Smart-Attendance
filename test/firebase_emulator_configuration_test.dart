import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/core/firebase/firebase_bootstrap.dart';

void main() {
  const valid = FirebaseEmulatorConfiguration(
    projectId: 'demo-smart-attendance',
    host: '127.0.0.1',
    authPort: 9099,
    firestorePort: 8081,
  );

  test('chấp nhận cấu hình điện thoại thật qua adb reverse', () {
    expect(() => valid.validate(isDebugMode: true), returnsNormally);
  });

  test('từ chối bật emulator trong release build', () {
    expect(
      () => valid.validate(isDebugMode: false),
      throwsA(isA<StateError>()),
    );
  });

  test('từ chối Firebase production project', () {
    const configuration = FirebaseEmulatorConfiguration(
      projectId: 'smart-attendance-32d6b',
      host: '127.0.0.1',
      authPort: 9099,
      firestorePort: 8081,
    );

    expect(
      () => configuration.validate(isDebugMode: true),
      throwsA(isA<StateError>()),
    );
  });

  test('từ chối host không đi qua adb reverse', () {
    const configuration = FirebaseEmulatorConfiguration(
      projectId: 'demo-smart-attendance',
      host: '10.0.2.2',
      authPort: 9099,
      firestorePort: 8081,
    );

    expect(
      () => configuration.validate(isDebugMode: true),
      throwsA(isA<StateError>()),
    );
  });
}
