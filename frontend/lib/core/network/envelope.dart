enum MessageType {
  text('TEXT'),
  image('IMAGE'),
  video('VIDEO'),
  audio('AUDIO'),
  recording('RECORDING');

  final String value;
  const MessageType(this.value);

  static MessageType fromValue(String value) {
    return MessageType.values.firstWhere(
      (MessageType e) => e.value == value,
      orElse: () => throw FormatException('Unknown MessageType: $value'),
    );
  }
}

class WrappedKey {
  final String key;
  final String iv;

  const WrappedKey({required this.key, required this.iv});

  factory WrappedKey.fromJson(Map<String, dynamic> json) => WrappedKey(
        key: json['key'] as String,
        iv: json['iv'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'iv': iv,
      };
}

class EncryptedEnvelope {
  final String messageId;
  final String chatId;
  final String senderDeviceId;
  final MessageType type;
  final String ciphertext;
  final String iv;
  final Map<String, WrappedKey> keys;
  final String sentAt;

  const EncryptedEnvelope({
    required this.messageId,
    required this.chatId,
    required this.senderDeviceId,
    required this.type,
    required this.ciphertext,
    required this.iv,
    required this.keys,
    required this.sentAt,
  });

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) =>
      EncryptedEnvelope(
        messageId: json['messageId'] as String,
        chatId: json['chatId'] as String,
        senderDeviceId: json['senderDeviceId'] as String,
        type: MessageType.fromValue(json['type'] as String),
        ciphertext: json['ciphertext'] as String,
        iv: json['iv'] as String,
        keys: (json['keys'] as Map<String, dynamic>).map(
          (String k, dynamic v) => MapEntry<String, WrappedKey>(
            k,
            WrappedKey.fromJson(v as Map<String, dynamic>),
          ),
        ),
        sentAt: json['sentAt'] as String,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'messageId': messageId,
        'chatId': chatId,
        'senderDeviceId': senderDeviceId,
        'type': type.value,
        'ciphertext': ciphertext,
        'iv': iv,
        'keys': keys.map(
          (String k, WrappedKey v) => MapEntry<String, dynamic>(k, v.toJson()),
        ),
        'sentAt': sentAt,
      };
}

/// Shared media-metadata contract (README §6.1).
class MediaMetadata {
  final String mediaId;    // server ref for GET /api/media/{mediaId}
  final String keyBase64;  // AES-256-GCM file key, base64 (SAME variant CryptoService.decryptFile decodes)
  final String ivBase64;   // AES-256-GCM file iv,  base64 (SAME variant CryptoService.decryptFile decodes)
  final String filename;
  final String? mime;
  const MediaMetadata({
    required this.mediaId, required this.keyBase64, required this.ivBase64,
    required this.filename, this.mime,
  });
  factory MediaMetadata.fromJson(Map<String, dynamic> j) => MediaMetadata(
    mediaId: j['media_id'] as String,
    keyBase64: j['file_key'] as String,
    ivBase64: j['file_iv'] as String,
    filename: j['filename'] as String,
    mime: j['mime'] as String?,
  );
}
