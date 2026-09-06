import 'web_video_adapter.dart';

bool get isSupported => false;

WebVideoAdapter? createWebVideoAdapter({
  required void Function(double position) onPositionChanged,
  required void Function(double duration) onDurationChanged,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function(String error) onError,
}) =>
    null;
