import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/local_database.dart';
import '../data/messages_repository.dart';

final messagesRepositoryProvider = Provider<MessagesRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  final socketClient = ref.watch(socketClientProvider);
  return MessagesRepository(db, apiClient, socketClient);
});

final chatMessagesProvider = StreamProvider.family<List<LocalMessage>, String>((ref, chatId) {
  final repository = ref.watch(messagesRepositoryProvider);
  return repository.watchMessages(chatId);
});
