import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_chat/core/security/crypto_service.dart';

void main() {
  group('CryptoService E2EE Tests', () {
    test('File encrypt/decrypt roundtrip', () async {
      final originalData = Uint8List.fromList([1, 2, 3, 4, 5, 255, 0, 42]);
      
      final encryptionResult = await CryptoService.encryptFile(originalData);
      expect(encryptionResult.containsKey('encryptedBytes'), true);
      expect(encryptionResult.containsKey('key'), true);
      expect(encryptionResult.containsKey('iv'), true);
      
      final encryptedBytes = encryptionResult['encryptedBytes'] as Uint8List;
      final keyBase64 = encryptionResult['key'] as String;
      final ivBase64 = encryptionResult['iv'] as String;
      
      final decryptedData = await CryptoService.decryptFile(
        encryptedBytes: encryptedBytes,
        keyBase64: keyBase64,
        ivBase64: ivBase64,
      );
      
      expect(decryptedData, equals(originalData));
    });

    test('Payload encrypt/decrypt roundtrip with Alice and Bob', () async {
      final x25519 = X25519();
      
      // Alice KeyPair
      final aliceKeyPair = await x25519.newKeyPair();
      final alicePrivBytes = await aliceKeyPair.extractPrivateKeyBytes();
      final alicePubBytes = await aliceKeyPair.extractPublicKey();
      final alicePrivBase64 = base64.encode(alicePrivBytes);
      final alicePubBase64 = base64.encode(alicePubBytes.bytes);
      final aliceDeviceId = 'device-alice-1';

      // Bob KeyPair
      final bobKeyPair = await x25519.newKeyPair();
      final bobPrivBytes = await bobKeyPair.extractPrivateKeyBytes();
      final bobPubBytes = await bobKeyPair.extractPublicKey();
      final bobPrivBase64 = base64.encode(bobPrivBytes);
      final bobPubBase64 = base64.encode(bobPubBytes.bytes);
      final bobDeviceId = 'device-bob-1';

      final originalMessage = 'Hello Bob, this is a secret E2EE message!';

      // Alice encrypts for Bob (and herself)
      final encryptedPayloadJson = await CryptoService.encryptPayload(
        plaintext: originalMessage,
        myPrivateKeyBase64: alicePrivBase64,
        myDeviceId: aliceDeviceId,
        recipientDevices: [
          {'device_id': aliceDeviceId, 'public_key': alicePubBase64},
          {'device_id': bobDeviceId, 'public_key': bobPubBase64},
        ],
      );

      final payloadMap = json.decode(encryptedPayloadJson) as Map<String, dynamic>;
      expect(payloadMap['sender_device_id'], aliceDeviceId);
      expect(payloadMap.containsKey('ciphertext'), true);
      expect(payloadMap.containsKey('iv'), true);
      expect(payloadMap.containsKey('keys'), true);
      
      final keysMap = payloadMap['keys'] as Map<String, dynamic>;
      expect(keysMap.containsKey(aliceDeviceId), true);
      expect(keysMap.containsKey(bobDeviceId), true);

      // Bob decrypts
      final decryptedByBob = await CryptoService.decryptPayload(
        payloadJson: encryptedPayloadJson,
        myPrivateKeyBase64: bobPrivBase64,
        myDeviceId: bobDeviceId,
        senderPublicKeyBase64: alicePubBase64,
      );

      expect(decryptedByBob, originalMessage);
      
      // Alice decrypts (self-read)
      final decryptedByAlice = await CryptoService.decryptPayload(
        payloadJson: encryptedPayloadJson,
        myPrivateKeyBase64: alicePrivBase64,
        myDeviceId: aliceDeviceId,
        senderPublicKeyBase64: alicePubBase64,
      );
      
      expect(decryptedByAlice, originalMessage);
    });

    test('Invalid key length rejection', () async {
      final invalidPrivKeyBase64 = base64.encode([1, 2, 3]); // only 3 bytes
      
      expect(
        () async => await CryptoService.encryptPayload(
          plaintext: 'test',
          myPrivateKeyBase64: invalidPrivKeyBase64,
          myDeviceId: 'dev1',
          recipientDevices: [{'device_id': 'dev1', 'public_key': 'abc'}],
        ),
        throwsA(isA<ArgumentError>()),
      );
      
      expect(
        () async => await CryptoService.decryptPayload(
          payloadJson: '{}',
          myPrivateKeyBase64: invalidPrivKeyBase64,
          myDeviceId: 'dev1',
          senderPublicKeyBase64: 'abc',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Empty recipients rejection', () async {
      final x25519 = X25519();
      final keyPair = await x25519.newKeyPair();
      final privBytes = await keyPair.extractPrivateKeyBytes();
      final privBase64 = base64.encode(privBytes);
      
      expect(
        () async => await CryptoService.encryptPayload(
          plaintext: 'test',
          myPrivateKeyBase64: privBase64,
          myDeviceId: 'dev1',
          recipientDevices: [], // empty recipients
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
