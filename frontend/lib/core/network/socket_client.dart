import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../secure_storage/secure_storage.dart';
import 'api_endpoints.dart';

class SocketClient {
  io.Socket? _socket;
  final SecureStorage _secureStorage = SecureStorage();
  
  // Streams for UI event consumption
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _presenceController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _readAckController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get presenceStream => _presenceController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get readAckStream => _readAckController.stream;
  /// Unified delivery status stream (DELIVERED / READ)
  Stream<Map<String, dynamic>> get statusStream => _statusController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Optional callback triggered after successful connection (for triggering sync)
  void Function()? onConnectCallback;

  /// Establishes WebSocket connection
  Future<void> connect() async {
    if (_socket != null && _socket!.connected) return;

    final token = await _secureStorage.getAccessToken();
    if (token == null) return;

    _socket = io.io(
      ApiEndpoints.wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token}) // Passes JWT auth handshake
          .build(),
    );

    _socket!.onConnect((_) {
      // Trigger external sync callback (e.g., offline queue processing)
      onConnectCallback?.call();
    });

    _socket!.onDisconnect((_) {});

    // Listeners for standard chat events
    _socket!.on('message:receive', (data) {
      if (data is Map<String, dynamic>) {
        _messageController.add(data);
      }
    });

    _socket!.on('presence:update', (data) {
      if (data is Map<String, dynamic>) {
        _presenceController.add(data);
      }
    });

    _socket!.on('typing:indicator', (data) {
      if (data is Map<String, dynamic>) {
        _typingController.add(data);
      }
    });

    _socket!.on('message:read_ack', (data) {
      if (data is Map<String, dynamic>) {
        _readAckController.add(data);
      }
    });

    _socket!.on('message:status', (data) {
      if (data is Map<String, dynamic>) {
        _statusController.add(data);
      }
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  /// Sends raw message payload via socket
  void sendMessage(Map<String, dynamic> payload) {
    if (isConnected) {
      _socket!.emit('message:send', payload);
    }
  }

  /// Sends a message with acknowledgement callback from server
  void sendMessageWithAck(Map<String, dynamic> payload, Function(dynamic) ackCallback) {
    if (isConnected) {
      _socket!.emitWithAck('message:send', payload, ack: ackCallback);
    }
  }

  /// Broadcasts typing indicator status
  void sendTypingIndicator(String chatId, bool isTyping) {
    if (isConnected) {
      _socket!.emit(isTyping ? 'typing:start' : 'typing:stop', {'chat_id': chatId});
    }
  }

  /// Acknowledges message as read
  void sendReadReceipt(String messageId, String chatId, String senderId) {
    if (isConnected) {
      _socket!.emit('message:read', {
        'message_id': messageId,
        'chat_id': chatId,
        'sender_id': senderId,
      });
    }
  }

  /// Batch acknowledges messages as delivered
  void sendDeliveryReceipts(List<Map<String, dynamic>> messageIds) {
    if (isConnected && messageIds.isNotEmpty) {
      _socket!.emit('message:delivered', {
        'message_ids': messageIds,
      });
    }
  }

  /// Requests messages missed while offline, returns via ack callback
  void requestSync(DateTime lastSeen, Function(dynamic) callback) {
    if (isConnected) {
      _socket!.emitWithAck('sync:request', {
        'last_sync_timestamp': lastSeen.toIso8601String(),
      }, ack: callback);
    }
  }

  void dispose() {
    _messageController.close();
    _presenceController.close();
    _typingController.close();
    _readAckController.close();
    _statusController.close();
    disconnect();
  }
}

