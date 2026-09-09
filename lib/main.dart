import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/network/supabase_client.dart';
import 'core/utils/ntp_clock_sync.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Global Flutter framework error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  // 2. Uncaught asynchronous error handling at platform level
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[PlatformDispatcher.onError] Uncaught asynchronous error: $error\n$stack');
    return true; // Prevents crashing the app process
  };

  // 3. Graceful dark-neon fallback widget when a widget build fails
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF090B14),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFF5252),
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Terjadi Kendala Tampilan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                kDebugMode
                    ? details.exceptionAsString()
                    : 'Komponen visual mengalami kesalahan sementara.',
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF9E9E9E),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Initialize MediaKit for hardware-accelerated video playback on native platforms
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }

  // Initialize Supabase Backend
  await SupabaseService().initialize();

  // Initialize NTP server clock sync with Supabase
  if (SupabaseService().isInitialized) {
    final client = SupabaseService().clientOrNull;
    if (client != null) {
      try {
        await NtpClockSync().syncWithSupabase(client);
      } catch (e) {
        debugPrint('[Main] NTP Clock Sync warning: $e');
      }
    }
  }

  runApp(
    const ProviderScope(
      child: WatchPartyApp(),
    ),
  );
}
