import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../controllers/bstation_player_controller.dart';

/// Widget that embeds the Bstation / Bilibili player in the room screen.
class BstationPlayerWidget extends StatelessWidget {
  final BstationPlayerController controller;
  final double aspectRatio;

  const BstationPlayerWidget({
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
                    color: AppColors.bstationBlue.withValues(alpha: 0.15),
                    border: Border.all(
                      color: AppColors.bstationBlue.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.tv_rounded,
                    color: AppColors.bstationBlue,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Memuat Pemutar Bstation...',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Video Bstation disinkronkan untuk seluruh peserta',
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
