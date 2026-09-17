import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class ExitRoomLoadingDialog extends StatelessWidget {
  final String message;
  final String? subMessage;

  const ExitRoomLoadingDialog({
    super.key,
    required this.message,
    this.subMessage,
  });

  /// Displays the exit loading dialog non-dismissibly.
  /// Returns a function to dismiss the dialog safely.
  static void show(
    BuildContext context, {
    required String message,
    String? subMessage,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: ExitRoomLoadingDialog(
          message: message,
          subMessage: subMessage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.border,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                spreadRadius: 4,
              ),
              BoxShadow(
                color: AppColors.accentRed.withValues(alpha: 0.15),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing exit icon container
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentRed.withValues(alpha: 0.15),
                  border: Border.all(
                    color: AppColors.accentRed.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.logout_rounded,
                    color: AppColors.accentRed,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Main message
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),

              if (subMessage != null && subMessage!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 22),

              // Neon progress indicator
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  color: AppColors.primaryNeon,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
