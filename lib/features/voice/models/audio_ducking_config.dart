import 'package:shared_preferences/shared_preferences.dart';

/// Preset level for Smart Audio Ducking
enum DuckingPreset {
  gentle(0.6, 'Lembut (60%)', 'Video tetap terdengar di latar belakang'),
  standard(0.4, 'Standar (40%)', 'Keseimbangan optimal antara video & obrolan'),
  aggressive(0.15, 'Agresif (15%)', 'Suara obrolan sangat diutamakan'),
  mute(0.0, 'Hening (0%)', 'Video dimatikan suaranya saat ada yang berbicara');

  final double factor;
  final String label;
  final String description;

  const DuckingPreset(this.factor, this.label, this.description);

  static DuckingPreset fromFactor(double factor) {
    if (factor <= 0.05) return DuckingPreset.mute;
    if (factor <= 0.25) return DuckingPreset.aggressive;
    if (factor <= 0.50) return DuckingPreset.standard;
    return DuckingPreset.gentle;
  }
}

/// Configuration settings for Smart Audio Ducking
class AudioDuckingConfig {
  static const String keyEnabled = 'nobarin_audio_ducking_enabled';
  static const String keyFactor = 'nobarin_audio_ducking_factor';
  static const String keyDuckSelf = 'nobarin_audio_ducking_self';
  static const String keySmooth = 'nobarin_audio_ducking_smooth';

  final bool enabled;
  final double duckingFactor;
  final bool duckWhenSpeakingLocally;
  final bool smoothTransition;
  final Duration attackDuration;
  final Duration releaseDuration;
  final Duration releaseHoldDuration;

  const AudioDuckingConfig({
    this.enabled = true,
    this.duckingFactor = 0.4,
    this.duckWhenSpeakingLocally = false,
    this.smoothTransition = false,
    this.attackDuration = const Duration(milliseconds: 150),
    this.releaseDuration = const Duration(milliseconds: 350),
    this.releaseHoldDuration = const Duration(milliseconds: 500),
  });

  const AudioDuckingConfig.production({
    this.enabled = true,
    this.duckingFactor = 0.4,
    this.duckWhenSpeakingLocally = false,
    this.smoothTransition = true,
    this.attackDuration = const Duration(milliseconds: 150),
    this.releaseDuration = const Duration(milliseconds: 350),
    this.releaseHoldDuration = const Duration(milliseconds: 500),
  });

  AudioDuckingConfig copyWith({
    bool? enabled,
    double? duckingFactor,
    bool? duckWhenSpeakingLocally,
    bool? smoothTransition,
    Duration? attackDuration,
    Duration? releaseDuration,
    Duration? releaseHoldDuration,
  }) {
    return AudioDuckingConfig(
      enabled: enabled ?? this.enabled,
      duckingFactor: (duckingFactor ?? this.duckingFactor).clamp(0.0, 0.8),
      duckWhenSpeakingLocally:
          duckWhenSpeakingLocally ?? this.duckWhenSpeakingLocally,
      smoothTransition: smoothTransition ?? this.smoothTransition,
      attackDuration: attackDuration ?? this.attackDuration,
      releaseDuration: releaseDuration ?? this.releaseDuration,
      releaseHoldDuration: releaseHoldDuration ?? this.releaseHoldDuration,
    );
  }

  DuckingPreset get nearestPreset => DuckingPreset.fromFactor(duckingFactor);

  /// Saves current configuration to persistent storage
  Future<void> saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyEnabled, enabled);
      await prefs.setDouble(keyFactor, duckingFactor);
      await prefs.setBool(keyDuckSelf, duckWhenSpeakingLocally);
      await prefs.setBool(keySmooth, smoothTransition);
    } catch (_) {}
  }

  /// Loads configuration from persistent storage with fallback to default production
  static Future<AudioDuckingConfig> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(keyEnabled) &&
          !prefs.containsKey(keyFactor) &&
          !prefs.containsKey(keySmooth)) {
        return const AudioDuckingConfig();
      }
      final enabled = prefs.getBool(keyEnabled) ?? true;
      final factor = prefs.getDouble(keyFactor) ?? 0.4;
      final duckSelf = prefs.getBool(keyDuckSelf) ?? false;
      final smooth = prefs.getBool(keySmooth) ?? true;
      return AudioDuckingConfig.production(
        enabled: enabled,
        duckingFactor: factor.clamp(0.0, 0.8),
        duckWhenSpeakingLocally: duckSelf,
        smoothTransition: smooth,
      );
    } catch (_) {
      return const AudioDuckingConfig();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioDuckingConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          (duckingFactor - other.duckingFactor).abs() < 0.001 &&
          duckWhenSpeakingLocally == other.duckWhenSpeakingLocally &&
          smoothTransition == other.smoothTransition &&
          attackDuration == other.attackDuration &&
          releaseDuration == other.releaseDuration &&
          releaseHoldDuration == other.releaseHoldDuration;

  @override
  int get hashCode =>
      enabled.hashCode ^
      duckingFactor.hashCode ^
      duckWhenSpeakingLocally.hashCode ^
      smoothTransition.hashCode ^
      attackDuration.hashCode ^
      releaseDuration.hashCode ^
      releaseHoldDuration.hashCode;
}
