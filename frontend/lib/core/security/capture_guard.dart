import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class CaptureGuard {
  static const MethodChannel _methodChannel = MethodChannel('com.ibemcom.aegis_chat/capture_guard');
  static const EventChannel _eventChannel = EventChannel('com.ibemcom.aegis_chat/capture_events');

  CaptureGuard._();
  static final CaptureGuard instance = CaptureGuard._();

  Stream<String>? _events;

  Stream<String> get events {
    _events ??= _eventChannel.receiveBroadcastStream().map((event) => event.toString());
    return _events!;
  }

  Future<void> enableSecureMode() async {
    try {
      await _methodChannel.invokeMethod('enableSecureMode');
    } catch (e) {
      debugPrint('Failed to enable secure mode: $e');
    }
  }

  Future<void> disableSecureMode() async {
    try {
      await _methodChannel.invokeMethod('disableSecureMode');
    } catch (e) {
      debugPrint('Failed to disable secure mode: $e');
    }
  }

  Future<bool> isBeingCaptured() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isBeingCaptured');
      return result ?? false;
    } catch (e) {
      debugPrint('Failed to check capture status: $e');
      return false;
    }
  }
}
