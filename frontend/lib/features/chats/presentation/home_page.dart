import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'chats_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../messages/presentation/messages_providers.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/secure_storage/secure_storage.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;
  final SecureStorage _storage = SecureStorage();
  String _myUsername = '';
  String _myDeviceId = '';

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    // Connect WebSockets when reaching home screen
    final socketClient = ref.read(socketClientProvider);
    socketClient.onConnectCallback = () {
      ref.read(messagesRepositoryProvider).syncOfflineQueue();
      ref.read(chatsRepositoryProvider).syncChatsWithApi();
    };
    socketClient.connect();
    
    // Initialize real-time listeners so we don't miss messages when on home screen
    ref.read(messagesRepositoryProvider).initSocketListeners();
    
    // Sync chats from server
    ref.read(chatsRepositoryProvider).syncChatsWithApi();

    // Listen for new chats created from accepted invites
    ref.read(socketClientProvider).chatCreatedStream.listen((_) {
      if (mounted) {
        ref.read(chatsRepositoryProvider).syncChatsWithApi();
      }
    });
  }

  Future<void> _loadMyProfile() async {
    final user = await _storage.getUsername();
    final dev = await _storage.getDeviceId();
    setState(() {
      _myUsername = user ?? 'Unknown';
      _myDeviceId = dev ?? 'Unknown';
    });
  }

  void _showStartChatSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AegisTheme.darkBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Start a Secure Chat',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AegisTheme.textPrimary)),
              const SizedBox(height: 24),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AegisTheme.cardColor,
                  child: Icon(Icons.link, color: AegisTheme.accentCyan),
                ),
                title: const Text('Generate Invite Link'),
                subtitle: const Text('Create a secure link to share with someone'),
                onTap: () {
                  Navigator.pop(context);
                  _showGenerateLinkDialog();
                },
              ),
              const Divider(color: AegisTheme.cardColor, height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AegisTheme.cardColor,
                  child: Icon(Icons.content_paste, color: AegisTheme.accentGreen),
                ),
                title: const Text('Enter Invite Link'),
                subtitle: const Text('Paste a link you received to join a chat'),
                onTap: () {
                  Navigator.pop(context);
                  _showEnterLinkDialog();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showGenerateLinkDialog() async {
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    ));

    try {
      final result = await ref.read(chatsRepositoryProvider).generateInviteLink(maxUses: 1); // Default to single use for now
      if (!mounted) return;
      Navigator.pop(context); // pop loading

      final token = result['token'] as String;

      unawaited(showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Your Invite Link'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Share this token securely. It can only be used once.',
                    style: TextStyle(color: AegisTheme.textSecondary)),
                const SizedBox(height: 16),
                TextField(
                  readOnly: true,
                  controller: TextEditingController(text: token),
                  decoration: const InputDecoration(
                    suffixIcon: Icon(Icons.copy, color: AegisTheme.textSecondary),
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: token));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Token copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done', style: TextStyle(color: AegisTheme.textPrimary)),
              ),
            ],
          );
        },
      ));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // pop loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate link: $e')),
      );
    }
  }

  void _showEnterLinkDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Invite Token'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Paste invite token here',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AegisTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final token = controller.text.trim();
                if (token.isEmpty) return;
                
                // Show loading
                unawaited(showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const Center(child: CircularProgressIndicator()),
                ));

                try {
                  final chatId = await ref.read(chatsRepositoryProvider).acceptInviteLink(token);
                  if (context.mounted) {
                    Navigator.pop(context); // pop loading
                    Navigator.pop(context); // pop enter link dialog
                    // We don't have the recipient name instantly unless we query local db, 
                    // so we pass 'Chat' and it will load from db in the ChatRoomPage if needed.
                    await context.push('/chat/$chatId?name=Chat');
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // pop loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to accept invite: $e')),
                    );
                  }
                }
              },
              child: const Text('Join Chat'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatsState = ref.watch(chatsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Aegis Chats' : 'Aegis Settings'),
        actions: _currentIndex == 0
            ? [
                IconButton(
                  icon: const Icon(Icons.sync, color: AegisTheme.accentCyan),
                  onPressed: () => ref.read(chatsRepositoryProvider).syncChatsWithApi(),
                ),
              ]
            : null,
      ),
      body: _currentIndex == 0
          ? chatsState.when(
              data: (chats) {
                if (chats.isEmpty) {
                  return const Center(
                    child: Text('No active chats. Start one below!', style: TextStyle(color: AegisTheme.textSecondary)),
                  );
                }
                return ListView.separated(
                  itemCount: chats.length,
                  separatorBuilder: (_, __) => Divider(color: AegisTheme.cardColor.withValues(alpha: 0.5), height: 1),
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    final hasAvatar = chat.recipientAvatarUrl != null && chat.recipientAvatarUrl!.isNotEmpty;
                    final initial = chat.recipientDisplayName.isNotEmpty
                        ? chat.recipientDisplayName[0].toUpperCase()
                        : '?';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AegisTheme.cardColor,
                        backgroundImage: hasAvatar
                            ? CachedNetworkImageProvider(chat.recipientAvatarUrl!)
                            : null,
                        child: hasAvatar
                            ? null
                            : Text(initial, style: const TextStyle(color: AegisTheme.accentCyan, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(chat.recipientDisplayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        chat.lastMessagePreview ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AegisTheme.textSecondary),
                      ),
                      trailing: Text(
                        DateFormat('HH:mm').format(chat.lastMessageAt),
                        style: const TextStyle(fontSize: 12, color: AegisTheme.textSecondary),
                      ),
                      onTap: () {
                        final avatarParam = hasAvatar ? '&avatar=${Uri.encodeComponent(chat.recipientAvatarUrl!)}' : '';
                        context.push('/chat/${chat.id}?name=${Uri.encodeComponent(chat.recipientDisplayName)}$avatarParam');
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error loading chats: $e')),
            )
          : _buildSettingsTab(),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              backgroundColor: AegisTheme.accentBlue,
              foregroundColor: Colors.white,
              onPressed: _showStartChatSheet,
              child: const Icon(Icons.chat_bubble_outline),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: AegisTheme.darkBackground,
        selectedItemColor: AegisTheme.accentCyan,
        unselectedItemColor: AegisTheme.textSecondary,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        GestureDetector(
          onTap: () => context.push('/profile'),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: AegisTheme.darkBackground,
                    child: Icon(Icons.security, size: 40, color: AegisTheme.accentCyan),
                  ),
                  const SizedBox(height: 16),
                  Text(_myUsername, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Secure Profile Dashboard', style: TextStyle(color: AegisTheme.accentCyan, fontSize: 13, fontWeight: FontWeight.w500)),
                      SizedBox(width: 4),
                      Icon(Icons.open_in_new, size: 14, color: AegisTheme.accentCyan),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text('DEVICE REGISTRY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AegisTheme.textSecondary)),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fingerprint, color: AegisTheme.accentCyan),
            title: const Text('Local Device ID'),
            subtitle: SelectableText(_myDeviceId, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ),
        const SizedBox(height: 24),
        const Text('SECURITY CONFIGURATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AegisTheme.textSecondary)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.link, color: AegisTheme.accentBlue),
                title: const Text('My Invite Links'),
                subtitle: const Text('Manage your active invite links'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showMyInviteLinksDialog,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.qr_code, color: AegisTheme.accentGreen),
                title: const Text('Setup 2FA'),
                subtitle: const Text('Configure Google Authenticator'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/totp-setup'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AegisTheme.errorRed),
                title: const Text('Sign Out'),
                subtitle: const Text('Logs out and clears session keys'),
                onTap: () async {
                  await ref.read(apiClientProvider).dio.post<dynamic>(ApiEndpoints.logout);
                  await _storage.clearAll();
                  if (mounted) {
                    context.go('/login');
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showMyInviteLinksDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return const _InviteLinksDialog();
      },
    );
  }
}

class _InviteLinksDialog extends ConsumerStatefulWidget {
  const _InviteLinksDialog();

  @override
  ConsumerState<_InviteLinksDialog> createState() => _InviteLinksDialogState();
}

class _InviteLinksDialogState extends ConsumerState<_InviteLinksDialog> {
  late Future<List<Map<String, dynamic>>> _linksFuture;

  @override
  void initState() {
    super.initState();
    _refreshLinks();
  }

  void _refreshLinks() {
    setState(() {
      _linksFuture = ref.read(chatsRepositoryProvider).getMyInviteLinks();
    });
  }

  Future<void> _toggleStatus(String id, bool currentStatus) async {
    try {
      await ref.read(chatsRepositoryProvider).toggleInviteLink(id, !currentStatus);
      _refreshLinks();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Future<void> _deleteLink(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Invite Link?'),
        content: const Text('This will permanently delete the link. Anyone trying to use it will fail.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text('Delete', style: TextStyle(color: AegisTheme.errorRed)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(chatsRepositoryProvider).deleteInviteLink(id);
        _refreshLinks();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('My Invite Links'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _linksFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            
            final links = snapshot.data ?? [];
            if (links.isEmpty) {
              return const Center(
                child: Text('You have no active invite links.', style: TextStyle(color: AegisTheme.textSecondary)),
              );
            }

            return ListView.builder(
              itemCount: links.length,
              itemBuilder: (context, index) {
                final link = links[index];
                final isActive = link['is_active'] as bool? ?? false;
                final maxUses = link['max_uses'];
                final useCount = link['use_count'] ?? 0;
                final id = link['id'] as String;

                return Card(
                  color: AegisTheme.darkBackground,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                (link['label'] as String?) ?? 'Invite Link', 
                                style: const TextStyle(fontWeight: FontWeight.bold)
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive ? AegisTheme.accentGreen.withValues(alpha: 0.2) : AegisTheme.errorRed.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  color: isActive ? AegisTheme.accentGreen : AegisTheme.errorRed,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Uses: $useCount${maxUses != null ? ' / $maxUses' : ''}\nToken: ${link['token']}',
                          style: const TextStyle(fontSize: 12, color: AegisTheme.textSecondary),
                        ),
                        if (!isActive)
                           const Padding(
                             padding: EdgeInsets.only(top: 4.0),
                             child: Text('⚠️ Will be auto-deleted 7 days after deactivation.', style: TextStyle(fontSize: 10, color: AegisTheme.errorRed)),
                           ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Switch(
                              value: isActive,
                              onChanged: (val) => _toggleStatus(id, !val),
                              activeThumbColor: AegisTheme.accentGreen,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AegisTheme.errorRed),
                              onPressed: () => _deleteLink(id),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
