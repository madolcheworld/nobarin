import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/url_open/url_open.dart';
import '../../controllers/vimeo_player_controller.dart';

/// Widget that embeds the Vimeo player in the room screen.
class VimeoPlayerWidget extends StatelessWidget {
  final VimeoPlayerController controller;
  final double aspectRatio;

  const VimeoPlayerWidget({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (kIsWeb) {
          final webPlayer = controller.buildWebWidget();
          if (webPlayer != null) {
            return AspectRatio(
              aspectRatio: aspectRatio,
              child: Container(
                color: Colors.black,
                child: webPlayer,
              ),
            );
          }
          if (controller.url.isEmpty) {
            return _buildWebFallback(context);
          }
          return _buildLoading(context);
        }

        final webCtrl = controller.webViewController;
        if (webCtrl != null) {
          return AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              color: Colors.black,
              child: WebViewWidget(
                key: controller.webViewKey,
                controller: webCtrl,
              ),
            ),
          );
        }

        // Fallback / Loading state on mobile
        return _buildLoading(context);
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
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
                color: AppColors.vimeoBlue.withValues(alpha: 0.15),
                border: Border.all(
                  color: AppColors.vimeoBlue.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(
                Icons.play_circle_filled_rounded,
                color: AppColors.vimeoBlue,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Memuat Pemutar Vimeo...',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Video Vimeo disinkronkan untuk seluruh peserta',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
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
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.vimeoBlue.withValues(alpha: 0.15),
                  border: Border.all(
                    color: AppColors.vimeoBlue.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.play_circle_filled_rounded,
                  color: AppColors.vimeoBlue,
                  size: 28,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pemutar Vimeo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Menunggu pemutaran video Vimeo...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (controller.url.isNotEmpty)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.vimeoBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        openUrlInNewTab(controller.url);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text(
                        'Buka di Vimeo',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
