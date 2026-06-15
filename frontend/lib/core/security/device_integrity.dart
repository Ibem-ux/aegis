import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';

class DeviceIntegrity {
  DeviceIntegrity._();
  static final DeviceIntegrity instance = DeviceIntegrity._();

  bool? _isCompromised;

  Future<bool> isCompromised() async {
    if (_isCompromised != null) {
      return _isCompromised!;
    }
    
    try {
      final isJailbroken = await FlutterJailbreakDetection.jailbroken;
      final isDeveloperMode = await FlutterJailbreakDetection.developerMode;
      _isCompromised = isJailbroken || isDeveloperMode;
    } catch (e) {
      debugPrint('Error checking device integrity: $e');
      _isCompromised = false; // fail-safe to false
    }
    
    return _isCompromised!;
  }

  Future<bool> shouldRestrictMedia() async {
    return await isCompromised();
  }
}
