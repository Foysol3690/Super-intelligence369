import 'dart:typed_data';

/// Number of log-spaced spectrum bands produced by the analyzer.
const int kNexusBandCount = 24;

/// The single shared state every visual layer consumes. It is mutated in place
/// once per frame by the VisualStateController (no per-frame allocation) and
/// read by the painters. Mic ring, waveform, stream, particles and orb all
/// react to exactly these numbers, which keeps them one coherent system.
class AudioVisualState {
  // Smoothed audio features, normalised 0..1.
  double amplitude = 0;
  double bass = 0;
  double mid = 0;
  double treble = 0;
  final Float32List bands = Float32List(kNexusBandCount);

  // Derived energies.
  double orbEnergy = 0.18;
  double waveEnergy = 0.05;
  double particleEnergy = 0.12;
  double glow = 0.3;

  /// +1 = microphone -> orb (user speaking), -1 = orb -> microphone (AI speaking).
  double flowDirection = 0;

  /// 0 = full spectrum, 1 = concentrated blue/violet (thinking).
  double coolness = 0;

  /// Spring-driven core scale (organic overshoot on voice onsets).
  double orbScale = 1;
  double orbScaleVelocity = 0;

  // Smoothed state weights (always sum to ~1, crossfade between states).
  double wIdle = 1;
  double wListening = 0;
  double wProcessing = 0;
  double wThinking = 0;
  double wSpeaking = 0;

  // Integrated phases. Integrating speed (rather than multiplying time) keeps
  // motion continuous when speeds change.
  double time = 0;
  double ribbonPhase = 0;
  double wavePhase = 0;
  double streamPhase = 0;
  double thinkingPulse = 0;

  /// Intensity of the visible mic <-> orb connection (0..1). The 0.32 floor
  /// is deliberate: at the old 0.14 floor the connecting stream rendered at
  /// ~8-20% alpha while idle (see EnergyStream's painter), which read as
  /// barely-there / disconnected rather than "wired together". Raising the
  /// resting floor keeps the link clearly visible at all times while the
  /// additive listening/speaking/processing terms below are untouched, so it
  /// still brightens and widens the same way during active states.
  double get streamEnergy =>
      0.32 + (wListening + wSpeaking) * (0.3 + amplitude * 0.7) + wProcessing * 0.15;

  /// How strongly the microphone itself is engaged (dim when idle).
  double get micActivity =>
      0.25 + wListening * (0.45 + amplitude * 0.5) + wSpeaking * (0.3 + amplitude * 0.45) +
      wProcessing * 0.12;

  double band(double position) {
    final p = position.clamp(0.0, 1.0) * (kNexusBandCount - 1);
    final i = p.floor();
    if (i >= kNexusBandCount - 1) return bands[kNexusBandCount - 1];
    final f = p - i;
    return bands[i] + (bands[i + 1] - bands[i]) * f;
  }
}
