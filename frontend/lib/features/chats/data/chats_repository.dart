import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/database/local_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/secure_storage/secure_storage.dart';
import '../../../core/security/crypto_service.dart';

class ChatsRepository {
  final AppDatabase _db;
  final ApiClient _apiClient;

  ChatsRepository(this._db, this._apiClient);

  /// Watches all local chats from SQLite database (reactively updates UI)
  Stream<List<LocalChat>> watchLocalChats() {
    return (_db.select(_db.localChats)
          ..orderBy([
            (t) => OrderingTerm(expression: t.lastMessageAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  /// Syncs chats list from backend API to local DB
  Future<void> syncChatsWithApi() async {
    final response = await _apiClient.dio.get<List<dynamic>>(ApiEndpoints.chats);
    final data = response.data!;

    final List<Map<String, dynamic>> decryptedChats = [];
    for (final item in data) {
      final chat = item as Map<String, dynamic>;
      final chatId = chat['chat_id'] as String;
      final rawPreview = chat['last_message_preview'] as String?;
      
      final decryptedPreview = await _decryptMessagePreview(chatId, rawPreview);
      decryptedChats.add({
        ...chat,
        'decrypted_preview': decryptedPreview,
      });
    }

    await _db.batch((batch) {
      for (final chat in decryptedChats) {
        final recipient = chat['recipient'] as Map<String, dynamic>;

        batch.insert(
          _db.localChats,
          LocalChatsCompanion.insert(
            id: chat['chat_id'] as String,
            recipientId: recipient['id'] as String,
            recipientUsername: recipient['username'] as String,
            recipientDisplayName: recipient['display_name'] as String,
            recipientAvatarUrl: Value(recipient['avatar_url'] as String?),
            lastMessageAt: DateTime.parse(chat['last_message_at'] as String),
            lastMessagePreview: Value(chat['decrypted_preview'] as String?),
            archived: Value(chat['archived'] as bool? ?? false),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Decrypts encrypted message preview using E2EE keys
  Future<String?> _decryptMessagePreview(String chatId, String? rawContent) async {
    if (rawContent == null || rawContent.isEmpty) {
      return rawContent;
    }

    if (!rawContent.startsWith('{"') || !rawContent.contains('"ciphertext"')) {
      return rawContent;
    }

    try {
      final payload = json.decode(rawContent) as Map<String, dynamic>;
      final senderDeviceId = payload['sender_device_id'] as String;

      final secureStorage = SecureStorage();
      final myPrivateKey = await secureStorage.getDevicePrivateKey();
      final myDeviceId = await secureStorage.getDeviceId();

      if (myPrivateKey == null || myDeviceId == null) {
        return '[Encrypted Message]';
      }

      // Try to load keys if missing from cache
      if (!CryptoService.chatKeys.containsKey(chatId) || 
          !CryptoService.chatKeys[chatId]!.containsKey(senderDeviceId)) {
        await _loadChatKeys(chatId);
      }

      final senderPublicKey = CryptoService.chatKeys[chatId]?[senderDeviceId];
      if (senderPublicKey == null) {
        return '[Encrypted Message]';
      }

      return await CryptoService.decryptPayload(
        payloadJson: rawContent,
        myPrivateKeyBase64: myPrivateKey,
        myDeviceId: myDeviceId,
        senderPublicKeyBase64: senderPublicKey,
      );
    } catch (e) {
      return '[Decryption Failed]';
    }
  }

  /// Fetches participant public keys from server and populates cache
  Future<void> _loadChatKeys(String chatId) async {
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

  /// Generates a new secure invite link
  Future<Map<String, dynamic>> generateInviteLink({int? maxUses, String? label}) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      ApiEndpoints.chatInvites,
      data: {
        if (maxUses != null) 'max_uses': maxUses,
        if (label != null) 'label': label,
      },
    );
    return response.data!;
  }

  /// Retrieves active invite links created by the user
  Future<List<Map<String, dynamic>>> getMyInviteLinks() async {
    final response = await _apiClient.dio.get<List<dynamic>>(ApiEndpoints.chatInvites);
    return response.data!.cast<Map<String, dynamic>>();
  }

  /// Toggles the active status of an invite link
  Future<void> toggleInviteLink(String inviteId, bool isActive) async {
    await _apiClient.dio.patch<dynamic>(
      '${ApiEndpoints.chatInvites}/$inviteId',
      data: {'is_active': isActive},
    );
  }

  /// Permanently deletes an invite link
  Future<void> deleteInviteLink(String inviteId) async {
    await _apiClient.dio.delete<dynamic>('${ApiEndpoints.chatInvites}/$inviteId');
  }

  /// Accepts an invite link and establishes a new conversation
  Future<String> acceptInviteLink(String token) async {
    // 1. Accept on backend
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      ApiEndpoints.acceptInvite,
      data: {'token': token},
    );
    final data = response.data!;
    final chatId = data['chat_id'] as String;
    
    // We can run a sync to ensure we have the latest chat metadata including
    // the new recipient's display name and avatar (which isn't strictly returned
    // by the accept endpoint, but is available if we sync).
    // The server does return creator_id and creator_keys, but the simplest 
    // way to get full participant details for local DB is to sync all chats.
    await syncChatsWithApi();

    return chatId;
  }
}
