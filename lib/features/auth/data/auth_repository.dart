import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../domain/user_profile.dart';

class AuthRepository {
  final SupabaseClient? supabase;

  AuthRepository({this.supabase});

  static const String _profileKey = 'cached_user_profile';

  /// Retrieves cached user profile from SharedPreferences
  Future<UserProfile?> getCachedProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_profileKey);
      if (jsonStr != null) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        return UserProfile.fromJson(data);
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
    final prefs = await SharedPreferences.getInstance();

    String userId;
    // Attempt Supabase anonymous sign-in if client is present
    if (supabase != null) {
      try {
        final currentSession = supabase!.auth.currentSession;
        if (currentSession != null) {
          userId = currentSession.user.id;
        } else {
          final authResponse = await supabase!.auth.signInAnonymously();
          userId = authResponse.user?.id ?? const Uuid().v4();
        }

        // Upsert to Supabase profiles table
        await supabase!.from('profiles').upsert({
          'id': userId,
          'username': username,
          'avatar_url': avatarUrl,
          'is_guest': true,
        }).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[AuthRepository] Supabase auth/profile fallback: $e');
        userId = const Uuid().v4();
      }
    } else {
      userId = const Uuid().v4();
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
