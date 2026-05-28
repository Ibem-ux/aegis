import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceInfo {
  static const String _keyFingerprint = 'device_fingerprint';

  /// Returns a unique persistent fingerprint for this device.
  /// If it doesn't exist, it generates a new UUID and stores it.
  static Future<String> getFingerprint() async {
    final prefs = await SharedPreferences.getInstance();
    String? fingerprint = prefs.getString(_keyFingerprint);
    
    if (fingerprint == null) {
      fingerprint = const Uuid().v4();
      await prefs.setString(_keyFingerprint, fingerprint);
    }
    return fingerprint;
  }

  /// Returns the human-readable device name.
  static String getDeviceName() {
    if (Platform.isAndroid) {
      return 'Android Device (${Platform.localHostname})';
    } else if (Platform.isIOS) {
      return 'iOS Device (${Platform.localHostname})';
    } else {
      return 'Desktop Session (${Platform.localHostname})';
    }
  }

  /// Returns the platform enum matching the backend's device_platform type.
  static String getPlatform() {
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isIOS) return 'IOS';
    return 'DESKTOP';
  }
}
