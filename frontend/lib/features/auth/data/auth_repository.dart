import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/secure_storage/secure_storage.dart';
import '../../../core/security/device_info.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final SecureStorage _secureStorage = SecureStorage();

  AuthRepository(this._apiClient);

  /// Registers user using QR invite code
  Future<Map<String, dynamic>> register({
    required String username,
    required String password,
    required String inviteCode,
    required String displayName,
  }) async {
    // Generate keypair if not exists
    String? pubKey = await _secureStorage.getDevicePublicKey();
    if (pubKey == null) {
      final x25519 = X25519();
      final keyPair = await x25519.newKeyPair();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();
      final publicKeyBytes = publicKey.bytes;
      
      pubKey = base64.encode(publicKeyBytes);
      await _secureStorage.saveDeviceKeyPair(
        privateKey: base64.encode(privateKeyBytes),
        publicKey: pubKey,
      );
    }

    final fingerprint = await DeviceInfo.getFingerprint();
    final name = DeviceInfo.getDeviceName();
    final platform = DeviceInfo.getPlatform();

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      ApiEndpoints.register,
      data: {
        'username': username,
        'password': password,
        'invite_code': inviteCode,
        'display_name': displayName,
        'device_name': name,
        'device_fingerprint': fingerprint,
        'platform': platform,
        'public_key': pubKey,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final tokens = data['tokens'] as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>;
    final device = data['device'] as Map<String, dynamic>;

    await _secureStorage.saveTokens(
      accessToken: tokens['accessToken'] as String,
      refreshToken: tokens['refreshToken'] as String,
    );

    await _secureStorage.saveUserInfo(
      userId: user['id'] as String,
      username: user['username'] as String,
      deviceId: device['id'] as String,
    );

    return data;
  }

  /// Logs user in. Returns whether 2FA or device trust is required.
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    // Generate keypair if not exists
    String? pubKey = await _secureStorage.getDevicePublicKey();
    if (pubKey == null) {
      final x25519 = X25519();
      final keyPair = await x25519.newKeyPair();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();
      final publicKeyBytes = publicKey.bytes;
      
      pubKey = base64.encode(publicKeyBytes);
      await _secureStorage.saveDeviceKeyPair(
        privateKey: base64.encode(privateKeyBytes),
        publicKey: pubKey,
      );
    }

    final fingerprint = await DeviceInfo.getFingerprint();
    final name = DeviceInfo.getDeviceName();
    final platform = DeviceInfo.getPlatform();

    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        ApiEndpoints.login,
        data: {
          'username': username,
          'password': password,
          'device_name': name,
          'device_fingerprint': fingerprint,
          'platform': platform,
          'public_key': pubKey,
        },
      );

      final data = response.data as Map<String, dynamic>;
      
      if (data['requires2FA'] == true) {
        return LoginResult(
          status: LoginStatus.requires2FA,
          tempToken: data['tempToken'] as String,
        );
      }

      final tokens = data['tokens'] as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      final device = data['device'] as Map<String, dynamic>;

      await _secureStorage.saveTokens(
        accessToken: tokens['accessToken'] as String,
        refreshToken: tokens['refreshToken'] as String,
      );

      await _secureStorage.saveUserInfo(
        userId: user['id'] as String,
        username: user['username'] as String,
        deviceId: device['id'] as String,
      );

      return LoginResult(status: LoginStatus.success);
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        final errData = e.response?.data as Map<String, dynamic>?;
        if (errData != null && errData['error'] == 'Device Untrusted') {
          final device = errData['device'] as Map<String, dynamic>;
          return LoginResult(
            status: LoginStatus.requiresDeviceTrust,
            untrustedDeviceId: device['id'] as String,
          );
        }
      }
      rethrow;
    }
  }

  /// Verifies a 2FA OTP code during setup or login
  Future<void> verify2FA({required String code, String? tempToken}) async {
    final Map<String, String> headers = {};
    if (tempToken != null) {
      headers['Authorization'] = 'Bearer $tempToken';
    }

    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      ApiEndpoints.verify2FA,
      data: {'code': code},
      options: Options(headers: headers),
    );

    if (tempToken != null) {
      final data = response.data as Map<String, dynamic>;
      final tokens = data['tokens'] as Map<String, dynamic>;

      await _secureStorage.saveTokens(
        accessToken: tokens['accessToken'] as String,
        refreshToken: tokens['refreshToken'] as String,
      );
    }
  }

  /// Checks if an untrusted device has been approved
  Future<bool> checkDeviceTrustStatus(String untrustedDeviceId) async {
    // In CLI admin/trust setup, untrusted device polls device list or retries login
    // Let's retry login logic on the UI side or poll `/devices` endpoint if authorized.
    // If not authorized yet, we retry the login check.
    return false;
  }
}

enum LoginStatus { success, requires2FA, requiresDeviceTrust }

class LoginResult {
  final LoginStatus status;
  final String? tempToken;
  final String? untrustedDeviceId;

  LoginResult({
    required this.status,
    this.tempToken,
    this.untrustedDeviceId,
  });
}
