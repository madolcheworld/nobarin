import '../../models/video_quality.dart';
import 'dailymotion_web_adapter.dart';

bool get isSupported => false;

DailymotionWebAdapter? createDailymotionWebAdapter({
  required void Function(double position) onPositionChanged,
  required void Function(double duration) onDurationChanged,
  required void Function(bool isPlaying) onPlayingChanged,
  required void Function() onPlaybackEnded,
  required void Function(String error) onError,
  void Function(List<VideoQuality> qualities)? onQualitiesChanged,
  void Function(VideoQuality quality)? onQualitySelectedChanged,
  void Function(int width, int height)? onResolutionChanged,
}) =>
    null;
