import 'package:flutter/material.dart';
import '../../data/models/youtube_video_model.dart';
import '../../data/youtube_service.dart';
import 'generic_media_picker_screen.dart';

/// Screen for picking YouTube videos, backed by [GenericMediaPickerScreen].
class YouTubePickerScreen extends StatelessWidget {
  const YouTubePickerScreen({super.key});

  static const Color youtubeRed = Color(0xFFFF0000);

  @override
  Widget build(BuildContext context) {
    return GenericMediaPickerScreen<YouTubeVideo>(
      config: GenericMediaPickerConfig<YouTubeVideo>(
        title: 'Pilih Video YouTube',
        platformName: 'YouTube',
        brandColor: youtubeRed,
        brandIcon: Icons.play_arrow_rounded,
        categories: const [
          'Trending',
          'Musik & Lo-Fi',
          'Trailer Film',
          'Anime',
          'Gaming',
          'Animasi / Kartun',
        ],
        categoryPresets: YouTubeService.categoryPresets,
        searchFunction: (query, page) => YouTubeService.search(query, page: page),
        hasPagination: true,
        searchHint: 'Cari video atau tempel link YouTube...',
      ),
    );
  }
}
