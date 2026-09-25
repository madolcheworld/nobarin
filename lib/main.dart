import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/constants/app_colors.dart';
import 'core/network/supabase_client.dart';
import 'core/utils/ntp_clock_sync.dart';
import 'features/room/controllers/unified_player_controller.dart';

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
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.accentRed,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Terjadi Kendala Tampilan',
                style: TextStyle(
                  color: AppColors.textPrimary,
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
                  color: AppColors.textSecondary,
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
    await UnifiedPlayerController.initializePlatformSettings();
  }

  // Initialize Supabase Backend
  await SupabaseService().initialize();

  // Initialize NTP server clock sync in background without blocking app launch
  if (SupabaseService().isInitialized) {
    final client = SupabaseService().clientOrNull;
    if (client != null) {
      unawaited(
        NtpClockSync().syncWithSupabase(client).catchError((e) {
          debugPrint('[Main] NTP Clock Sync warning: $e');
        }),
      );
    }
  }

  runApp(
    const ProviderScope(
      child: NobarinApp(),
    ),
  );
}
