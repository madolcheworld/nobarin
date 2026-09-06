import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/network/supabase_client.dart';
import 'core/utils/ntp_clock_sync.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize MediaKit for hardware-accelerated video playback on native platforms
  if (!kIsWeb) {
    MediaKit.ensureInitialized();
  }

  // Initialize Supabase Backend
  await SupabaseService().initialize();

  // Initialize NTP server clock sync with Supabase
  if (SupabaseService().isInitialized) {
    try {
      await NtpClockSync().syncWithSupabase(SupabaseService().client);
    } catch (_) {}
  }

  runApp(
    const ProviderScope(
      child: WatchPartyApp(),
    ),
  );
}
