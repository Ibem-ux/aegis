import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyAccessToken = 'access_token';
  static const String _keyRefreshToken = 'refresh_token';
  static const String _keyDbKey = 'db_encryption_key';
  static const String _keyUserId = 'user_id';
  static const String _keyUsername = 'username';
  static const String _keyDeviceId = 'device_id';
  static const String _keyDevicePrivateKey = 'device_private_key';
  static const String _keyDevicePublicKey = 'device_public_key';

  // Save Token
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  // Get Access Token
  Future<String?> getAccessToken() async {
    return await _storage.read(key: _keyAccessToken);
  }

  // Get Refresh Token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  // Save User Info
  Future<void> saveUserInfo({required String userId, required String username, required String deviceId}) async {
    await _storage.write(key: _keyUserId, value: userId);
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyDeviceId, value: deviceId);
  }

  Future<String?> getUserId() async => await _storage.read(key: _keyUserId);
  Future<String?> getUsername() async => await _storage.read(key: _keyUsername);
  Future<String?> getDeviceId() async => await _storage.read(key: _keyDeviceId);
  Future<String?> getDevicePrivateKey() async => await _storage.read(key: _keyDevicePrivateKey);
  Future<String?> getDevicePublicKey() async => await _storage.read(key: _keyDevicePublicKey);

  Future<void> saveDeviceKeyPair({required String privateKey, required String publicKey}) async {
    await _storage.write(key: _keyDevicePrivateKey, value: privateKey);
    await _storage.write(key: _keyDevicePublicKey, value: publicKey);
  }

  // Clear Storage
  Future<void> clearAll() async {
    // Keep the db key and device encryption keys, clear everything else
    final dbKey = await getOrGenerateDbKey();
    final devicePrivKey = await getDevicePrivateKey();
    final devicePubKey = await getDevicePublicKey();
    await _storage.deleteAll();
    await _storage.write(key: _keyDbKey, value: dbKey);
    if (devicePrivKey != null) {
      await _storage.write(key: _keyDevicePrivateKey, value: devicePrivKey);
    }
    if (devicePubKey != null) {
      await _storage.write(key: _keyDevicePublicKey, value: devicePubKey);
    }
  }

  // Get or Generate a 256-bit (32 byte) key for Drift SQLite database
  Future<String> getOrGenerateDbKey() async {
    String? key = await _storage.read(key: _keyDbKey);
    if (key == null) {
      final random = Random.secure();
      final bytes = List<int>.generate(32, (i) => random.nextInt(256));
      key = base64Url.encode(bytes);
      await _storage.write(key: _keyDbKey, value: key);
    }
    return key;
  }
}
