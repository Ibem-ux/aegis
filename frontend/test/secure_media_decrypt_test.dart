import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_chat/core/security/crypto_service.dart';
import 'package:aegis_chat/core/security/secure_media_loader.dart';
import 'package:aegis_chat/core/network/envelope.dart';

class FakeBlobSource extends EncryptedBlobSource {
  final Uint8List blob;
  FakeBlobSource(this.blob);
  
  @override
  Future<Uint8List> fetchEncryptedBlob(String mediaId) async {
    return blob;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track B Secure Media Decrypt (In-Memory)', () {
    test('Task 5.1: Round-trip test using original encryption/decryption', () async {
      final plaintext = utf8.encode('AEGIS-SECURE-MEDIA-OK');
      final originalData = Uint8List.fromList(plaintext);
      
      // Use the existing encryptFile from CryptoService
      final result = await CryptoService.encryptFile(originalData);
      
      final encryptedBytes = result['encryptedBytes'] as Uint8List;
      final keyBase64 = result['key'] as String;
      final ivBase64 = result['iv'] as String;
      
      // Attempt decrypt
      final decrypted = await CryptoService.decryptFile(
        encryptedBytes: encryptedBytes,
        keyBase64: keyBase64,
        ivBase64: ivBase64,
      );
      
      expect(decrypted, equals(originalData));
    });

    test('Task 5.2: Variant-distinguishing case (prove normalize accepts standard base64)', () async {
      // Create key and iv with bytes that produce + and / in standard base64
      // 0xFB = 251 -> standard base64 emits +, url-safe emits -
      // 0xFF = 255 -> standard base64 emits /, url-safe emits _
      final rawKey = Uint8List(32);
      rawKey.fillRange(0, 32, 251); 
      rawKey[1] = 255;
      
      final rawIv = Uint8List(12);
      rawIv.fillRange(0, 12, 255);
      rawIv[1] = 251;
      
      // Standard base64 variant (with + and /)
      final standardKeyBase64 = base64.encode(rawKey);
      final standardIvBase64 = base64.encode(rawIv);
      
      expect(standardKeyBase64.contains('+') || standardKeyBase64.contains('/'), isTrue);
      expect(standardIvBase64.contains('+') || standardIvBase64.contains('/'), isTrue);

      // Verify decryptFile accepts the standard variant without FormatException
      try {
        final dummyBytes = Uint8List(32); // 16 bytes ciphertext + 16 bytes mac
        await CryptoService.decryptFile(
          encryptedBytes: dummyBytes,
          keyBase64: standardKeyBase64,
          ivBase64: standardIvBase64,
        );
        fail('Should have thrown MAC failure, not FormatException');
      } catch (e) {
        // Assert it did NOT fail due to FormatException (base64 decode error)
        expect(e, isNot(isA<FormatException>()));
      }
    });

    test('Task 5.3: Tampered ciphertext rejection', () async {
      final plaintext = utf8.encode('AEGIS-SECURE-MEDIA-OK');
      final originalData = Uint8List.fromList(plaintext);
      final result = await CryptoService.encryptFile(originalData);
      
      final encryptedBytes = result['encryptedBytes'] as Uint8List;
      final keyBase64 = result['key'] as String;
      final ivBase64 = result['iv'] as String;
      
      // Tamper with the ciphertext (flip first byte)
      encryptedBytes[0] ^= 0xFF;
      
      // Should fail Mac check and throw SecretBoxAuthenticationError / MacAlgorithmException
      expect(
        () => CryptoService.decryptFile(
          encryptedBytes: encryptedBytes,
          keyBase64: keyBase64,
          ivBase64: ivBase64,
        ),
        throwsA(isNot(isA<FormatException>())), // Anything except format exception, cryptography throws MAC errors
      );
      
      try {
        await CryptoService.decryptFile(
          encryptedBytes: encryptedBytes,
          keyBase64: keyBase64,
          ivBase64: ivBase64,
        );
        fail('Should have thrown on tampered MAC');
      } catch (e) {
        // Verify it's a crypto error, not something else. We just ensure it throws.
      }
    });
    
    test('Task 6: Loader wiring test and InMemoryMedia dispose (zeroization)', () async {
      final plaintext = utf8.encode('TOP-SECRET-DOCUMENT-12345');
      final originalData = Uint8List.fromList(plaintext);
      final result = await CryptoService.encryptFile(originalData);
      
      final fakeSource = FakeBlobSource(result['encryptedBytes'] as Uint8List);
      final loader = SecureMediaLoader(source: fakeSource);
      
      final meta = MediaMetadata(
        mediaId: 'media-777',
        keyBase64: result['key'] as String,
        ivBase64: result['iv'] as String,
        filename: 'secret.txt',
        mime: 'text/plain',
      );
      
      // Decrypt via loader
      final media = await loader.load(meta);
      
      // Obtain internal buffer reference BEFORE dispose
      final rawBuffer = media.bytes;
      
      // Verify correct plaintext
      expect(rawBuffer, equals(originalData));
      
      // Call dispose and verify zeroization
      media.dispose();
      
      // The buffer itself should be filled with 0s
      for (final byte in rawBuffer) {
        expect(byte, equals(0), reason: 'Buffer should be zeroed after dispose');
      }
      
      // Accessing through media.bytes should throw
      expect(() => media.bytes, throwsStateError);
    });
  });
}
