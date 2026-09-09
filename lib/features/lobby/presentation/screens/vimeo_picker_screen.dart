import 'package:flutter/material.dart';
import '../../data/models/vimeo_video_model.dart';
import '../../data/vimeo_service.dart';
import 'generic_media_picker_screen.dart';

/// Screen for picking Vimeo videos, backed by [GenericMediaPickerScreen].
class VimeoPickerScreen extends StatelessWidget {
  const VimeoPickerScreen({super.key});

  static const Color vimeoBlue = Color(0xFF1AB7EA);

  @override
  Widget build(BuildContext context) {
    return GenericMediaPickerScreen<VimeoVideo>(
      config: GenericMediaPickerConfig<VimeoVideo>(
        title: 'Pilih Video Vimeo',
        platformName: 'Vimeo',
        brandColor: vimeoBlue,
        brandIcon: Icons.video_library_rounded,
        categories: const [
          'Staff Picks',
          'Film Pendek & Sci-Fi',
          'Animasi 3D',
          'Dokumenter & Alam',
        ],
        categoryPresets: VimeoService.categoryPresets,
        searchFunction: (query, _) => VimeoService.search(query),
        hasPagination: false,
        searchHint: 'Cari judul, kata kunci, atau ID Vimeo...',
      ),
    );
  }
}
