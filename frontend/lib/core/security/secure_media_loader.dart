import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../network/envelope.dart';
import 'crypto_service.dart';

/// Typed error for media-fetch failures (404, empty body, network).
class MediaFetchException implements Exception {
  final String message;
  final int? statusCode;
  final Object? cause;
  const MediaFetchException(this.message, {this.statusCode, this.cause});
  @override
  String toString() => 'MediaFetchException($statusCode): $message';
}

abstract class EncryptedBlobSource {
  Future<Uint8List> fetchEncryptedBlob(String mediaId);
}

/// Fetches the raw encrypted blob from GET /api/media/{mediaId}.
///
/// The [Dio] instance MUST carry the app's auth interceptors (e.g. obtained
/// via [ApiClient.dio]).  The constructor accepts bare [Dio] so that tests
/// can inject a fake; production code should use the [fromApiClient] factory.
class RelayEncryptedBlobSource implements EncryptedBlobSource {
  final Dio _dio;

  RelayEncryptedBlobSource(Dio dio) : _dio = dio;

  factory RelayEncryptedBlobSource.fromApiClient(ApiClient client) {
    return RelayEncryptedBlobSource(client.dio);
  }

  @override
  Future<Uint8List> fetchEncryptedBlob(String mediaId) async {
    try {
      final response = await _dio.get<List<int>>(
        '/media/$mediaId',
        options: Options(responseType: ResponseType.bytes),
      );

      final data = response.data;
      if (data == null || data.isEmpty) {
        throw MediaFetchException(
          'Empty media response for $mediaId',
          statusCode: response.statusCode,
        );
      }

      return Uint8List.fromList(data);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) {
        throw MediaFetchException(
          'Media not found: $mediaId',
          statusCode: 404,
          cause: e,
        );
      }
      throw MediaFetchException(
        'Network error fetching media $mediaId',
        statusCode: status,
        cause: e,
      );
    } catch (e) {
      if (e is MediaFetchException) rethrow;
      throw MediaFetchException(
        'Unexpected error fetching media $mediaId',
        cause: e,
      );
    }
  }
}

class InMemoryMedia {
  final Uint8List _bytes;
  final String? mime;
  final String filename;
  bool _isDisposed = false;

  InMemoryMedia(this._bytes, this.mime, this.filename);

  Uint8List get bytes {
    if (_isDisposed) throw StateError('Media has been disposed');
    return _bytes;
  }

  void dispose() {
    if (_isDisposed) return;
    for (int i = 0; i < _bytes.length; i++) {
      _bytes[i] = 0;
    }
    _isDisposed = true;
  }
}

class SecureMediaLoader {
  final EncryptedBlobSource source;

  SecureMediaLoader({required this.source});

  Future<InMemoryMedia> load(MediaMetadata meta) async {
    final encryptedBlob = await source.fetchEncryptedBlob(meta.mediaId);

    final decryptedBytes = await CryptoService.decryptFile(
      encryptedBytes: encryptedBlob,
      keyBase64: meta.keyBase64,
      ivBase64: meta.ivBase64,
    );

    return InMemoryMedia(decryptedBytes, meta.mime, meta.filename);
  }
}

