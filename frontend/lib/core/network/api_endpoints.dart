import 'package:flutter/foundation.dart';

class ApiEndpoints {
  /// Production API URL override via --dart-define=API_URL=https://your-api.onrender.com
  /// Falls back to localhost for development.
  static const String _apiUrlOverride = String.fromEnvironment('API_URL');
  static const String _wsUrlOverride = String.fromEnvironment('WS_URL');

  /// Resolves the correct backend host for each platform:
  /// - If API_URL is set via --dart-define, uses that directly
  /// - Android Emulator uses 10.0.2.2 (special loopback alias)
  /// - All other platforms (Windows, iOS, macOS, Linux, Web) use localhost
  static String get host {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return '10.0.2.2:3000';
    }
    return 'localhost:3000';
  }

  static String get baseUrl {
    if (_apiUrlOverride.isNotEmpty) {
      // Production: use the full URL from --dart-define (e.g. https://aegis-api.onrender.com/api)
      final url = _apiUrlOverride.endsWith('/api') ? _apiUrlOverride : '$_apiUrlOverride/api';
      return url;
    }
    return 'http://$host/api';
  }

  static String get wsUrl {
    if (_wsUrlOverride.isNotEmpty) {
      return _wsUrlOverride;
    }
    if (_apiUrlOverride.isNotEmpty) {
      // Derive WS URL from API URL (strip /api suffix if present)
      return _apiUrlOverride.replaceAll(RegExp(r'/api$'), '');
    }
    return 'http://$host';
  }

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
  static const String passwordChange = '/users/password/change';
  static const String recoveryGenerate = '/users/recovery/generate';
  static const String recoveryRecover = '/users/recovery/recover';
  static const String sessions = '/users/sessions';

  // Chats & Messages
  static const String chats = '/chats';
  static const String chatInvites = '/chats/invites';
  static const String acceptInvite = '/chats/invites/accept';

  // Media
  static const String mediaUpload = '/media/upload';
  static const String mediaDownload = '/media/download';
}
