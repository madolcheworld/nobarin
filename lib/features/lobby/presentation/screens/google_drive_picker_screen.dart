import 'package:flutter/material.dart';
import '../../data/google_drive_service.dart';
import '../../data/models/google_drive_video_model.dart';
import 'generic_media_picker_screen.dart';

/// Screen for picking Google Drive videos, backed by [GenericMediaPickerScreen].
class GoogleDrivePickerScreen extends StatelessWidget {
  const GoogleDrivePickerScreen({super.key});

  static const Color driveGreen = Color(0xFF0F9D58);

  @override
  Widget build(BuildContext context) {
    return GenericMediaPickerScreen<GoogleDriveVideo>(
      config: GenericMediaPickerConfig<GoogleDriveVideo>(
        title: 'Pilih Video Google Drive',
        platformName: 'Google Drive',
        brandColor: driveGreen,
        brandIcon: Icons.add_to_drive_rounded,
        categories: const [
          'Film & Animasi Open Source',
          'Tutorial & Dokumenter',
          'Demo Sample Clips',
        ],
        categoryPresets: GoogleDriveService.categoryPresets,
        searchFunction: (query, _) async => GoogleDriveService.search(query),
        hasPagination: false,
        searchHint: 'Cari judul file atau tempel URL Google Drive...',
      ),
    );
  }
}
