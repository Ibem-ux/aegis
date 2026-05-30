import 'package:flutter/foundation.dart';
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
    if (kIsWeb) return 'Web Browser Session';
    return _getNativeDeviceName();
  }

  /// Returns the platform enum matching the backend's device_platform type.
  static String getPlatform() {
    if (kIsWeb) return 'WEB'; // Accurately report WEB to backend
    return _getNativePlatform();
  }
}

// These helper functions are only called on non-web platforms,
// so the dart:io import won't be triggered on web.
String _getNativeDeviceName() {
  try {
    // Dynamic import to avoid web compilation errors
    // ignore: avoid_classes_with_only_static_members
    final io = _PlatformHelper.instance;
    if (io.isAndroid) {
      return 'Android Device (${io.localHostname})';
    } else if (io.isIOS) {
      return 'iOS Device (${io.localHostname})';
    } else {
      return 'Desktop Session (${io.localHostname})';
    }
  } catch (_) {
    return 'Unknown Device';
  }
}

String _getNativePlatform() {
  try {
    final io = _PlatformHelper.instance;
    if (io.isAndroid) return 'ANDROID';
    if (io.isIOS) return 'IOS';
  } catch (_) {}
  return 'DESKTOP';
}

/// Thin wrapper around dart:io Platform to avoid static analysis issues.
/// Only instantiated on native platforms.
class _PlatformHelper {
  static final _PlatformHelper instance = _PlatformHelper._();
  _PlatformHelper._();

  bool get isAndroid {
    try {
      return _platformCheck('android');
    } catch (_) {
      return false;
    }
  }

  bool get isIOS {
    try {
      return _platformCheck('ios');
    } catch (_) {
      return false;
    }
  }

  String get localHostname {
    try {
      // Use defaultTargetPlatform as a safe alternative
      return defaultTargetPlatform.name;
    } catch (_) {
      return 'unknown';
    }
  }

  bool _platformCheck(String platform) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return platform == 'android';
      case TargetPlatform.iOS:
        return platform == 'ios';
      default:
        return false;
    }
  }
}

