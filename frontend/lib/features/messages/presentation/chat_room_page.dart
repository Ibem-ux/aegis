import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'messages_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/local_database.dart';
import '../../../core/secure_storage/secure_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Compresses image bytes using native flutter_image_compress on mobile,
/// falling back to the pure-Dart `image` package on web.
Future<Uint8List> _compressImageBytes(Uint8List originalBytes) async {
  if (kIsWeb) {
    final image = img.decodeImage(originalBytes);
    if (image == null) return originalBytes;
    final img.Image resized;
    if (image.width > 1024) {
      resized = img.copyResize(image, width: 1024);
    } else {
      resized = image;
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  final result = await FlutterImageCompress.compressWithList(
    originalBytes,
    minWidth: 1024,
    minHeight: 1024,
    quality: 82,
    format: CompressFormat.jpeg,
  );
  return result;
}

class ChatRoomPage extends ConsumerStatefulWidget {
  final String chatId;
  final String recipientName;
  final String? recipientAvatarUrl;

  const ChatRoomPage({super.key, required this.chatId, required this.recipientName, this.recipientAvatarUrl});

  @override
  ConsumerState<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends ConsumerState<ChatRoomPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final SecureStorage _storage = SecureStorage();
  final AudioRecorder _audioRecorder = AudioRecorder();
  String _myUserId = '';
  bool _isRecipientTyping = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _loadMyUserId();
    ref.read(messagesRepositoryProvider).initSocketListeners();
    ref.read(messagesRepositoryProvider).syncMessagesFromApi(widget.chatId);
    _setupSocketListeners();
    ref.read(messagesRepositoryProvider).markChatAsRead(widget.chatId);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadMyUserId() async {
    final uid = await _storage.getUserId();
    setState(() => _myUserId = uid ?? '');
  }

  void _setupSocketListeners() {
    ref.read(socketClientProvider).typingStream.listen((data) {
      if (data['chat_id'] == widget.chatId && mounted) {
        setState(() => _isRecipientTyping = (data['is_typing'] as bool?) ?? false);
      }
    });

    ref.read(socketClientProvider).messageStream.listen((data) async {
      if (data['chat_id'] == widget.chatId) {
        await ref.read(messagesRepositoryProvider).markChatAsRead(widget.chatId);
      }
    });
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    ref.read(messagesRepositoryProvider).sendTextMessage(widget.chatId, text);
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  /// Shows a glassmorphic dialog when a file exceeds the size limit.
  /// For images: offers Cancel or Compress.
  /// For video/audio: explains the file is too large and offers only Cancel.
  Future<bool?> _showCompressionDialog(int sizeInBytes, String mediaType) {
    final sizeMb = (sizeInBytes / (1024 * 1024)).toStringAsFixed(1);
    final bool isCompressible = mediaType == 'IMAGE';
    final limit = mediaType == 'VIDEO' ? '10.0' : mediaType == 'AUDIO' ? '5.0' : '2.0';

    final String body = isCompressible
        ? 'This image is $sizeMb MB, exceeding the $limit MB limit.\n\nWould you like to compress it on your device before sending?'
        : 'This file is $sizeMb MB, exceeding the $limit MB limit.\n\nPlease select a smaller file or compress it externally before sending.';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: AegisTheme.darkBackground.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15, spreadRadius: 2)],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              Icon(
                isCompressible ? Icons.photo_size_select_large : Icons.warning_amber_rounded,
                size: 48,
                color: isCompressible ? AegisTheme.accentCyan : AegisTheme.errorRed,
              ),
              const SizedBox(height: 16),
              Text(
                isCompressible ? 'Large Image Detected' : 'File Too Large',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AegisTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              Text(body, style: const TextStyle(color: AegisTheme.textSecondary, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(isCompressible ? 'Cancel' : 'Got It', style: const TextStyle(color: AegisTheme.textSecondary)),
                  ),
                  if (isCompressible)
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.compress, size: 18),
                      label: const Text('Compress'),
                    ),
                ],
              ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAndSendMedia({required bool isVideo}) async {
    if (kIsWeb) return;
    final picker = ImagePicker();
    final pickedFile = isVideo 
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
        
    if (pickedFile == null) return;

    Uint8List bytes = await pickedFile.readAsBytes();
    final maxOriginalSize = isVideo ? 10 * 1024 * 1024 : 2 * 1024 * 1024;
    XFile fileToSend = pickedFile;

    if (bytes.length > maxOriginalSize) {
      if (isVideo) {
        // Video compression is not supported on-device; show info dialog and abort.
        await _showCompressionDialog(bytes.length, 'VIDEO');
        return;
      }
      // Image: offer the choice to compress
      final shouldCompress = await _showCompressionDialog(bytes.length, 'IMAGE');
      if (shouldCompress == null || !shouldCompress) return;

      bytes = await compute(_compressImageBytes, bytes);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${pickedFile.name.split('.').first}_compressed.jpg');
      await tempFile.writeAsBytes(bytes);
      fileToSend = XFile(tempFile.path);
    }

    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encrypting and uploading...')));
    try {
      await ref.read(messagesRepositoryProvider).sendMediaMessage(widget.chatId, fileToSend, isVideo ? 'VIDEO' : 'IMAGE');
      await ref.read(messagesRepositoryProvider).syncMessagesFromApi(widget.chatId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Future<void> _pickAndSendAudio() async {
    if (kIsWeb) return;
    FilePickerResult? result = await FilePicker.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final file = XFile(result.files.single.path!);
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        final shouldCompress = await _showCompressionDialog(bytes.length, 'AUDIO');
        if (shouldCompress == null || !shouldCompress) return;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encrypting and uploading audio...')));
      try {
        await ref.read(messagesRepositoryProvider).sendMediaMessage(widget.chatId, file, 'AUDIO');
        await ref.read(messagesRepositoryProvider).syncMessagesFromApi(widget.chatId);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (kIsWeb) return;
    if (_isRecording) {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        final file = XFile(path);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encrypting and uploading voice note...')));
        try {
          await ref.read(messagesRepositoryProvider).sendMediaMessage(widget.chatId, file, 'RECORDING');
          await ref.read(messagesRepositoryProvider).syncMessagesFromApi(widget.chatId);
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
        }
      }
    } else {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/record_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000), path: path);
        setState(() {
          _isRecording = true;
        });
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission required')));
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: AegisTheme.darkBackground.withValues(alpha: 0.75),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: Colors.white10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.image, color: AegisTheme.accentCyan),
                      title: const Text('Photo Gallery', style: TextStyle(color: AegisTheme.textPrimary)),
                      onTap: () { Navigator.pop(ctx); _pickAndSendMedia(isVideo: false); },
                    ),
                    ListTile(
                      leading: const Icon(Icons.videocam, color: AegisTheme.accentBlue),
                      title: const Text('Video Upload', style: TextStyle(color: AegisTheme.textPrimary)),
                      onTap: () { Navigator.pop(ctx); _pickAndSendMedia(isVideo: true); },
                    ),
                    ListTile(
                      leading: const Icon(Icons.audiotrack, color: AegisTheme.accentGreen),
                      title: const Text('Music / Audio', style: TextStyle(color: AegisTheme.textPrimary)),
                      onTap: () { Navigator.pop(ctx); _pickAndSendAudio(); },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleMediaPlayback(LocalMessage message, String type) async {
    if (kIsWeb) return;

    // Show a loading spinner while downloading and decrypting
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));

    try {
      final meta = json.decode(message.content) as Map<String, dynamic>;
      final Uint8List bytes = await ref.read(messagesRepositoryProvider).downloadAndDecryptMedia(
            mediaId: message.mediaId!,
            keyBase64: meta['file_key'] as String,
            ivBase64: meta['file_iv'] as String,
            filename: meta['filename'] as String,
          );

      // Dismiss the loading spinner
      if (mounted) Navigator.of(context).pop();

      if (type == 'AUDIO' || type == 'RECORDING') {
        if (mounted) {
          unawaited(showDialog<void>(
            context: context,
            builder: (_) => _AudioPlayerDialog(bytes: bytes),
          ));
        }
      } else if (type == 'VIDEO') {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/temp_vid_${message.mediaId}.mp4');
        await tempFile.writeAsBytes(bytes);
        if (mounted) {
          unawaited(showDialog<void>(
            context: context,
            builder: (_) => _VideoPlayerDialog(file: tempFile),
          ));
        }
      }
    } catch (e) {
      // Dismiss loading spinner on error
      if (mounted) Navigator.of(context).pop();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to decrypt attachment: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesState = ref.watch(chatMessagesProvider(widget.chatId));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.recipientAvatarUrl != null && widget.recipientAvatarUrl!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AegisTheme.cardColor,
                  backgroundImage: CachedNetworkImageProvider(widget.recipientAvatarUrl!),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AegisTheme.cardColor,
                  child: Text(
                    widget.recipientName.isNotEmpty ? widget.recipientName[0].toUpperCase() : '?',
                    style: const TextStyle(color: AegisTheme.accentCyan, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.recipientName, style: const TextStyle(fontSize: 16)),
                const Text('Encrypted Channel', style: TextStyle(fontSize: 11, color: AegisTheme.accentGreen, fontWeight: FontWeight.bold)),
              ],
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
                  return const Center(child: Text('Say hello! Tap below to start.', style: TextStyle(color: AegisTheme.textSecondary)));
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
                child: Text('${widget.recipientName} is typing...', style: const TextStyle(fontSize: 12, color: AegisTheme.accentCyan, fontStyle: FontStyle.italic)),
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
            else if (message.messageType == 'VIDEO')
              _buildVideoAttachment(message)
            else if (message.messageType == 'AUDIO' || message.messageType == 'RECORDING')
              _buildAudioAttachment(message)
            else
              Text(message.content, style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.6)),
                ),
                if (isMe) ...[const SizedBox(width: 4), _buildStatusIcon(message.syncStatus)],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageAttachment(LocalMessage message) {
    return _buildGenericMediaAttachment(message, Icons.image, 'View Image', () async {
      // Show loading spinner while downloading and decrypting
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ));
      try {
        final meta = json.decode(message.content) as Map<String, dynamic>;
        final Uint8List result = await ref.read(messagesRepositoryProvider).downloadAndDecryptMedia(
              mediaId: message.mediaId!,
              keyBase64: meta['file_key'] as String,
              ivBase64: meta['file_iv'] as String,
              filename: meta['filename'] as String,
            );
        if (mounted) Navigator.of(context).pop(); // dismiss spinner
        if (mounted) unawaited(showDialog<void>(context: context, builder: (_) => Dialog(child: Image.memory(result))));
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // dismiss spinner
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    });
  }

  Widget _buildVideoAttachment(LocalMessage message) {
    return _buildGenericMediaAttachment(message, Icons.videocam, 'Play Video', () => _handleMediaPlayback(message, 'VIDEO'));
  }

  Widget _buildAudioAttachment(LocalMessage message) {
    final label = message.messageType == 'RECORDING' ? 'Play Voice Note' : 'Play Audio';
    return _buildGenericMediaAttachment(message, Icons.audiotrack, label, () => _handleMediaPlayback(message, message.messageType));
  }

  Widget _buildGenericMediaAttachment(LocalMessage message, IconData icon, String label, VoidCallback onTap) {
    return Container(
      width: 200,
      height: 120,
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AegisTheme.textSecondary, size: 40),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.play_circle_fill, size: 16),
              label: Text(label),
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
      decoration: const BoxDecoration(color: AegisTheme.darkBackground),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: AegisTheme.accentCyan),
              onPressed: _showAttachmentOptions,
            ),
            IconButton(
              icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic, color: _isRecording ? AegisTheme.errorRed : AegisTheme.textSecondary),
              onPressed: _toggleRecording,
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
                  ref.read(socketClientProvider).sendTypingIndicator(widget.chatId, text.isNotEmpty);
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
      case 'PENDING': return Icon(Icons.access_time, size: 14, color: Colors.white.withValues(alpha: 0.5));
      case 'SENT': return const Icon(Icons.done, size: 14, color: Colors.white70);
      case 'DELIVERED': return const Icon(Icons.done_all, size: 14, color: Colors.white70);
      case 'READ': return const Icon(Icons.done_all, size: 14, color: AegisTheme.accentCyan);
      default: return const Icon(Icons.done, size: 14, color: Colors.white70);
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

// Dialogs for playback
class _AudioPlayerDialog extends StatefulWidget {
  final Uint8List bytes;
  const _AudioPlayerDialog({required this.bytes});
  @override
  State<_AudioPlayerDialog> createState() => _AudioPlayerDialogState();
}
class _AudioPlayerDialogState extends State<_AudioPlayerDialog> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  
  @override
  void initState() {
    super.initState();
    _player.setSourceBytes(widget.bytes);
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
  }
  @override
  void dispose() { _player.dispose(); super.dispose(); }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AegisTheme.darkBackground,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audiotrack, size: 48, color: AegisTheme.accentCyan),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, size: 48),
                  color: AegisTheme.accentBlue,
                  onPressed: () { _isPlaying ? _player.pause() : _player.resume(); },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final File file;
  const _VideoPlayerDialog({required this.file});
  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}
class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late VideoPlayerController _controller;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) { if (mounted) setState(() {}); _controller.play(); });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      child: _controller.value.isInitialized
          ? AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            )
          : const Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator()),
    );
  }
}
