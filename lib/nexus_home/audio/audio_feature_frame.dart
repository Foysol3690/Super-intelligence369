import 'dart:math' as math;
import 'dart:typed_data';

import '../core/audio_visual_state.dart';
import 'feature_extractor.dart';

/// Monotonic clock shared by the audio and visual layers.
abstract final class NexusClock {
  static final Stopwatch _watch = Stopwatch()..start();
  static int get micros => _watch.elapsedMicroseconds;
}

/// Latest analysed features for one audio channel (mic input or AI output).
/// Values go stale and fade out if the source stops sending data, so the
/// visuals settle naturally instead of freezing.
class AudioFeatureFrame {
  double level = 0;
  double bass = 0;
  double mid = 0;
  double treble = 0;
  final Float32List bands = Float32List(kNexusBandCount);
  int _stamp = -1 << 30;

  double _pulse = 0;
  int _pulseStamp = -1 << 30;

  static const int _staleAfterMicros = 160000;

  void applyFeatures(Float32List f) {
    level = f[FeatureIndex.level];
    bass = f[FeatureIndex.bass];
    mid = f[FeatureIndex.mid];
    treble = f[FeatureIndex.treble];
    for (var i = 0; i < kNexusBandCount; i++) {
      bands[i] = f[FeatureIndex.bands + i];
    }
    _stamp = NexusClock.micros;
  }

  /// For sources that only expose a loudness value (for example
  /// speech_to_text's onSoundLevelChange). Bands get a speech-shaped profile.
  void applyLevel(double value) {
    final l = value.clamp(0.0, 1.0).toDouble();
    level = l;
    bass = l * 0.85;
    mid = l;
    treble = l * 0.6;
    for (var i = 0; i < kNexusBandCount; i++) {
      final x = i / (kNexusBandCount - 1);
      bands[i] = l * (0.35 + 0.65 * math.exp(-math.pow((x - 0.35) / 0.3, 2)));
    }
    _stamp = NexusClock.micros;
  }

  /// A decaying envelope hit, e.g. driven by TTS word-boundary callbacks when
  /// the engine does not expose its PCM output.
  void pulse([double strength = 1]) {
    _pulse = strength.clamp(0.0, 1.0).toDouble();
    _pulseStamp = NexusClock.micros;
  }

  /// 1 while fresh, then decays to 0 once the source goes quiet.
  double freshness(int now) {
    final age = now - _stamp;
    if (age <= _staleAfterMicros) return 1;
    return math.exp(-(age - _staleAfterMicros) / 120000.0);
  }

  double pulseEnvelope(int now) {
    final age = (now - _pulseStamp) / 1e6;
    if (age < 0 || age > 1.2) return 0;
    return _pulse * math.exp(-age / 0.22);
  }

  void reset() {
    level = bass = mid = treble = 0;
    bands.fillRange(0, kNexusBandCount, 0);
    _stamp = -1 << 30;
    _pulse = 0;
  }
}
