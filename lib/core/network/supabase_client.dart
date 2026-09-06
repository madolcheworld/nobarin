import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/api_constants.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  SupabaseClient get client {
    return Supabase.instance.client;
  }

  Future<void> initialize({
    String? url,
    String? anonKey,
  }) async {
    if (_initialized) return;

    final targetUrl = url ?? ApiConstants.supabaseUrl;
    final targetAnonKey = anonKey ?? ApiConstants.supabaseAnonKey;

    try {
      await Supabase.initialize(
        url: targetUrl,
        anonKey: targetAnonKey, // ignore: deprecated_member_use
        realtimeClientOptions: const RealtimeClientOptions(
          eventsPerSecond: 10,
        ),
      );
      _initialized = true;
      debugPrint('[SupabaseService] Initialized successfully with $targetUrl');
    } catch (e) {
      debugPrint('[SupabaseService] Initialization failed or mock mode: $e');
    }
  }
}
