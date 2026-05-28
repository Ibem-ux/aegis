import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'chats_providers.dart';
import '../../auth/presentation/auth_providers.dart';
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
    ref.read(socketClientProvider).connect();
    // Sync chats from server
    ref.read(chatsRepositoryProvider).syncChatsWithApi();
  }

  Future<void> _loadMyProfile() async {
    final user = await _storage.getUsername();
    final dev = await _storage.getDeviceId();
    setState(() {
      _myUsername = user ?? 'Unknown';
      _myDeviceId = dev ?? 'Unknown';
    });
  }

  void _showNewChatDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Start Private Chat'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter recipient username',
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
                final username = controller.text.trim();
                if (username.isEmpty) return;
                Navigator.pop(context);

                try {
                  final chatId = await ref.read(chatsRepositoryProvider).startChat(username);
                  if (mounted) {
                    context.push('/chat/$chatId?name=$username');
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to start chat: $e')),
                    );
                  }
                }
              },
              child: const Text('Start'),
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
        title: Text(_currentIndex == 0 ? 'Aegis Chats' : 'Node Settings'),
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
                  separatorBuilder: (_, __) => Divider(color: AegisTheme.cardColor.withOpacity(0.5), height: 1),
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AegisTheme.cardColor,
                        child: const Icon(Icons.person, color: AegisTheme.accentCyan),
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
                        context.push('/chat/${chat.id}?name=${chat.recipientDisplayName}');
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
              onPressed: _showNewChatDialog,
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AegisTheme.darkBackground,
                  child: const Icon(Icons.security, size: 40, color: AegisTheme.accentCyan),
                ),
                const SizedBox(height: 16),
                Text(_myUsername, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('Secure Profile', style: TextStyle(color: AegisTheme.textSecondary)),
              ],
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
                leading: const Icon(Icons.qr_code, color: AegisTheme.accentGreen),
                title: const Text('Setup 2FA'),
                subtitle: const Text('Configure Google Authenticator'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/totp-setup'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AegisTheme.errorRed),
                title: const Text('Lock Node Session'),
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
}
