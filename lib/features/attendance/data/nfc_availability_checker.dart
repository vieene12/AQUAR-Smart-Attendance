import 'package:nfc_manager/nfc_manager.dart';

abstract class NfcAvailabilityChecker {
  Future<NfcAvailability> checkAvailability();
}

class DeviceNfcAvailabilityChecker implements NfcAvailabilityChecker {
  @override
  Future<NfcAvailability> checkAvailability() =>
      NfcManager.instance.checkAvailability();
}
