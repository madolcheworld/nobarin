import 'package:flutter/material.dart';
import '../../data/models/twitch_stream_model.dart';
import '../../data/twitch_service.dart';
import 'generic_media_picker_screen.dart';

/// Screen for picking Twitch streams/channels, backed by [GenericMediaPickerScreen].
class TwitchPickerScreen extends StatelessWidget {
  const TwitchPickerScreen({super.key});

  static const Color twitchPurple = Color(0xFF9146FF);

  @override
  Widget build(BuildContext context) {
    return GenericMediaPickerScreen<TwitchStream>(
      config: GenericMediaPickerConfig<TwitchStream>(
        title: 'Pilih Stream Twitch',
        platformName: 'Twitch',
        brandColor: twitchPurple,
        brandIcon: Icons.live_tv_rounded,
        categories: const [
          'Populer & Live',
          'Gaming',
          'Musik & Kreatif',
          'Esports',
        ],
        categoryPresets: TwitchService.categoryPresets,
        searchFunction: (query, _) async => TwitchService.search(query),
        hasPagination: false,
        searchHint: 'Cari channel atau tempel link Twitch...',
      ),
    );
  }
}
