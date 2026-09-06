import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/auth_repository.dart';
import '../domain/user_profile.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } catch (_) {}
  return AuthRepository(supabase: client);
});

class AuthController extends StateNotifier<AsyncValue<UserProfile?>> {
  final AuthRepository _repository;

  AuthController(this._repository) : super(const AsyncValue.loading()) {
    loadInitialProfile();
  }

  Future<void> loadInitialProfile() async {
    try {
      final cached = await _repository.getCachedProfile();
      state = AsyncValue.data(cached);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<UserProfile?> loginAsGuest({
    required String username,
    required String avatarUrl,
  }) async {
    state = const AsyncValue.loading();
    try {
      final profile = await _repository.saveProfile(
        username: username,
        avatarUrl: avatarUrl,
      );
      state = AsyncValue.data(profile);
      return profile;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  Future<void> logout() async {
    await _repository.clearSession();
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<UserProfile?>>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});
