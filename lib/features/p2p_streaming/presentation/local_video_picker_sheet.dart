import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../models/local_video_file.dart';

class LocalVideoPickerSheet extends StatefulWidget {
  final ValueChanged<LocalVideoFile> onFileSelected;
  final bool isAddingToQueue;

  const LocalVideoPickerSheet({
    super.key,
    required this.onFileSelected,
    this.isAddingToQueue = false,
  });

  static Future<LocalVideoFile?> show(
    BuildContext context, {
    bool isAddingToQueue = false,
  }) {
    return showModalBottomSheet<LocalVideoFile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LocalVideoPickerSheet(
        isAddingToQueue: isAddingToQueue,
        onFileSelected: (file) => Navigator.of(ctx).pop(file),
      ),
    );
  }

  @override
  State<LocalVideoPickerSheet> createState() => _LocalVideoPickerSheetState();
}

class _LocalVideoPickerSheetState extends State<LocalVideoPickerSheet> {
  LocalVideoFile? _selectedFile;
  bool _isPicking = false;

  Future<void> _pickVideoFile() async {
    AppHaptics.light();
    setState(() => _isPicking = true);

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v', 'ts'],
      );

      if (files.isNotEmpty) {
        final pf = files.first;
        final ext = pf.extension ?? 'mp4';
        final size = pf.lengthSync() ?? await pf.length();
        Uint8List? bytes;
        if (pf.path == null) {
          bytes = await pf.readAsBytes();
        }
        final file = LocalVideoFile(
          id: const Uuid().v4(),
          name: pf.name,
          path: pf.path,
          bytes: bytes,
          size: size,
          mimeType: LocalVideoFile.guessMimeType(ext),
          extension: ext,
        );
        setState(() => _selectedFile = file);
        AppHaptics.medium();
      }
    } catch (e) {
      debugPrint('[LocalVideoPickerSheet] Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih file: $e'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_tethering_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Video Lokal (P2P Internet)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Streaming langsung via WebRTC tanpa upload ke cloud',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Internet P2P Info Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0077B6).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.public_rounded,
                  color: Color(0xFF00B4D8),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Video dipancarkan langsung dari HP/PC Anda ke penonton melalui internet (WiFi mana saja atau Data Seluler 4G/5G). Tidak perlu satu jaringan WiFi.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // File selection card or button
          if (_selectedFile == null)
            InkWell(
              onTap: _isPicking ? null : _pickVideoFile,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border,
                    style: BorderStyle.solid,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: _isPicking
                          ? const SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Color(0xFF00B4D8),
                              ),
                            )
                          : const Icon(
                              Icons.video_file_rounded,
                              size: 36,
                              color: Color(0xFF00B4D8),
                            ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Pilih File Video dari Perangkat',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mendukung MP4, MKV, WebM, MOV, AVI (Hingga beberapa GB)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF00B4D8).withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00B4D8).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.movie_filter_rounded,
                          color: Color(0xFF00B4D8),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedFile!.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00B4D8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _selectedFile!.extension.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _selectedFile!.formattedSize,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.change_circle_outlined,
                          color: AppColors.textSecondary,
                        ),
                        tooltip: 'Ganti File',
                        onPressed: _pickVideoFile,
                      ),
                    ],
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Submit Action Button
          ElevatedButton(
            onPressed: _selectedFile == null
                ? null
                : () {
                    AppHaptics.heavy();
                    widget.onFileSelected(_selectedFile!);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00B4D8),
              disabledBackgroundColor:
                  AppColors.surfaceElevated.withValues(alpha: 0.5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isAddingToQueue
                      ? Icons.queue_rounded
                      : Icons.play_arrow_rounded,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isAddingToQueue
                      ? 'Tambahkan ke Antrean'
                      : 'Mulai Nobar File Ini',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
