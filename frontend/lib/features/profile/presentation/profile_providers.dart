import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/user_model.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/profile_repository.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ProfileRepository(apiClient);
});

final currentUserProfileProvider = FutureProvider.autoDispose<UserModel>((ref) async {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.getMe();
});

final activeSessionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final repository = ref.watch(profileRepositoryProvider);
  return repository.getSessions();
});
