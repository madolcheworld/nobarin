import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/url_open/url_open.dart';
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
              child: WebViewWidget(
                key: controller.webViewKey,
                controller: webCtrl,
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
                  color: AppColors.bstationBlue.withValues(alpha: 0.15),
                  border: Border.all(
                    color: AppColors.bstationBlue.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.tv_rounded,
                  color: AppColors.bstationBlue,
                  size: 28,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pemutar Bstation Khusus Mobile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Karena batasan keamanan browser (Same-Origin Policy), sinkronisasi langsung Bstation didukung di aplikasi Android & iOS.',
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
                        backgroundColor: AppColors.bstationBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: () => openUrlInNewTab(controller.url),
                      icon: const Icon(Icons.open_in_new_rounded, size: 14),
                      label: const Text(
                        'Buka di Bstation',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.screen_share_rounded,
                      color: AppColors.secondaryNeon,
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Tips: Minta Host tekan "Bagi Layar" (Screen Share) untuk nobar di Web!',
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
