import 'dart:typed_data';
import '../network/envelope.dart';
import 'crypto_service.dart';

abstract class EncryptedBlobSource {
  Future<Uint8List> fetchEncryptedBlob(String mediaId);
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
