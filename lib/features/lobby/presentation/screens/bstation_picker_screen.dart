import 'package:flutter/material.dart';
import '../../data/bstation_service.dart';
import '../../data/models/bstation_video_model.dart';
import 'generic_media_picker_screen.dart';

/// Screen for picking Bstation/Bilibili videos, backed by [GenericMediaPickerScreen].
class BstationPickerScreen extends StatelessWidget {
  const BstationPickerScreen({super.key});

  static const Color bstationBlue = Color(0xFF23ADE5);

  @override
  Widget build(BuildContext context) {
    return GenericMediaPickerScreen<BstationVideo>(
      config: GenericMediaPickerConfig<BstationVideo>(
        title: 'Pilih Anime & Video Bstation',
        platformName: 'Bstation',
        brandColor: bstationBlue,
        brandIcon: Icons.tv_rounded,
        categories: const [
          'Anime Populer',
          'Donghua & Action',
          'Romance & Slice of Life',
          'AMV & Musik',
        ],
        categoryPresets: BstationService.categoryPresets,
        searchFunction: (query, _) async => BstationService.search(query),
        hasPagination: false,
        searchHint: 'Cari anime, donghua, atau link Bstation...',
      ),
    );
  }
}
