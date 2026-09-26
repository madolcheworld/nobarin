import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/url_open/url_open.dart';
import '../../controllers/google_drive_player_controller.dart';

/// Widget that embeds the Google Drive video player in the room screen.
class GoogleDrivePlayerWidget extends StatelessWidget {
  final GoogleDrivePlayerController controller;
  final double aspectRatio;

  const GoogleDrivePlayerWidget({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebFallback(context);
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final webCtrl = controller.webViewController;
        if (webCtrl != null) {
          return AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              color: Colors.black,
              child: IgnorePointer(
                child: WebViewWidget(
                  key: controller.webViewKey,
                  controller: webCtrl,
                ),
              ),
            ),
          );
        }

        // Fallback / Loading state on mobile
        return AspectRatio(
          aspectRatio: aspectRatio,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.googleDriveGreen.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.googleDriveGreen.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.add_to_drive_rounded,
                    color: AppColors.googleDriveGreen,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Memuat Pemutar Google Drive...',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Video Google Drive disinkronkan untuk seluruh peserta',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWebFallback(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        color: AppColors.surface,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.googleDriveGreen.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.add_to_drive_rounded,
                  color: AppColors.googleDriveGreen,
                  size: 28,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Google Drive di Web Browser',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pada platform Web, pemutaran sinkron penuh didukung optimal melalui aplikasi Android/iOS atau dengan membuka tautan Google Drive langsung.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              if (controller.url.isNotEmpty)
                FilledButton.icon(
                  onPressed: () {
                    final previewUrl = GoogleDrivePlayerController.resolvePreviewUri(
                      controller.url,
                    ).toString();
                    openUrlInNewTab(previewUrl);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 14),
                  label: const Text('Buka Video di Tab Baru', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.googleDriveGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
