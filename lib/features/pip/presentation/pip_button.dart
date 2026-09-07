import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../services/pip_service.dart';

/// An icon button that allows users to transition the active room into
/// Picture-in-Picture (PiP) mode.
class PipButton extends StatefulWidget {
  final PipService? pipService;
  final VoidCallback? onBeforeEnter;

  const PipButton({
    super.key,
    this.pipService,
    this.onBeforeEnter,
  });

  @override
  State<PipButton> createState() => _PipButtonState();
}

class _PipButtonState extends State<PipButton> {
  bool _isSupported = true;

  PipService get _pip => widget.pipService ?? PipService.instance;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  Future<void> _checkSupport() async {
    final supported = await _pip.isPipSupported();
    if (mounted) {
      setState(() {
        _isSupported = supported;
      });
    }
  }

  Future<void> _handlePressed() async {
    widget.onBeforeEnter?.call();
    final success = await _pip.enterPip();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mode Picture-in-Picture tidak didukung pada perangkat ini.'),
          backgroundColor: AppColors.surfaceElevated,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: 'Mode Picture-in-Picture (PiP)',
      icon: const Icon(
        Icons.picture_in_picture_alt_rounded,
        color: AppColors.textSecondary,
        size: 20,
      ),
      splashRadius: 20,
      onPressed: _handlePressed,
    );
  }
}
