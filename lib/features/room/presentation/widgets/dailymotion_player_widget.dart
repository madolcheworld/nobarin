import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../controllers/dailymotion_player_controller.dart';

/// Widget that embeds the Dailymotion player in the room screen.
class DailymotionPlayerWidget extends StatelessWidget {
  final DailymotionPlayerController controller;
  final double aspectRatio;

  const DailymotionPlayerWidget({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final webCtrl = controller.webViewController;
        if (webCtrl != null) {
          return AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              color: Colors.black,
              child: WebViewWidget(controller: webCtrl),
            ),
          );
        }

        // Fallback / Loading state
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
                    color: AppColors.dailymotionBlue.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.dailymotionBlue.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.play_circle_filled_rounded,
                    color: AppColors.dailymotionBlue,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Memuat Pemutar Dailymotion...',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Video Dailymotion disinkronkan untuk seluruh peserta',
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
}
