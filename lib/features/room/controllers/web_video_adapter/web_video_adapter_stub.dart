import '../../models/video_quality.dart';
import 'web_video_adapter.dart';

bool get isSupported => false;

WebVideoAdapter? createWebVideoAdapter({
  required void Function(double position) onPositionChanged,
  required void Function(double duration) onDurationChanged,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function(String error) onError,
  void Function(List<VideoQuality> qualities)? onQualitiesChanged,
}) =>
    null;

