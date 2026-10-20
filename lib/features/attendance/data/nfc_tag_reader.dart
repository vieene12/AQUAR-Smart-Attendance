import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

abstract class NfcTagReader {
  Future<void> start({required void Function(Uint8List? uid) onTag});
  Future<void> stop();
}

class DeviceNfcTagReader implements NfcTagReader {
  DeviceNfcTagReader({this.manager});

  final NfcManager? manager;
  NfcManager get _deviceManager => manager ?? NfcManager.instance;

  @override
  Future<void> start({required void Function(Uint8List? uid) onTag}) =>
      _deviceManager.startSession(
        pollingOptions: NfcPollingOption.values.toSet(),
        onDiscovered: (tag) {
          final id = defaultTargetPlatform == TargetPlatform.android
              ? NfcTagAndroid.from(tag)?.id
              : null;
          onTag(id == null || id.isEmpty ? null : id);
        },
      );

  @override
  Future<void> stop() => _deviceManager.stopSession();
}

String? nfcUidHex(Uint8List? uid) {
  if (uid == null || uid.isEmpty) return null;
  return uid
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}
