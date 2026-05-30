import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'messages_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/local_database.dart';
import '../../../core/secure_storage/secure_storage.dart';

class ChatRoomPage extends ConsumerStatefulWidget {
  final String chatId;
  final String recipientName;

  const ChatRoomPage({super.key, required this.chatId, required this.recipientName});

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final SecureStorage _storage = SecureStorage();
  String _myUserId = '';
  bool _isRecipientTyping = false;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
    // Initialize socket listeners for real-time message insertion
    ref.read(messagesRepositoryProvider).initSocketListeners();
    ref.read(messagesRepositoryProvider).syncMessagesFromApi(widget.chatId);
    _setupSocketListeners();
    // Mark all existing messages as read when entering the chat
    ref.read(messagesRepositoryProvider).markChatAsRead(widget.chatId);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMyUserId() async {
    final uid = await _storage.getUserId();
    setState(() => _myUserId = uid ?? '');
  }

  void _setupSocketListeners() {
    // Listen to typing updates (server sends snake_case 'is_typing')
    ref.read(socketClientProvider).typingStream.listen((data) {
      if (data['chat_id'] == widget.chatId && mounted) {
        setState(() {
          _isRecipientTyping = (data['is_typing'] as bool?) ?? false;
        });
      }
    });

    // When new messages arrive for this chat, mark them as read immediately
    ref.read(socketClientProvider).messageStream.listen((data) async {
      if (data['chat_id'] == widget.chatId) {
        // Messages are now inserted into SQLite by initSocketListeners
        // Just mark them as read since the user is actively viewing this chat
        await ref.read(messagesRepositoryProvider).markChatAsRead(widget.chatId);
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    ref.read(messagesRepositoryProvider).sendTextMessage(widget.chatId, text);
    
    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickAndSendImage() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image upload is not available on web')),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encrypting and uploading image...')),
      );
    }

    try {
      await ref.read(messagesRepositoryProvider).sendMediaMessage(
            widget.chatId,
            pickedFile,
            'IMAGE',
          );
      // Sync room
      await ref.read(messagesRepositoryProvider).syncMessagesFromApi(widget.chatId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesState = ref.watch(chatMessagesProvider(widget.chatId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.recipientName),
            const Text(
              'Encrypted Channel',
              style: TextStyle(fontSize: 11, color: AegisTheme.accentGreen, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesState.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Say hello! Tap below to start.', style: TextStyle(color: AegisTheme.textSecondary)),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == _myUserId;
                    return _buildMessageBubble(message, isMe);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading messages: $e')),
            ),
          ),
          if (_isRecipientTyping)
            Padding(
              padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${widget.recipientName} is typing...',
                  style: const TextStyle(fontSize: 12, color: AegisTheme.accentCyan, fontStyle: FontStyle.italic),
                ),
              ),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(LocalMessage message, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AegisTheme.accentBlue : AegisTheme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.messageType == 'IMAGE')
              _buildImageAttachment(message)
            else
              Text(
                message.content,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(message.syncStatus),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageAttachment(LocalMessage message) {
    // If media is not yet downloaded, show placeholder/download button
    return Container(
      width: 200,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image, color: AegisTheme.textSecondary, size: 40),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                if (kIsWeb) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Media download is not available on web')),
                    );
                  }
                  return;
                }
                // Parse key details (stored inside meta JSON content by sender)
                try {
                  final meta = json.decode(message.content) as Map<String, dynamic>;
                  final result = await ref.read(messagesRepositoryProvider).downloadAndDecryptMedia(
                        mediaId: message.mediaId!,
                        keyBase64: meta['file_key'] as String,
                        ivBase64: meta['file_iv'] as String,
                        filename: meta['filename'] as String,
                      );
                  
                  if (mounted) {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        child: Image.memory(result as Uint8List),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to decrypt attachment: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.download, size: 16),
              label: const Text('View Attachment'),
              style: TextButton.styleFrom(foregroundColor: AegisTheme.accentCyan),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: AegisTheme.darkBackground,
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.photo_library_outlined, color: AegisTheme.accentCyan),
              onPressed: _pickAndSendImage,
            ),
            Expanded(
              child: TextFormField(
                controller: _inputController,
                textInputAction: TextInputAction.send,
                onFieldSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Enter secure message...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onChanged: (text) {
                  ref.read(socketClientProvider).sendTypingIndicator(
                        widget.chatId,
                        text.isNotEmpty,
                      );
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send, color: AegisTheme.accentBlue),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String syncStatus) {
    switch (syncStatus) {
      case 'PENDING':
        return Icon(
          Icons.access_time,
          size: 14,
          color: Colors.white.withValues(alpha: 0.5),
        );
      case 'SENT':
        return const Icon(
          Icons.done,
          size: 14,
          color: Colors.white70,
        );
      case 'DELIVERED':
        return const Icon(
          Icons.done_all,
          size: 14,
          color: Colors.white70,
        );
      case 'READ':
        return const Icon(
          Icons.done_all,
          size: 14,
          color: AegisTheme.accentCyan,
        );
      default: // SYNCED (legacy) or unknown
        return const Icon(
          Icons.done,
          size: 14,
          color: Colors.white70,
        );
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
