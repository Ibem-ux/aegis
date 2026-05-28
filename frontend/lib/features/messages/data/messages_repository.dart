import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart';
import '../../../core/database/local_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/socket_client.dart';
import '../../../core/security/crypto_service.dart';
import '../../../core/secure_storage/secure_storage.dart';
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
        final sender = data['sender'] as Map<String, dynamic>;
        final rawContent = data['content'] as String;
        final decryptedContent = await decryptMessageContent(data['chat_id'] as String, rawContent, data['message_type'] as String);
        
        await _db.into(_db.localMessages).insert(
          LocalMessagesCompanion.insert(
            id: data['id'] as String,
            chatId: data['chat_id'] as String,
            senderId: sender['id'] as String,
            content: decryptedContent,
            messageType: data['message_type'] as String,
            mediaId: Value(data['media_id'] as String?),
            replyToId: Value(data['reply_to_id'] as String?),
            createdAt: DateTime.parse(data['created_at'] as String),
            syncStatus: 'SYNCED',
          ),
          mode: InsertMode.insertOrReplace,
        );
      } catch (e) {
        // Silently handle duplicate insertions
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

    // Listen to legacy read ack for backwards compat
    _socketClient.readAckStream.listen((data) async {
      try {
        final messageId = data['message_id'] as String;
        await (_db.update(_db.localMessages)
              ..where((t) => t.id.equals(messageId)))
            .write(const LocalMessagesCompanion(syncStatus: Value('READ')));
      } catch (e) {
        // Silently handle
      }
    });

    // Hook reconnection callback for offline sync
    _socketClient.onConnectCallback = () {
      syncOfflineQueue();
      requestSyncSinceLastMessage();
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

  /// Syncs chat messages history from REST API
  Future<void> syncMessagesFromApi(String chatId) async {
    final response = await _apiClient.dio.get<List<dynamic>>('${ApiEndpoints.messages}/$chatId');
    final data = response.data!;

    final List<Map<String, dynamic>> decryptedMsgs = [];
    for (final item in data) {
      final msg = item as Map<String, dynamic>;
      final rawContent = msg['content'] as String;
      final decryptedContent = await decryptMessageContent(chatId, rawContent, msg['message_type'] as String);
      decryptedMsgs.add({
        ...msg,
        'decrypted_content': decryptedContent,
      });
    }

    await _db.batch((batch) {
      for (final msg in decryptedMsgs) {
        final sender = msg['sender'] as Map<String, dynamic>;

        batch.insert(
          _db.localMessages,
          LocalMessagesCompanion.insert(
            id: msg['id'] as String,
            chatId: msg['chat_id'] as String,
            senderId: sender['id'] as String,
            content: msg['decrypted_content'] as String,
            messageType: msg['message_type'] as String,
            mediaId: Value(msg['media_id'] as String?),
            replyToId: Value(msg['reply_to_id'] as String?),
            createdAt: DateTime.parse(msg['created_at'] as String),
            syncStatus: 'SYNCED',
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
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
        // Fallback to sending plaintext if encryption engine fails
      }
    }

    // 3. Transmit via WebSockets with acknowledgement
    if (_socketClient.isConnected) {
      _socketClient.sendMessageWithAck({
        'id': messageId,
        'chat_id': chatId,
        'content': payloadToSend,
        'message_type': 'TEXT',
      }, (ack) async {
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
              payload: json.encode({
                'id': messageId,
                'chat_id': chatId,
                'content': payloadToSend,
                'message_type': 'TEXT',
              }),
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
              final msgId = payload['id'] as String?;
              if (msgId != null) {
                await (_db.update(_db.localMessages)
                      ..where((t) => t.id.equals(msgId)))
                    .write(const LocalMessagesCompanion(syncStatus: Value('SENT')));
              }
            }
          });
        } else if (item.actionType == 'MARK_READ') {
          _socketClient.sendReadReceipt(
            payload['message_id'] as String,
            payload['chat_id'] as String,
            payload['sender_id'] as String,
          );
        }

        // Remove from queue after processing
        await (_db.delete(_db.syncQueue)..where((t) => t.id.equals(item.id))).go();
      } catch (e) {
        // If processing fails, leave in queue for next attempt
      }
    }
  }

  /// Reconciles messages missed while the device was offline
  Future<void> requestSyncSinceLastMessage() async {
    // Find the most recent message timestamp in local DB
    final latestMsg = await (_db.select(_db.localMessages)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();

    final lastSeen = latestMsg?.createdAt ?? DateTime.now().subtract(const Duration(days: 7));

    _socketClient.requestSync(lastSeen, (response) async {
      if (response is Map<String, dynamic> && response['success'] == true) {
        final messages = response['messages'] as List<dynamic>? ?? [];
        await _db.batch((batch) {
          for (final item in messages) {
            final msg = item as Map<String, dynamic>;
            final sender = msg['sender'] as Map<String, dynamic>;
            batch.insert(
              _db.localMessages,
              LocalMessagesCompanion.insert(
                id: msg['id'] as String,
                chatId: msg['chat_id'] as String,
                senderId: sender['id'] as String,
                content: msg['content'] as String,
                messageType: msg['message_type'] as String,
                mediaId: Value(msg['media_id'] as String?),
                replyToId: Value(msg['reply_to_id'] as String?),
                createdAt: DateTime.parse(msg['created_at'] as String),
                syncStatus: 'SYNCED',
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        });
      }
    });
  }

  /// Marks all messages in a chat from other users as read and sends read receipts
  Future<void> markChatAsRead(String chatId) async {
    final myUserId = await _secureStorage.getUserId() ?? '';

    // Get unread messages from others that haven't been marked as READ yet
    final unreadMessages = await (_db.select(_db.localMessages)
          ..where((t) => t.chatId.equals(chatId) &
              t.senderId.equals(myUserId).not() &
              t.syncStatus.equals('READ').not()))
        .get();

    for (final msg in unreadMessages) {
      if (_socketClient.isConnected) {
        _socketClient.sendReadReceipt(msg.id, chatId, msg.senderId);
      } else {
        // Queue for offline
        await _db.into(_db.syncQueue).insert(
              SyncQueueCompanion.insert(
                actionType: 'MARK_READ',
                payload: json.encode({
                  'message_id': msg.id,
                  'chat_id': chatId,
                  'sender_id': msg.senderId,
                }),
              ),
            );
      }
    }
  }

  /// Encrypts and sends a media attachment (photo, video, voice note, document)
  Future<void> sendMediaMessage(String chatId, File file, String type) async {
    final bytes = await file.readAsBytes();
    
    // 1. Client-side encrypt file bytes
    final encryptionResult = await CryptoService.encryptFile(bytes);
    final encryptedFileBytes = encryptionResult['encryptedBytes'] as Uint8List;
    final fileKey = encryptionResult['key'] as String;
    final fileIv = encryptionResult['iv'] as String;

    // 2. Request pre-signed upload URL from backend
    final filename = file.path.split('/').last;
    final uploadResponse = await _apiClient.dio.get<Map<String, dynamic>>(
      ApiEndpoints.mediaUpload,
      queryParameters: {
        'filename': filename,
        'mime_type': _getMimeType(file.path, type),
        'file_size': encryptedFileBytes.length,
      },
    );

    final uploadDetails = uploadResponse.data as Map<String, dynamic>;
    final uploadUrl = uploadDetails['upload_url'] as String;
    final mediaId = uploadDetails['media_id'] as String;

    // 3. Upload encrypted bytes directly to MinIO
    await Dio().put<dynamic>(
      uploadUrl,
      data: Stream.fromIterable([encryptedFileBytes]),
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

    // 7. Send payload via WebSocket with ack
    if (_socketClient.isConnected) {
      _socketClient.sendMessageWithAck({
        'id': messageId,
        'chat_id': chatId,
        'content': payloadToSend,
        'message_type': type,
        'media_id': mediaId,
      }, (ack) async {
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
              payload: json.encode({
                'id': messageId,
                'chat_id': chatId,
                'content': payloadToSend,
                'message_type': type,
                'media_id': mediaId,
              }),
            ),
          );
    }
  }

  /// Downloads, decrypts, and saves an encrypted media file to local device path
  Future<File> downloadAndDecryptMedia({
    required String mediaId,
    required String keyBase64,
    required String ivBase64,
    required String filename,
  }) async {
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

    // 4. Save file to app documents folder
    final tempDir = await Directory.systemTemp.createTemp();
    final localFile = File('${tempDir.path}/$filename');
    await localFile.writeAsBytes(decryptedBytes);

    return localFile;
  }

  String _getMimeType(String path, String type) {
    if (type == 'IMAGE') return 'image/jpeg';
    if (type == 'VIDEO') return 'video/mp4';
    if (type == 'AUDIO') return 'audio/aac';
    return 'application/octet-stream';
  }
}

