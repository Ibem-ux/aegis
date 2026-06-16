import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_chat/core/security/crypto_service.dart';
import 'package:aegis_chat/core/security/secure_media_loader.dart';
import 'package:aegis_chat/core/network/envelope.dart';

// ---------------------------------------------------------------------------
// Fake blob source – injects pre-built encrypted bytes
// ---------------------------------------------------------------------------
class _FakeBlobSource extends EncryptedBlobSource {
  final Uint8List? _blob;
  final Object? _error;

  _FakeBlobSource.ok(Uint8List blob) : _blob = blob, _error = null;
  _FakeBlobSource.error(Object error) : _blob = null, _error = error;
  _FakeBlobSource.empty() : _blob = Uint8List(0), _error = null;

  @override
  Future<Uint8List> fetchEncryptedBlob(String mediaId) async {
    if (_error != null) throw _error;
    if (_blob == null || _blob.isEmpty) {
      throw MediaFetchException('Empty media response for $mediaId');
    }
    return _blob;
  }
}

// ---------------------------------------------------------------------------
// Fake Dio HttpClientAdapter – returns pre-canned responses without network
// ---------------------------------------------------------------------------
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int>? bodyBytes;

  _FakeHttpClientAdapter({required this.statusCode, this.bodyBytes});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (statusCode >= 400) {
      throw DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: statusCode,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return ResponseBody.fromBytes(
      bodyBytes ?? [],
      statusCode,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track B Secure Media Pipeline', () {
    // ------ Happy path: encrypt → FakeBlobSource → SecureMediaLoader ------
    test('full round-trip: encrypt → source → loader → decrypted InMemoryMedia', () async {
      final plaintext = utf8.encode('TEST-ENCRYPTED-BLOB-CONTENT-XYZ');
      final originalData = Uint8List.fromList(plaintext);

      // Encrypt with CryptoService (same path the sender uses)
      final encResult = await CryptoService.encryptFile(originalData);
      final encryptedBytes = encResult['encryptedBytes'] as Uint8List;

      final source = _FakeBlobSource.ok(encryptedBytes);
      final loader = SecureMediaLoader(source: source);

      final meta = MediaMetadata(
        mediaId: 'media-test-123',
        keyBase64: encResult['key'] as String,
        ivBase64: encResult['iv'] as String,
        filename: 'test.bin',
        mime: 'application/octet-stream',
      );

      final media = await loader.load(meta);

      expect(media.bytes, equals(originalData));
      expect(media.filename, equals('test.bin'));
      expect(media.mime, equals('application/octet-stream'));
    });

    // ------ Dispose zeroes the buffer ------
    test('InMemoryMedia dispose() zeroes the buffer and blocks further reads', () async {
      final plaintext = utf8.encode('SENSITIVE-DATA-TO-BE-ZEROFIED');
      final originalData = Uint8List.fromList(plaintext);

      final encResult = await CryptoService.encryptFile(originalData);
      final encryptedBytes = encResult['encryptedBytes'] as Uint8List;

      final source = _FakeBlobSource.ok(encryptedBytes);
      final loader = SecureMediaLoader(source: source);

      final meta = MediaMetadata(
        mediaId: 'media-dispose-test',
        keyBase64: encResult['key'] as String,
        ivBase64: encResult['iv'] as String,
        filename: 'secret.bin',
        mime: null,
      );

      final media = await loader.load(meta);
      final rawBuffer = media.bytes;

      expect(rawBuffer, equals(originalData));

      media.dispose();

      // Every byte in the underlying buffer must be zero
      for (final byte in rawBuffer) {
        expect(byte, equals(0), reason: 'Buffer should be zeroed after dispose');
      }

      // Accessing .bytes after dispose must throw
      expect(() => media.bytes, throwsStateError);
    });

    // ------ 404 / error throws MediaFetchException ------
    test('404/error response throws MediaFetchException', () async {
      final source = _FakeBlobSource.error(
        const MediaFetchException('Media not found: media-nonexistent', statusCode: 404),
      );
      final loader = SecureMediaLoader(source: source);

      final meta = MediaMetadata(
        mediaId: 'media-nonexistent',
        keyBase64: base64.encode(Uint8List(32)),
        ivBase64: base64.encode(Uint8List(12)),
        filename: 'missing.bin',
      );

      expect(
        () => loader.load(meta),
        throwsA(isA<MediaFetchException>()),
      );
    });

    // ------ Empty response throws MediaFetchException ------
    test('Empty response throws MediaFetchException', () async {
      final source = _FakeBlobSource.empty();
      final loader = SecureMediaLoader(source: source);

      final meta = MediaMetadata(
        mediaId: 'media-empty',
        keyBase64: base64.encode(Uint8List(32)),
        ivBase64: base64.encode(Uint8List(12)),
        filename: 'empty.bin',
      );

      expect(
        () => loader.load(meta),
        throwsA(isA<MediaFetchException>()),
      );
    });

    // ------ RelayEncryptedBlobSource with fake Dio adapter ------
    test('RelayEncryptedBlobSource hits /media/{id} and returns raw bytes', () async {
      final plaintext = utf8.encode('relay-blob-source-test');
      final originalData = Uint8List.fromList(plaintext);

      final encResult = await CryptoService.encryptFile(originalData);
      final encryptedBytes = encResult['encryptedBytes'] as Uint8List;

      final dio = Dio(BaseOptions(baseUrl: 'http://fake'));
      dio.httpClientAdapter = _FakeHttpClientAdapter(
        statusCode: 200,
        bodyBytes: encryptedBytes,
      );

      final source = RelayEncryptedBlobSource(dio);
      final blob = await source.fetchEncryptedBlob('abc-123');

      expect(blob, equals(encryptedBytes));
    });

    test('RelayEncryptedBlobSource throws MediaFetchException on 404', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://fake'));
      dio.httpClientAdapter = _FakeHttpClientAdapter(statusCode: 404);

      final source = RelayEncryptedBlobSource(dio);

      expect(
        () => source.fetchEncryptedBlob('nonexistent'),
        throwsA(
          isA<MediaFetchException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });
}
