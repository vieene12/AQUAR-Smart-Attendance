import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_attendance/firebase_options.dart';

class FirebaseBootstrap {
  const FirebaseBootstrap._();

  static const bool useEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
  );

  static Future<void> initialize() async {
    if (!useEmulators) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      return;
    }

    await _initializeEmulators();
  }

  static Future<void> initializeEmulatorTestBuild() async {
    if (!useEmulators) {
      throw StateError(
        'The emutest entrypoint requires USE_FIREBASE_EMULATORS=true.',
      );
    }
    await _initializeEmulators();
  }

  static Future<void> _initializeEmulators() async {
    const configuration = FirebaseEmulatorConfiguration.fromEnvironment();
    configuration.validate(isDebugMode: kDebugMode);

    final app = await Firebase.initializeApp(
      name: defaultFirebaseAppName,
      demoProjectId: configuration.projectId,
    );
    if (app.options.projectId != configuration.projectId) {
      throw StateError('Firebase demo project initialization failed.');
    }

    await FirebaseAuth.instance.useAuthEmulator(
      configuration.host,
      configuration.authPort,
      automaticHostMapping: false,
    );

    final firestore = FirebaseFirestore.instance;
    firestore.settings = const Settings(persistenceEnabled: false);
    firestore.useFirestoreEmulator(
      configuration.host,
      configuration.firestorePort,
      automaticHostMapping: false,
    );
  }
}

@immutable
class FirebaseEmulatorConfiguration {
  const FirebaseEmulatorConfiguration({
    required this.projectId,
    required this.host,
    required this.authPort,
    required this.firestorePort,
  });

  const FirebaseEmulatorConfiguration.fromEnvironment()
    : projectId = const String.fromEnvironment('FIREBASE_EMULATOR_PROJECT_ID'),
      host = const String.fromEnvironment('FIREBASE_EMULATOR_HOST'),
      authPort = const int.fromEnvironment(
        'FIREBASE_AUTH_EMULATOR_PORT',
        defaultValue: 9099,
      ),
      firestorePort = const int.fromEnvironment(
        'FIRESTORE_EMULATOR_PORT',
        defaultValue: 8081,
      );

  static const String requiredProjectId = 'demo-smart-attendance';
  static const String requiredAdbReverseHost = '127.0.0.1';

  final String projectId;
  final String host;
  final int authPort;
  final int firestorePort;

  void validate({required bool isDebugMode}) {
    if (!isDebugMode) {
      throw StateError('Firebase emulators are allowed only in debug builds.');
    }
    if (projectId != requiredProjectId || !projectId.startsWith('demo-')) {
      throw StateError('Firebase emulator project must be $requiredProjectId.');
    }
    if (host != requiredAdbReverseHost) {
      throw StateError(
        'A physical Android device must use $requiredAdbReverseHost with adb reverse.',
      );
    }
    if (authPort != 9099 || firestorePort != 8081) {
      throw StateError('Unexpected Firebase emulator ports.');
    }
  }
}
