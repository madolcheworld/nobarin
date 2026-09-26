import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../room/models/room_model.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../../../core/widgets/nobarin_button.dart';
import '../lobby_controller.dart';

class JoinCodeDialog extends ConsumerStatefulWidget {
  final ValueChanged<RoomModel>? onJoined;

  const JoinCodeDialog({super.key, this.onJoined});

  @override
  ConsumerState<JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends ConsumerState<JoinCodeDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    if (_isLoading) return;

    final input = _codeController.text.trim();
    if (input.isEmpty) {
      AppHaptics.heavy();
      setState(() => _errorMessage = 'Masukkan kode room');
      return;
    }
    if (input.length > 256) {
      AppHaptics.heavy();
      setState(() => _errorMessage = 'Kode atau tautan room terlalu panjang');
      return;
    }

    AppHaptics.selection();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final room = await ref
        .read(lobbyControllerProvider.notifier)
        .findRoomByCode(input);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (room != null) {
      AppHaptics.medium();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(room);
      }
      widget.onJoined?.call(room);
    } else {
      AppHaptics.heavy();
      final repoError = ref.read(lobbyControllerProvider.notifier).lastRepositoryError;
      final clean = input.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), '').trim();
      final display = clean.length > 20 ? '${clean.substring(0, 17)}...' : clean;
      setState(() {
        _errorMessage = repoError ?? 'Room dengan kode "$display" tidak ditemukan';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.secondaryNeon.withValues(alpha: 0.28),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 32,
                    spreadRadius: 4,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppColors.secondaryNeon.withValues(alpha: 0.12),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Row
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.secondaryNeon.withValues(alpha: 0.2),
                                  AppColors.primaryNeon.withValues(alpha: 0.15),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.secondaryNeon.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.pin_rounded,
                                color: AppColors.secondaryNeon,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gabung Room',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Masukkan kode untuk bergabung',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          NobarinModalIconButton(
                            icon: Icons.close_rounded,
                            tooltip: 'Tutup',
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Input Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'KODE ROOM',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (_codeController.text.isNotEmpty)
                            Text(
                              '${_codeController.text.length} KARAKTER',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                                color: AppColors.secondaryNeon,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Code Input Field
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighlight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _errorMessage != null
                                ? AppColors.accentRed.withValues(alpha: 0.8)
                                : AppColors.secondaryNeon.withValues(alpha: 0.3),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _errorMessage != null
                                  ? AppColors.accentRed.withValues(alpha: 0.1)
                                  : AppColors.secondaryNeon.withValues(alpha: 0.06),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _codeController,
                          maxLength: 256,
                          buildCounter:
                              (
                                _, {
                                required currentLength,
                                required isFocused,
                                required maxLength,
                              }) => null,
                          enabled: !_isLoading,
                          autofocus: true,
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: AppColors.secondaryNeon,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            hintText: 'MISAL: WP1001',
                            hintStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2,
                              color: AppColors.textMuted,
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(left: 14, right: 4),
                              child: Icon(
                                Icons.tag_rounded,
                                color: AppColors.secondaryNeon,
                                size: 20,
                              ),
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            suffixIcon: _codeController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 18,
                                    ),
                                    color: AppColors.textMuted,
                                    tooltip: 'Hapus teks',
                                    onPressed: () {
                                      AppHaptics.light();
                                      _codeController.clear();
                                      setState(() => _errorMessage = null);
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (_) {
                            if (_errorMessage != null) {
                              setState(() => _errorMessage = null);
                            } else {
                              setState(() {});
                            }
                          },
                          onSubmitted: (_) => _handleJoin(),
                        ),
                      ),

                      // Status or Tip Box (No clipboard button)
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.accentRed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.accentRed.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 16,
                                color: AppColors.accentRed,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.accentRed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighlight.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.borderLight.withValues(alpha: 0.12),
                              width: 1,
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                size: 15,
                                color: AppColors.textMuted,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Masukkan kode 6 karakter atau tautan URL room',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 22),

                      // Action Buttons: Batal & Gabung
                      Row(
                        children: [
                          Expanded(
                            child: NobarinSecondaryButton(
                              label: 'Batal',
                              isNeutral: true,
                              height: 48,
                              onPressed: _isLoading
                                  ? null
                                  : () => Navigator.of(context).pop(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: NobarinPrimaryButton(
                              label: 'Gabung',
                              icon: Icons.login_rounded,
                              height: 48,
                              isLoading: _isLoading,
                              gradient: AppColors.cyanGradient,
                              glowShadows: AppColors.neonCyanGlow,
                              onPressed: _isLoading ? null : _handleJoin,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
