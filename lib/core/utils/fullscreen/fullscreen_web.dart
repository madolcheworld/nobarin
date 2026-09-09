import 'package:web/web.dart' as web;

bool isFullscreen() {
  return web.document.fullscreenElement != null;
}

void toggleFullscreen() {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  } else {
    web.document.documentElement?.requestFullscreen();
  }
}

Future<void> enterFullscreen() async {
  if (web.document.fullscreenElement == null) {
    web.document.documentElement?.requestFullscreen();
  }
}

Future<void> exitFullscreen() async {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  }
}
