import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../core/errors/failures.dart';
import '../domain/user_profile.dart';

class AuthRepository {
  final SupabaseClient? supabase;

  AuthRepository({this.supabase});

  static const String _profileKey = 'cached_user_profile';

  /// Retrieves cached user profile from SharedPreferences
  Future<UserProfile?> getCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Object? raw = prefs.get(_profileKey);
      if (raw is String) {
        final Map<String, dynamic> data = jsonDecode(raw);
        return UserProfile.fromJson(data);
      } else if (raw is Map) {
        return UserProfile.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('[AuthRepository] Error reading cached profile: $e');
    }
    return null;
  }

  /// Saves user profile to local cache and Supabase backend
  Future<UserProfile> saveProfile({
    required String username,
    required String avatarUrl,
  }) async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      throw AuthFailure('Gagal mengakses penyimpanan lokal perangkat.', e);
    }

    String userId = '';
    // Attempt Supabase anonymous sign-in if client is present
    if (supabase != null) {
      try {
        final currentSession = supabase!.auth.currentSession;
        if (currentSession != null) {
          userId = currentSession.user.id;
        } else {
          final authResponse = await supabase!.auth.signInAnonymously();
          userId = authResponse.user?.id ?? '';
        }

        if (userId.isEmpty) {
          final cached = await getCachedProfile();
          userId = cached?.id ?? const Uuid().v4();
        }

        // Upsert to Supabase profiles table
        await supabase!.from('profiles').upsert({
          'id': userId,
          'username': username,
          'avatar_url': avatarUrl,
          'is_guest': true,
        }).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[AuthRepository] Supabase auth/profile sync note: $e');
        // Preserve userId if obtained from Supabase Auth; otherwise fallback to cached/UUID
        if (userId.isEmpty) {
          final currentAuthUser = supabase?.auth.currentUser;
          if (currentAuthUser != null) {
            userId = currentAuthUser.id;
          } else {
            final cached = await getCachedProfile();
            userId = cached?.id ?? const Uuid().v4();
          }
        }
      }
    } else {
      final cached = await getCachedProfile();
      userId = cached?.id ?? const Uuid().v4();
    }

    final profile = UserProfile(
      id: userId,
      username: username,
      avatarUrl: avatarUrl,
      isGuest: true,
      createdAt: DateTime.now(),
    );

    // Cache locally
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    return profile;
  }

  /// Deletes user profile and hosted rooms from backend and clears local session
  Future<void> deleteAccount() async {
    try {
      final cached = await getCachedProfile();
      final userId = cached?.id ?? supabase?.auth.currentUser?.id;
      if (userId != null && supabase != null) {
        // Delete user's hosted rooms
        try {
          await supabase!
              .from('rooms')
              .delete()
              .eq('host_id', userId)
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('[AuthRepository] Error deleting user rooms: $e');
        }

        // Delete user profile
        try {
          await supabase!
              .from('profiles')
              .delete()
              .eq('id', userId)
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('[AuthRepository] Error deleting user profile: $e');
        }
      }
    } catch (e) {
      debugPrint('[AuthRepository] Error during deleteAccount: $e');
    } finally {
      await clearSession();
    }
  }

  /// Clears profile and session
  Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profileKey);
      if (supabase != null) {
        await supabase!.auth.signOut();
      }
    } catch (e) {
      debugPrint('[AuthRepository] Error clearing session: $e');
    }
  }
}
