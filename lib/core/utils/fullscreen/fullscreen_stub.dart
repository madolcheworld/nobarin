import 'package:flutter/services.dart';

bool isFullscreen() => false;

void toggleFullscreen() {}

Future<void> enterFullscreen() async {
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  } catch (_) {}
}

Future<void> exitFullscreen() async {
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    Future.delayed(const Duration(milliseconds: 600), () {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    });
  } catch (_) {}
}
