import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'emutest có package riêng và không xử lý Google Services production',
    () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();

      expect(
        gradle,
        contains('applicationId = "com.example.smart_attendance"'),
      );
      expect(gradle, contains('create("production")'));
      expect(gradle, contains('create("emutest")'));
      expect(gradle, contains('applicationIdSuffix = ".emutest"'));
      expect(gradle, contains('processEmutest'));
      expect(gradle, contains('enabled = false'));
      expect(gradle, contains('lib/main_emutest.dart'));
    expect(gradle, contains('withFlavor("environment" to "emutest")'));
    expect(gradle, contains('it.buildType != "debug"'));
    },
  );

  test('google-services.json vẫn chỉ thuộc production package', () {
    final json = jsonDecode(
      File('android/app/google-services.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final clients = json['client'] as List<dynamic>;
    final packageNames = clients
        .cast<Map<String, dynamic>>()
        .map(
          (client) =>
              ((client['client_info']
                          as Map<String, dynamic>)['android_client_info']
                      as Map<String, dynamic>)['package_name']
                  as String,
        )
        .toSet();

    expect(packageNames, contains('com.example.smart_attendance'));
    expect(
      packageNames,
      isNot(contains('com.example.smart_attendance.emutest')),
    );
  });

  test('entrypoint emutest chỉ gọi bootstrap Emulator bắt buộc', () {
    final entrypoint = File('lib/main_emutest.dart').readAsStringSync();

    expect(entrypoint, contains('initializeEmulatorTestBuild()'));
    expect(entrypoint, isNot(contains('DefaultFirebaseOptions')));
  });
}
