class ApiEndpoints {
  // Can be configured to point to local IP or tailscale IP
  static const String baseUrl = 'http://10.0.2.2:3000/api'; // Android Emulator loopback
  static const String wsUrl = 'http://10.0.2.2:3000/chat';

  // Auth Endpoints
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';
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
