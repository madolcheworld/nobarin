import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/dailymotion_service.dart';
import '../../data/models/dailymotion_video_model.dart';
import 'generic_media_picker_screen.dart';

/// Screen for picking Dailymotion videos, backed by [GenericMediaPickerScreen].
class DailymotionPickerScreen extends StatelessWidget {
  const DailymotionPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GenericMediaPickerScreen<DailymotionVideo>(
      config: GenericMediaPickerConfig<DailymotionVideo>(
        title: 'Pilih Video Dailymotion',
        platformName: 'Dailymotion',
        brandColor: AppColors.dailymotionBlue,
        brandIcon: Icons.play_circle_filled_rounded,
        categories: const [
          'Trending',
          'Berita & Media',
          'Musik & Klip',
          'Olahraga & Aksi',
          'Film & Animasi',
        ],
        categoryPresets: DailymotionService.categoryPresets,
        searchFunction: (query, _) => DailymotionService.search(query),
        hasPagination: false,
        searchHint: 'Cari video Dailymotion...',
      ),
    );
  }
}
