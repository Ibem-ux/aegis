import 'package:flutter/foundation.dart';

class ApiEndpoints {
  /// Resolves the correct backend host for each platform:
  /// - Android Emulator uses 10.0.2.2 (special loopback alias)
  /// - All other platforms (Windows, iOS, macOS, Linux, Web) use localhost
  static String get host {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2:3000';
    }
    return 'localhost:3000';
  }

  static String get baseUrl => 'http://$host/api';
  static String get wsUrl => 'http://$host/chat';

  // Auth Endpoints
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
  static const String sendOtp = '/auth/otp/send';
  static const String verifyOtp = '/auth/otp/verify';
  static const String setup2FA = '/auth/2fa/setup';
  static const String verify2FA = '/auth/2fa/verify';

  // Devices
  static const String devices = '/devices';
  static const String approveDevice = '/devices/approve';
  static const String removeDevice = '/devices'; // DELETE /devices/:id

  // Users
  static const String searchUsers = '/users/search';
  static const String me = '/users/me';

  // Chats & Messages
  static const String chats = '/chats';
  static const String messages = '/messages';

  // Media
  static const String mediaUpload = '/media/upload';
  static const String mediaDownload = '/media/download';
}
