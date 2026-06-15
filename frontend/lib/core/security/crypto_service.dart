import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

class CryptoService {
  static final _cipher = AesGcm.with256bits();

  /// Encrypts raw file bytes using AES-256-GCM.
  /// Returns a map containing:
  /// - 'encryptedBytes': Combined ciphertext + auth tag (ready to upload)
  /// - 'key': Base64Url-encoded 256-bit AES key
  /// - 'iv': Base64Url-encoded 96-bit (12-byte) initialization vector (IV)
  static Future<Map<String, dynamic>> encryptFile(Uint8List fileBytes) async {
    // 1. Generate key and IV
    final secretKey = await _cipher.newSecretKey();
    final secretKeyBytes = await secretKey.extractBytes();
    
    // Generate random 12-byte IV (nonce)
    final random = Random.secure();
    final ivBytes = Uint8List.fromList(List<int>.generate(12, (_) => random.nextInt(256)));

    // 2. Encrypt
    final secretBox = await _cipher.encrypt(
      fileBytes,
      secretKey: secretKey,
      nonce: ivBytes,
    );

    // 3. Combine ciphertext and MAC (Auth Tag)
    final ciphertext = secretBox.cipherText;
    final macBytes = secretBox.mac.bytes;
    
    final combinedBytes = Uint8List(ciphertext.length + macBytes.length);
    combinedBytes.setRange(0, ciphertext.length, ciphertext);
    combinedBytes.setRange(ciphertext.length, combinedBytes.length, macBytes);

    return {
      'encryptedBytes': combinedBytes,
      'key': base64Url.encode(secretKeyBytes),
      'iv': base64Url.encode(ivBytes),
    };
  }

  /// Decrypts media file bytes using AES-256-GCM.
  /// Expects:
  /// - [encryptedBytes]: The combined ciphertext + tag downloaded from MinIO.
  /// - [keyBase64]: Base64Url-encoded AES key.
  /// - [ivBase64]: Base64Url-encoded IV.
  static Future<Uint8List> decryptFile({
    required Uint8List encryptedBytes,
    required String keyBase64,
    required String ivBase64,
  }) async {
    // 1. Parse Key and IV (robustly handle both standard and url-safe base64)
    final keyBytes = base64.decode(base64.normalize(keyBase64));
    final ivBytes = base64.decode(base64.normalize(ivBase64));
    final secretKey = SecretKey(keyBytes);

    // 2. Split ciphertext and MAC tag (last 16 bytes is standard GCM MAC)
    const macLength = 16;
    if (encryptedBytes.length <= macLength) {
      throw ArgumentError('Invalid encrypted payload size');
    }
    
    final ciphertext = encryptedBytes.sublist(0, encryptedBytes.length - macLength);
    final macBytes = encryptedBytes.sublist(encryptedBytes.length - macLength);

    // 3. Decrypt
    final secretBox = SecretBox(
      ciphertext,
      nonce: ivBytes,
      mac: Mac(macBytes),
    );

    final clearTextBytes = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(clearTextBytes);
  }

  // Memory cache of chat public keys: chatId -> (deviceId -> publicKeyBase64)
  static final Map<String, Map<String, String>> chatKeys = {};

  /// Updates the key cache for a chat room.
  static void updateChatKeys(String chatId, Map<String, String> keys) {
    chatKeys[chatId] = keys;
  }

  /// Encrypts raw content under a random message key K_msg, and wraps K_msg 
  /// for each recipient device public key using X25519 ECDH + HKDF.
  static Future<String> encryptPayload({
    required String plaintext,
    required String myPrivateKeyBase64,
    required String myDeviceId,
    required List<Map<String, dynamic>> recipientDevices,
  }) async {
    final seedBytes = base64.decode(myPrivateKeyBase64);
    if (seedBytes.length != 32) {
      throw ArgumentError('Invalid X25519 private key length: ${seedBytes.length} (expected 32)');
    }

    final random = Random.secure();
    
    // 1. Generate random 256-bit message key K_msg
    final kMsgBytes = Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final kMsgSecret = SecretKey(kMsgBytes);
    
    // 2. Encrypt plaintext message body using K_msg via AES-GCM
    final bodyIv = Uint8List.fromList(List<int>.generate(12, (_) => random.nextInt(256)));
    final bodySecretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: kMsgSecret,
      nonce: bodyIv,
    );
    
    final bodyCombined = Uint8List(bodySecretBox.cipherText.length + bodySecretBox.mac.bytes.length);
    bodyCombined.setRange(0, bodySecretBox.cipherText.length, bodySecretBox.cipherText);
    bodyCombined.setRange(bodySecretBox.cipherText.length, bodyCombined.length, bodySecretBox.mac.bytes);
    
    // 3. Load local X25519 private key
    final x25519 = X25519();
    final myKeyPair = await x25519.newKeyPairFromSeed(seedBytes);
    
    // 4. Encrypt K_msg for each trusted device's public key
    final Map<String, Map<String, String>> encryptedKeysMap = {};
    
    for (final device in recipientDevices) {
      final deviceId = device['device_id'] as String;
      final publicKeyBase64 = device['public_key'] as String;
      
      try {
        final remotePublicKey = SimplePublicKey(
          base64.decode(publicKeyBase64),
          type: KeyPairType.x25519,
        );
        
        // Derive shared secret via ECDH
        final sharedSecret = await x25519.sharedSecretKey(
          keyPair: myKeyPair,
          remotePublicKey: remotePublicKey,
        );
        
        // Derive AES key via HKDF SHA-256
        final aesSecretKey = await Hkdf(
          hmac: Hmac.sha256(),
          outputLength: 32,
        ).deriveKey(
          secretKey: sharedSecret,
          nonce: [],
          info: utf8.encode('Aegis-E2EE-Key-Exchange'),
        );
        
        // Encrypt K_msg under derived AES key
        final keyIv = Uint8List.fromList(List<int>.generate(12, (_) => random.nextInt(256)));
        final keySecretBox = await _cipher.encrypt(
          kMsgBytes,
          secretKey: aesSecretKey,
          nonce: keyIv,
        );
        
        final keyCombined = Uint8List(keySecretBox.cipherText.length + keySecretBox.mac.bytes.length);
        keyCombined.setRange(0, keySecretBox.cipherText.length, keySecretBox.cipherText);
        keyCombined.setRange(keySecretBox.cipherText.length, keyCombined.length, keySecretBox.mac.bytes);
        
        encryptedKeysMap[deviceId] = {
          'key': base64.encode(keyCombined),
          'iv': base64.encode(keyIv),
        };
      } catch (e) {
        // Log and continue — wrapping for remaining devices
        debugPrint('[CryptoService] WARNING: Failed to wrap K_msg for device $deviceId: $e');
      }
    }
    
    // Validate at least one recipient device was wrapped
    if (encryptedKeysMap.isEmpty) {
      throw Exception('E2EE failed: could not wrap message key for any recipient device');
    }
    
    // 5. Build E2EE JSON envelope
    return json.encode({
      'sender_device_id': myDeviceId,
      'ciphertext': base64.encode(bodyCombined),
      'iv': base64.encode(bodyIv),
      'keys': encryptedKeysMap,
    });
  }

  /// Decrypts E2EE message envelope using local private key and sender public key.
  static Future<String> decryptPayload({
    required String payloadJson,
    required String myPrivateKeyBase64,
    required String myDeviceId,
    required String senderPublicKeyBase64,
  }) async {
    final seedBytes = base64.decode(myPrivateKeyBase64);
    if (seedBytes.length != 32) {
      throw ArgumentError('Invalid X25519 private key length: ${seedBytes.length} (expected 32)');
    }

    final payloadMap = json.decode(payloadJson) as Map<String, dynamic>;
    final bodyCombined = base64.decode(payloadMap['ciphertext'] as String);
    final bodyIv = base64.decode(payloadMap['iv'] as String);
    final keysMap = payloadMap['keys'] as Map<String, dynamic>;
    
    final myDeviceEntry = keysMap[myDeviceId] as Map<String, dynamic>?;
    if (myDeviceEntry == null) {
      throw Exception('Payload not encrypted for this device');
    }
    
    final keyCombined = base64.decode(myDeviceEntry['key'] as String);
    final keyIv = base64.decode(myDeviceEntry['iv'] as String);
    
    // 1. Derive shared secret and derived AES key
    final x25519 = X25519();
    final myKeyPair = await x25519.newKeyPairFromSeed(seedBytes);
    final remotePublicKey = SimplePublicKey(
      base64.decode(senderPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: remotePublicKey,
    );
    
    final aesSecretKey = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(
      secretKey: sharedSecret,
      nonce: [],
      info: utf8.encode('Aegis-E2EE-Key-Exchange'),
    );
    
    // 2. Decrypt K_msg using derived AES key
    const macLength = 16;
    if (keyCombined.length <= macLength) {
      throw Exception('Invalid encrypted message key');
    }
    final keyCiphertext = keyCombined.sublist(0, keyCombined.length - macLength);
    final keyMac = keyCombined.sublist(keyCombined.length - macLength);
    
    final decryptedKeyBytes = await _cipher.decrypt(
      SecretBox(
        keyCiphertext,
        nonce: keyIv,
        mac: Mac(keyMac),
      ),
      secretKey: aesSecretKey,
    );
    final kMsgSecret = SecretKey(decryptedKeyBytes);
    
    // 3. Decrypt message body using K_msg
    if (bodyCombined.length <= macLength) {
      throw Exception('Invalid encrypted message body');
    }
    final bodyCiphertext = bodyCombined.sublist(0, bodyCombined.length - macLength);
    final bodyMac = bodyCombined.sublist(bodyCombined.length - macLength);
    
    final decryptedBodyBytes = await _cipher.decrypt(
      SecretBox(
        bodyCiphertext,
        nonce: bodyIv,
        mac: Mac(bodyMac),
      ),
      secretKey: kMsgSecret,
    );
    
    return utf8.decode(decryptedBodyBytes);
  }
}
