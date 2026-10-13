import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../core/audio_visual_state.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';

class _RibbonSpec {
  const _RibbonSpec(this.radius, this.lobes, this.lobeDepth, this.twist, this.speed, this.seed,
      this.spin);

  final double radius;
  final int lobes;
  final double lobeDepth;
  final double twist;
  final double speed;
  final double seed;
  final double spin;
}

/// Computes every procedural curve once per frame (orbital ribbons, the
/// mic <-> orb energy stream, core filaments, the waveform) into reusable
/// Path objects. Painters only draw; particles sample the same curves, so
/// everything stays physically connected.
class EnergyGeometry {
  static const List<_RibbonSpec> _ribbons = <_RibbonSpec>[
    _RibbonSpec(0.86, 4, 0.11, 0.24, 1.0, 0.0, 1),
    _RibbonSpec(0.94, 4, 0.09, 0.30, 0.8, 1.7, -1),
    _RibbonSpec(0.78, 4, 0.13, 0.20, 1.2, 3.1, 1),
    _RibbonSpec(0.99, 3, 0.07, 0.28, 0.7, 4.4, -1),
    _RibbonSpec(0.83, 5, 0.06, 0.34, 0.9, 5.9, 1),
    _RibbonSpec(0.91, 4, 0.12, 0.22, 1.1, 7.3, -1),
  ];
  static const int _strands = 4;
  static const int _ribbonSamples = 84;
  static const int streamStrands = 9;
  static const int _streamSamples = 40;
  static const int waveSamples = 150;

  // Ribbons split by depth: back strands render behind the glass lens (and
  // get blurred by it), front strands render over the core.
  final Path backCore = Path();
  final Path backFilaments = Path();
  final Path frontCore = Path();
  final Path frontFilaments = Path();
  final Path coreFilaments = Path();

  // Energy stream strands grouped by hue (cool / violet / warm) + all strands.
  final List<Path> streamGroups = <Path>[Path(), Path(), Path()];
  final Path streamAll = Path();

  final Path waveMain = Path();
  final Path waveLayers = Path();
  final Path waveHairlines = Path();
  final Float32List waveY = Float32List(waveSamples + 1);
  final Float32List waveAmp = Float32List(waveSamples + 1);
  final Float32List _waveEnvelope = Float32List(waveSamples + 1);
  double waveLeft = 0;
  double waveWidth = 1;
  double waveCenterY = 0;

  // Energy stream cubic Bezier control points.
  double _p0x = 0, _p0y = 0, _p1x = 0, _p1y = 0, _p2x = 0, _p2y = 0, _p3x = 0, _p3y = 0;
  double streamSpread = 0;
  double streamWiggle = 0;
  double _streamPhase = 0;

  /// Output of [streamAt] (avoids allocating Offsets per particle).
  double outX = 0, outY = 0;

  double ribbonRadius = 0;

  EnergyGeometry() {
    for (var i = 0; i <= waveSamples; i++) {
      final x = i / waveSamples;
      double g(double c, double w) => math.exp(-math.pow((x - c) / w, 2).toDouble());
      final humps = (g(0.24, 0.12) + g(0.76, 0.12)) * 0.85 + 0.3 * g(0.5, 0.3);
      final edge = math.pow(math.sin(math.pi * x), 0.7).toDouble();
      final micDip = 1 - 0.55 * g(0.5, 0.085);
      _waveEnvelope[i] = humps * edge * micDip;
    }
  }

  void update(AudioVisualState v, NexusLayout layout) {
    _updateRibbons(v, layout);
    _updateCoreFilaments(v, layout);
    _updateStream(v, layout);
    _updateWave(v, layout);
  }

  void _updateRibbons(AudioVisualState v, NexusLayout layout) {
    backCore.reset();
    backFilaments.reset();
    frontCore.reset();
    frontFilaments.reset();

    final r0 = layout.fieldRadius * (1 + 0.05 * v.bass + 0.25 * (v.orbScale - 1));
    ribbonRadius = r0;
    final cx = layout.orbCenter.dx;
    final cy = layout.orbCenter.dy;
    const twoPi = math.pi * 2;

    for (final spec in _ribbons) {
      final ph = v.ribbonPhase * spec.speed + spec.seed;
      final ax = 0.42 + 0.3 * organic(ph * 0.23, spec.seed) + 0.22 * v.bass * math.sin(ph * 1.3);
      final ay = 0.42 * organic(ph * 0.19, spec.seed + 2);
      final az = spec.spin * ph * 0.35 + 0.8 * organic(ph * 0.11, spec.seed + 4);
      final sxA = math.sin(ax), cxA = math.cos(ax);
      final syA = math.sin(ay), cyA = math.cos(ay);
      final szA = math.sin(az), czA = math.cos(az);

      for (var k = 0; k < _strands; k++) {
        final phk = ph - k * 0.27;
        final rk = r0 * spec.radius * (1 + (k - 1.5) * 0.024);
        final isCore = k == 0;
        final back = isCore ? backCore : backFilaments;
        final front = isCore ? frontCore : frontFilaments;

        var prevFront = false;
        var prevX = 0.0, prevY = 0.0;
        for (var j = 0; j <= _ribbonSamples; j++) {
          final theta = j / _ribbonSamples * twoPi;
          final deform = 1 +
              spec.lobeDepth * math.sin(spec.lobes * theta + phk * 0.7) +
              v.mid * 0.16 * math.sin((spec.lobes + 2) * theta - phk * 1.1 + spec.seed) +
              0.035 * math.sin(3 * theta + phk * 1.9 + k) +
              v.treble * 0.025 * math.sin(11 * theta + v.time * 7 + k);
          final rr = rk * deform;
          final x = rr * math.cos(theta);
          final y = rr * math.sin(theta);
          final z = r0 * spec.twist * math.sin(2 * theta + phk * 0.5);

          final x1 = x * czA - y * szA;
          final y1 = x * szA + y * czA;
          final y2 = y1 * cxA - z * sxA;
          final z2 = y1 * sxA + z * cxA;
          final x3 = x1 * cyA + z2 * syA;
          final z3 = -x1 * syA + z2 * cyA;

          final persp = 1 / (1 - z3 / (r0 * 3.6));
          final px = cx + x3 * persp;
          final py = cy + y2 * persp;
          final isFront = z3 >= 0;

          if (j == 0) {
            (isFront ? front : back).moveTo(px, py);
          } else if (isFront == prevFront) {
            (isFront ? front : back).lineTo(px, py);
          } else {
            (prevFront ? front : back).lineTo(px, py);
            (isFront ? front : back)
              ..moveTo(prevX, prevY)
              ..lineTo(px, py);
          }
          prevFront = isFront;
          prevX = px;
          prevY = py;
        }
      }
    }
  }

  void _updateCoreFilaments(AudioVisualState v, NexusLayout layout) {
    coreFilaments.reset();
    final cx = layout.orbCenter.dx;
    final cy = layout.orbCenter.dy;
    final core = layout.coreRadius * v.orbScale;
    for (var a = 0; a < 5; a++) {
      final start = v.ribbonPhase * (0.7 + 0.25 * a) * (a.isEven ? 1 : -1) + a * 1.26;
      final sweep = 1.1 + 0.6 * organic(v.time * 0.4, a.toDouble());
      final radius = core * (1.4 + 0.32 * a);
      const steps = 22;
      for (var i = 0; i <= steps; i++) {
        final t = start + sweep * i / steps;
        final jitter = 1 +
            0.06 * math.sin(t * 5 + v.time * 2 + a) +
            v.treble * 0.1 * math.sin(t * 13 + v.time * 9);
        final px = cx + math.cos(t) * radius * jitter;
        final py = cy + math.sin(t) * radius * jitter * 0.92;
        if (i == 0) {
          coreFilaments.moveTo(px, py);
        } else {
          coreFilaments.lineTo(px, py);
        }
      }
    }
  }

  void _updateStream(AudioVisualState v, NexusLayout layout) {
    for (final p in streamGroups) {
      p.reset();
    }
    streamAll.reset();
    final r = layout.fieldRadius;
    final start = layout.streamStart;
    final end = layout.streamEnd;
    _p0x = start.dx;
    _p0y = start.dy;
    _p3x = end.dx;
    _p3y = end.dy;
    _p1x = _p0x + r * 0.34 * organic(v.time * 0.35, 2);
    _p1y = _p0y - (_p0y - _p3y) * 0.42;
    _p2x = _p3x - r * 0.62 + r * 0.18 * organic(v.time * 0.27, 5);
    _p2y = _p3y + r * 0.86;
    streamSpread = r * 0.17 * (0.55 + 0.75 * v.streamEnergy);
    streamWiggle = r * (0.025 + 0.03 * v.amplitude);
    _streamPhase = v.streamPhase;

    for (var s = 0; s < streamStrands; s++) {
      final u = s / (streamStrands - 1) * 2 - 1;
      final group = u < -0.34 ? 0 : (u > 0.34 ? 2 : 1);
      final path = streamGroups[group];
      for (var i = 0; i <= _streamSamples; i++) {
        streamAt(i / _streamSamples, u, strand: s.toDouble());
        if (i == 0) {
          path.moveTo(outX, outY);
          streamAll.moveTo(outX, outY);
        } else {
          path.lineTo(outX, outY);
          streamAll.lineTo(outX, outY);
        }
      }
    }
  }

  /// Point on the energy stream: [t] 0 = microphone, 1 = core; [u] -1..1
  /// lateral strand offset. Result in [outX], [outY].
  void streamAt(double t, double u, {double strand = 0}) {
    final it = 1 - t;
    final b0 = it * it * it;
    final b1 = 3 * it * it * t;
    final b2 = 3 * it * t * t;
    final b3 = t * t * t;
    final x = b0 * _p0x + b1 * _p1x + b2 * _p2x + b3 * _p3x;
    final y = b0 * _p0y + b1 * _p1y + b2 * _p2y + b3 * _p3y;

    final d0 = 3 * it * it;
    final d1 = 6 * it * t;
    final d2 = 3 * t * t;
    var dx = d0 * (_p1x - _p0x) + d1 * (_p2x - _p1x) + d2 * (_p3x - _p2x);
    var dy = d0 * (_p1y - _p0y) + d1 * (_p2y - _p1y) + d2 * (_p3y - _p2y);
    final len = math.sqrt(dx * dx + dy * dy);
    if (len > 1e-6) {
      dx /= len;
      dy /= len;
    }
    final envelope = math.pow(math.sin(math.pi * t), 0.85).toDouble();
    final lateral = u * streamSpread * envelope +
        streamWiggle * envelope * math.sin(t * 9 - _streamPhase * 4 + strand * 1.7);
    outX = x - dy * lateral;
    outY = y + dx * lateral;
  }

  void _updateWave(AudioVisualState v, NexusLayout layout) {
    waveMain.reset();
    waveLayers.reset();
    waveHairlines.reset();
    final rect = layout.waveRect;
    final half = rect.height / 2;
    waveLeft = rect.left;
    waveWidth = rect.width;
    waveCenterY = rect.center.dy;
    const twoPi = math.pi * 2;
    const ampScale = <double>[1.0, 0.72, 0.5, 0.34];
    const freq = <double>[1.6, 2.4, 3.3, 1.15];
    const speed = <double>[1.0, 1.35, 0.8, 1.7];

    for (var i = 0; i <= waveSamples; i++) {
      final x01 = i / waveSamples;
      final u = (x01 - 0.5).abs() * 2;
      final b = v.band(u * 0.95);
      waveAmp[i] = half * _waveEnvelope[i] * (0.06 + v.waveEnergy * (0.32 + 0.8 * b));
    }

    for (var l = 0; l < 4; l++) {
      final path = l == 0 ? waveMain : waveLayers;
      for (var i = 0; i <= waveSamples; i++) {
        final x01 = i / waveSamples;
        final u = (x01 - 0.5).abs() * 2;
        final carrier =
            math.sin(twoPi * u * freq[l] * 2 + v.wavePhase * speed[l] + l * 1.3) * 0.75 +
                0.25 * math.sin(twoPi * u * freq[l] * 4.7 - v.wavePhase * 0.6 * speed[l] + l);
        final dy = (waveAmp[i] * carrier * ampScale[l]).clamp(-half, half);
        final px = rect.left + x01 * rect.width;
        final py = waveCenterY - dy;
        if (l == 0) waveY[i] = py;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
    }

    const hairCount = 96;
    for (var k = 0; k < hairCount; k++) {
      final x01 = (k + 0.5) / hairCount;
      final i = (x01 * waveSamples).round();
      final jitter = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(k * 12.9898 + v.wavePhase * 0.8));
      final h = (waveAmp[i] * 0.95 * jitter).clamp(0.0, half);
      if (h < 0.6) continue;
      final px = rect.left + x01 * rect.width;
      waveHairlines
        ..moveTo(px, waveCenterY - h)
        ..lineTo(px, waveCenterY + h);
    }
  }

  /// Waveform height at horizontal position [x] (screen coordinates).
  double waveYAt(double x) {
    final x01 = ((x - waveLeft) / waveWidth).clamp(0.0, 1.0);
    return waveY[(x01 * waveSamples).round()];
  }
}
