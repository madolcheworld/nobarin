import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../room/models/room_model.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/app_haptics.dart';
import '../../data/lobby_repository.dart';
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

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      AppHaptics.selection();
      final normalized = LobbyRepository.normalizeCode(text);
      _codeController.text = normalized.isNotEmpty ? normalized : text;
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    if (_isLoading) return;

    final input = _codeController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorMessage = 'Masukkan kode room');
      return;
    }

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
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(room);
      }
      widget.onJoined?.call(room);
    } else {
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryNeon.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.key_rounded,
                        color: AppColors.primaryNeon,
                        size: 22,
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
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _codeController,
                  enabled: !_isLoading,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: AppColors.secondaryNeon,
                  ),
                  decoration: InputDecoration(
                    hintText: 'MISAL: WP1001',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      letterSpacing: 1.5,
                      color: AppColors.textMuted,
                    ),
                    errorText: _errorMessage,
                    suffixIcon: _codeController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
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
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    onPressed: _isLoading ? null : _pasteFromClipboard,
                    icon: const Icon(Icons.content_paste_rounded, size: 15),
                    label: const Text(
                      'Tempel dari Clipboard',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondaryNeon,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleJoin,
                        child: _isLoading
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Mencari...',
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              )
                            : const Text('Gabung'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
