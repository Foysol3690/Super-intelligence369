import 'dart:math' as math;
import 'dart:ui';

/// Shared colour language: electric cyan -> blue -> violet -> magenta -> pink -> warm orange.
abstract final class NexusPalette {
  static const Color void0 = Color(0xFF02040A);
  static const Color void1 = Color(0xFF050916);
  static const Color void2 = Color(0xFF080E22);

  static const Color cyan = Color(0xFF3FE6FF);
  static const Color blue = Color(0xFF3D7BFF);
  static const Color violet = Color(0xFF8A5CFF);
  static const Color magenta = Color(0xFFE24CE0);
  static const Color pink = Color(0xFFFF4D8D);
  static const Color orange = Color(0xFFFF9A3D);

  static const Color rose = Color(0xFFFF4D6D);
  static const Color amber = Color(0xFFFFA24D);
  static const Color periwinkle = Color(0xFF6F8CFF);
  static const Color aqua = Color(0xFF52E5F2);

  static const List<int> _stops = <int>[
    0xFF3FE6FF,
    0xFF3D7BFF,
    0xFF8A5CFF,
    0xFFE24CE0,
    0xFFFF4D8D,
    0xFFFF9A3D,
  ];

  /// Spectrum position for [t] in 0..1. [cool] pulls the hue toward blue/violet
  /// (used by the THINKING state). Returns a packed ARGB int so per-frame
  /// particle code can colour thousands of sprites without allocating Colors.
  static int spectrumArgb(double t, double alpha, [double cool = 0]) {
    var h = t.clamp(0.0, 1.0);
    if (cool > 0) h = h + ((0.12 + h * 0.36) - h) * cool.clamp(0.0, 1.0);
    final scaled = h * (_stops.length - 1);
    final i = scaled.floor().clamp(0, _stops.length - 2);
    final f = scaled - i;
    final a = _stops[i];
    final b = _stops[i + 1];
    final r = _lerpChannel(a >> 16, b >> 16, f);
    final g = _lerpChannel(a >> 8, b >> 8, f);
    final bl = _lerpChannel(a, b, f);
    final al = (alpha.clamp(0.0, 1.0) * 255).round();
    return (al << 24) | (r << 16) | (g << 8) | bl;
  }

  static Color spectrum(double t, [double alpha = 1, double cool = 0]) =>
      Color(spectrumArgb(t, alpha, cool));

  static int _lerpChannel(int a, int b, double f) {
    final ca = a & 0xFF;
    final cb = b & 0xFF;
    return (ca + (cb - ca) * f).round().clamp(0, 255);
  }

  /// Six colours sampled across the spectrum, shifted by [cool].
  static List<Color> ribbonColors(double cool) => List<Color>.generate(
        6,
        (i) => spectrum(i / 5, 1, cool),
        growable: false,
      );
}

/// Cheap smooth pseudo-noise built from incommensurate sines. Deterministic,
/// allocation-free and continuous, which is all organic motion needs.
double organic(double t, [double seed = 0]) =>
    math.sin(t + seed) * 0.5 +
    math.sin(t * 1.618 + seed * 1.7) * 0.3 +
    math.sin(t * 2.718 + seed * 2.3) * 0.2;

/// Frame-rate independent exponential approach.
double approach(double current, double target, double rate, double dt) =>
    current + (target - current) * (1 - math.exp(-rate * dt));

/// Asymmetric smoothing: fast attack, slower release. Keeps audio-driven
/// visuals responsive without jitter.
double attackRelease(
  double current,
  double target,
  double dt, {
  double attack = 20,
  double release = 6,
}) =>
    approach(current, target, target > current ? attack : release, dt);
