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

void enterFullscreen() {
  if (web.document.fullscreenElement == null) {
    web.document.documentElement?.requestFullscreen();
  }
}

void exitFullscreen() {
  if (web.document.fullscreenElement != null) {
    web.document.exitFullscreen();
  }
}
