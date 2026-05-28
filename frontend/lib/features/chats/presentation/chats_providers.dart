import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/local_database.dart';
import '../data/chats_repository.dart';

final chatsRepositoryProvider = Provider<ChatsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  return ChatsRepository(db, apiClient);
});

final chatsListProvider = StreamProvider<List<LocalChat>>((ref) {
  final repository = ref.watch(chatsRepositoryProvider);
  return repository.watchLocalChats();
});
