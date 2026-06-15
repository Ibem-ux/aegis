import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../../../core/database/local_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/security/crypto_service.dart';
import '../../../core/secure_storage/secure_storage.dart';
import '../../../core/network/envelope.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';

class MessagesRepository {
  final AppDatabase _db;
  final ApiClient _apiClient;
  final SocketClient _socketClient;
  final SecureStorage _secureStorage = SecureStorage();
  bool _listenersInitialized = false;

  MessagesRepository(this._db, this._apiClient, this._socketClient);

  /// Initialize socket stream listeners (call once from UI layer)
  void initSocketListeners() {
    if (_listenersInitialized) return;
    _listenersInitialized = true;

    // Listen to incoming real-time messages and insert into local SQLite
    _socketClient.messageStream.listen((data) async {
      try {
        final envelope = EncryptedEnvelope.fromJson(data);
        
        // Ensure the chat exists in local DB (FK constraint)
        final existingChat = await (_db.select(_db.localChats)
              ..where((t) => t.id.equals(envelope.chatId)))
            .getSingleOrNull();
            
        if (existingChat == null) {
          // Fallback: create a dummy chat to satisfy FK constraint if we receive a message
          // before the chat metadata syncs.
          await _db.into(_db.localChats).insert(
            LocalChatsCompanion.insert(
              id: envelope.chatId,
              recipientId: envelope.senderDeviceId, // Using device ID as placeholder
              recipientUsername: 'Unknown',
              recipientDisplayName: 'Unknown',
              lastMessageAt: DateTime.parse(envelope.sentAt),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }

        final rawContent = _envelopeToCryptoPayload(envelope);
        final decryptedContent = await decryptMessageContent(envelope.chatId, rawContent, envelope.type.value);
        
        await _db.into(_db.localMessages).insert(
          LocalMessagesCompanion.insert(
            id: envelope.messageId,
            chatId: envelope.chatId,
            senderId: envelope.senderDeviceId,
            content: decryptedContent,
            messageType: envelope.type.value,
            createdAt: DateTime.parse(envelope.sentAt),
            syncStatus: 'SYNCED',
          ),
          mode: InsertMode.insertOrIgnore,
        );

        // Update chat preview for real-time home page updates
        await (_db.update(_db.localChats)
              ..where((t) => t.id.equals(envelope.chatId)))
            .write(LocalChatsCompanion(
              lastMessageAt: Value(DateTime.parse(envelope.sentAt)),
              lastMessagePreview: Value(decryptedContent),
            ));
            
        // Emit message:ack to drop the queued copy on the relay
        final myDeviceId = await _secureStorage.getDeviceId();
        if (myDeviceId != null) {
          _socketClient.sendAck(envelope.messageId, myDeviceId);
        }
      } catch (e) {
        debugPrint('Error inserting real-time message: $e');
      }
    });

    // Listen to delivery/read status updates and update local syncStatus
    _socketClient.statusStream.listen((data) async {
      try {
        final messageId = data['message_id'] as String;
        final status = data['status'] as String; // 'DELIVERED' or 'READ'
        // Map server status to local syncStatus representation
        final localStatus = status == 'READ' ? 'READ' : (status == 'DELIVERED' ? 'DELIVERED' : 'SYNCED');
        await (_db.update(_db.localMessages)
              ..where((t) => t.id.equals(messageId)))
            .write(LocalMessagesCompanion(syncStatus: Value(localStatus)));
      } catch (e) {
        // Silently handle
      }
    });

    // Hook reconnection callback for offline sync
    _socketClient.onConnectCallback = () {
      syncOfflineQueue();
    };
  }

  /// Watches all messages for a specific chat (in reverse chronological order)
  Stream<List<LocalMessage>> watchMessages(String chatId) {
    return (_db.select(_db.localMessages)
          ..where((t) => t.chatId.equals(chatId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }



  /// Fetches participant public keys from server and populates cache
  Future<void> loadChatKeys(String chatId) async {
    try {
      final response = await _apiClient.dio.get<List<dynamic>>('${ApiEndpoints.chats}/$chatId/keys');
      final data = response.data!;

      final Map<String, String> keysMap = {};
      for (final item in data) {
        final device = item as Map<String, dynamic>;
        final deviceId = device['device_id'] as String;
        final publicKey = device['public_key'] as String;
        keysMap[deviceId] = publicKey;
      }

      CryptoService.updateChatKeys(chatId, keysMap);
    } catch (e) {
      // Silently fail
    }
  }

  /// Decrypts encrypted message content using E2EE keys
  Future<String> decryptMessageContent(String chatId, String rawContent, String messageType) async {
    if (messageType == 'SYSTEM') {
      return rawContent;
    }

    if (!rawContent.startsWith('{"') || !rawContent.contains('"ciphertext"')) {
      // Backwards compatibility with plaintext
      return rawContent;
    }

    try {
      final payload = json.decode(rawContent) as Map<String, dynamic>;
      final senderDeviceId = payload['sender_device_id'] as String;

      final myPrivateKey = await _secureStorage.getDevicePrivateKey();
      final myDeviceId = await _secureStorage.getDeviceId();

      if (myPrivateKey == null || myDeviceId == null) {
        return '[Encrypted Message (Keys missing)]';
      }

      // Try to load keys if missing from cache
      if (!CryptoService.chatKeys.containsKey(chatId) || 
          !CryptoService.chatKeys[chatId]!.containsKey(senderDeviceId)) {
        await loadChatKeys(chatId);
      }

      final senderPublicKey = CryptoService.chatKeys[chatId]?[senderDeviceId];
      if (senderPublicKey == null) {
        // Retry loading once
        await loadChatKeys(chatId);
      }

      final senderPublicKeyFinal = CryptoService.chatKeys[chatId]?[senderDeviceId];
      if (senderPublicKeyFinal == null) {
        return '[Encrypted Message (Untrusted Device)]';
      }

      return await CryptoService.decryptPayload(
        payloadJson: rawContent,
        myPrivateKeyBase64: myPrivateKey,
        myDeviceId: myDeviceId,
        senderPublicKeyBase64: senderPublicKeyFinal,
      );
    } catch (e) {
      return '[Decryption Failed]';
    }
  }

  /// Sends a text message
  Future<void> sendTextMessage(String chatId, String text) async {
    final messageId = const Uuid().v4();
    final myUserId = await _secureStorage.getUserId() ?? '';
    final myDeviceId = await _secureStorage.getDeviceId() ?? '';
    final myPrivateKey = await _secureStorage.getDevicePrivateKey() ?? '';

    // 1. Write to local database as PENDING (using plaintext `text` so the local database has the decrypted content)
    final localMsg = LocalMessagesCompanion.insert(
      id: messageId,
      chatId: chatId,
      senderId: myUserId,
      content: text,
      messageType: 'TEXT',
      createdAt: DateTime.now(),
      syncStatus: 'PENDING',
    );
    await _db.into(_db.localMessages).insert(localMsg);

    // 2. Encrypt text content using hybrid E2EE
    if (!CryptoService.chatKeys.containsKey(chatId)) {
      await loadChatKeys(chatId);
    }
    
    final chatDevices = CryptoService.chatKeys[chatId] ?? {};
    final recipientList = chatDevices.entries.map((e) => <String, String>{
      'device_id': e.key,
      'public_key': e.value,
    }).toList();

    String payloadToSend = text;
    if (recipientList.isNotEmpty && myPrivateKey.isNotEmpty) {
      try {
        payloadToSend = await CryptoService.encryptPayload(
          plaintext: text,
          myPrivateKeyBase64: myPrivateKey,
          myDeviceId: myDeviceId,
          recipientDevices: recipientList,
        );
      } catch (e) {
        // WARNING: Encryption failed — message will be sent in plaintext
        debugPrint('[MessagesRepository] ⚠️ E2EE encryption failed, falling back to plaintext: $e');
      }
    }

    final envelope = _cryptoPayloadToEnvelope(
      messageId: messageId,
      chatId: chatId,
      senderDeviceId: myDeviceId,
      type: MessageType.text,
      payloadJson: payloadToSend,
    );
    final envelopeJson = envelope.toJson();

    // 3. Transmit via WebSockets with acknowledgement
    if (_socketClient.isConnected) {
      _socketClient.sendMessageWithAck(envelopeJson, (ack) async {
        if (ack is Map<String, dynamic> && ack['success'] == true) {
          // Server confirmed persistence — mark as SENT
          await (_db.update(_db.localMessages)
                ..where((t) => t.id.equals(messageId)))
              .write(const LocalMessagesCompanion(syncStatus: Value('SENT')));
        }
      });
    } else {
      // Queue offline sync
      await _db.into(_db.syncQueue).insert(
            SyncQueueCompanion.insert(
              actionType: 'SEND_MESSAGE',
              payload: json.encode(envelopeJson),
            ),
          );
    }
  }

  /// Processes pending items in the offline sync queue
  Future<void> syncOfflineQueue() async {
    final queueItems = await (_db.select(_db.syncQueue)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]))
        .get();

    for (final item in queueItems) {
      try {
        final payload = json.decode(item.payload) as Map<String, dynamic>;

        if (item.actionType == 'SEND_MESSAGE') {
          _socketClient.sendMessageWithAck(payload, (ack) async {
            if (ack is Map<String, dynamic> && ack['success'] == true) {
              final msgId = payload['messageId'] as String?;
              if (msgId != null) {
                await (_db.update(_db.localMessages)
                      ..where((t) => t.id.equals(msgId)))
                    .write(const LocalMessagesCompanion(syncStatus: Value('SENT')));
              }
            }
          });
        }

        // Remove from queue after processing
        await (_db.delete(_db.syncQueue)..where((t) => t.id.equals(item.id))).go();
      } catch (e) {
        // If processing fails, leave in queue for next attempt
      }
    }
  }

  // TODO Step 4: remove backend message:read handler (read receipts dropped)

  /// Encrypts and sends a media attachment (photo, video, voice note, document)
  /// Not available on web platform.
  Future<void> sendMediaMessage(String chatId, dynamic file, String type) async {
    if (kIsWeb) {
      throw UnsupportedError('Media upload is not supported on web');
    }
    final bytes = await file.readAsBytes() as Uint8List;
    
    // 1. Client-side encrypt file bytes
    final encryptionResult = await CryptoService.encryptFile(bytes);
    final encryptedFileBytes = encryptionResult['encryptedBytes'] as Uint8List;
    final fileKey = encryptionResult['key'] as String;
    final fileIv = encryptionResult['iv'] as String;

    // 2. Request pre-signed upload URL from backend
    final filePath = file.path as String;
    final filename = filePath.split('/').last;
    final uploadResponse = await _apiClient.dio.get<Map<String, dynamic>>(
      ApiEndpoints.mediaUpload,
      queryParameters: {
        'filename': filename,
        'mime_type': _getMimeType(filePath, type),
        'file_size': encryptedFileBytes.length,
        'encrypted': 'true',
      },
    );

    final uploadDetails = uploadResponse.data as Map<String, dynamic>;
    final uploadUrl = uploadDetails['upload_url'] as String;
    final mediaId = uploadDetails['media_id'] as String;

    // 3. Upload encrypted bytes directly to MinIO
    await Dio().put<dynamic>(
      uploadUrl,
      data: encryptedFileBytes,
      options: Options(
        headers: {
          Headers.contentLengthHeader: encryptedFileBytes.length,
          'Content-Type': 'application/octet-stream',
        },
      ),
    );

    // 4. Pack AES key and IV inside message content payload
    final metaContent = json.encode({
      'file_key': fileKey,
      'file_iv': fileIv,
      'filename': filename,
    });

    final messageId = const Uuid().v4();
    final myUserId = await _secureStorage.getUserId() ?? '';
    final myDeviceId = await _secureStorage.getDeviceId() ?? '';
    final myPrivateKey = await _secureStorage.getDevicePrivateKey() ?? '';

    // 5. Write to local database as PENDING (storing metaContent JSON locally so sender can view)
    final localMsg = LocalMessagesCompanion.insert(
      id: messageId,
      chatId: chatId,
      senderId: myUserId,
      content: metaContent,
      messageType: type,
      mediaId: Value(mediaId),
      createdAt: DateTime.now(),
      syncStatus: 'PENDING',
    );
    await _db.into(_db.localMessages).insert(localMsg);

    // 6. Encrypt metaContent for Socket.IO
    if (!CryptoService.chatKeys.containsKey(chatId)) {
      await loadChatKeys(chatId);
    }
    final chatDevices = CryptoService.chatKeys[chatId] ?? {};
    final recipientList = chatDevices.entries.map((e) => <String, String>{
      'device_id': e.key,
      'public_key': e.value,
    }).toList();

    String payloadToSend = metaContent;
    if (recipientList.isNotEmpty && myPrivateKey.isNotEmpty) {
      try {
        payloadToSend = await CryptoService.encryptPayload(
          plaintext: metaContent,
          myPrivateKeyBase64: myPrivateKey,
          myDeviceId: myDeviceId,
          recipientDevices: recipientList,
        );
      } catch (e) {
        // Fallback
      }
    }

    final envelope = _cryptoPayloadToEnvelope(
      messageId: messageId,
      chatId: chatId,
      senderDeviceId: myDeviceId,
      type: MessageType.fromValue(type),
      payloadJson: payloadToSend,
    );
    final envelopeJson = envelope.toJson();

    // 7. Send payload via WebSocket with ack
    if (_socketClient.isConnected) {
      _socketClient.sendMessageWithAck(envelopeJson, (ack) async {
        if (ack is Map<String, dynamic> && ack['success'] == true) {
          await (_db.update(_db.localMessages)
                ..where((t) => t.id.equals(messageId)))
              .write(const LocalMessagesCompanion(syncStatus: Value('SENT')));
        }
      });
    } else {
      // Queue offline sync
      await _db.into(_db.syncQueue).insert(
            SyncQueueCompanion.insert(
              actionType: 'SEND_MESSAGE',
              payload: json.encode(envelopeJson),
            ),
          );
    }
  }

  /// Downloads, decrypts, and saves an encrypted media file to local device path.
  /// Not available on web platform.
  Future<Uint8List> downloadAndDecryptMedia({
    required String mediaId,
    required String keyBase64,
    required String ivBase64,
    required String filename,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Media download is not supported on web');
    }

    // 1. Get pre-signed download URL from backend
    final downloadUrlRes = await _apiClient.dio.get<Map<String, dynamic>>('${ApiEndpoints.mediaDownload}/$mediaId');
    final downloadDetails = downloadUrlRes.data!;
    final downloadUrl = downloadDetails['download_url'] as String;

    // 2. Fetch encrypted file stream
    final downloadResponse = await Dio().get<List<int>>(
      downloadUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final encryptedBytes = Uint8List.fromList(downloadResponse.data!);

    // 3. Client-side decrypt using cached keys
    final decryptedBytes = await CryptoService.decryptFile(
      encryptedBytes: encryptedBytes,
      keyBase64: keyBase64,
      ivBase64: ivBase64,
    );

    return decryptedBytes;
  }

  String _getMimeType(String path, String type) {
    final ext = path.split('.').last.toLowerCase();
    switch (type) {
      case 'IMAGE':
        if (ext == 'png') return 'image/png';
        if (ext == 'gif') return 'image/gif';
        if (ext == 'webp') return 'image/webp';
        return 'image/jpeg';
      case 'VIDEO':
        if (ext == 'webm') return 'video/webm';
        if (ext == 'mov') return 'video/quicktime';
        if (ext == 'avi') return 'video/x-msvideo';
        return 'video/mp4';
      case 'AUDIO':
      case 'RECORDING':
        if (ext == 'mp3') return 'audio/mpeg';
        if (ext == 'wav') return 'audio/wav';
        if (ext == 'ogg') return 'audio/ogg';
        if (ext == 'm4a') return 'audio/mp4';
        return 'audio/aac';
      default:
        return 'application/octet-stream';
    }
  }

  // Adapter functions to map EncryptedEnvelope to CryptoService expectations
  String _envelopeToCryptoPayload(EncryptedEnvelope envelope) {
    return json.encode({
      'sender_device_id': envelope.senderDeviceId,
      'ciphertext': envelope.ciphertext,
      'iv': envelope.iv,
      'keys': envelope.keys.map((k, v) => MapEntry(k, v.toJson())),
    });
  }

  EncryptedEnvelope _cryptoPayloadToEnvelope({
    required String messageId,
    required String chatId,
    required String senderDeviceId,
    required MessageType type,
    required String payloadJson,
  }) {
    try {
      final data = json.decode(payloadJson) as Map<String, dynamic>;
      return EncryptedEnvelope(
        messageId: messageId,
        chatId: chatId,
        senderDeviceId: senderDeviceId,
        type: type,
        ciphertext: data['ciphertext'] as String,
        iv: data['iv'] as String,
        keys: (data['keys'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, WrappedKey.fromJson(v as Map<String, dynamic>)),
        ),
        sentAt: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Fallback for plaintext payloads if E2EE failed during generation
      return EncryptedEnvelope(
        messageId: messageId,
        chatId: chatId,
        senderDeviceId: senderDeviceId,
        type: type,
        ciphertext: payloadJson,
        iv: '',
        keys: const {},
        sentAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }
}

