import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/audio_visual_state.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';
import 'energy_geometry.dart';

abstract final class _Kind {
  static const int dead = 0;
  static const int ambient = 1;
  static const int orbit = 2;
  static const int stream = 3;
  static const int inflow = 4;
  static const int wave = 5;
}

/// Fixed-size, allocation-free particle pool in struct-of-arrays layout.
/// Each particle has velocity, direction, lifespan, fade and depth. All
/// particles render through two drawRawAtlas calls (back + front layer),
/// so cost stays flat no matter how many are alive.
class ParticleSystem {
  static const int capacity = 420;
  static const int _ambientCount = 80;
  static const double spriteSize = 32;

  final Uint8List _kind = Uint8List(capacity);
  final Float32List _x = Float32List(capacity);
  final Float32List _y = Float32List(capacity);
  final Float32List _a = Float32List(capacity); // vx | angle | stream t
  final Float32List _b = Float32List(capacity); // vy | angular vel | stream u
  final Float32List _c = Float32List(capacity); // radius | stream speed
  final Float32List _life = Float32List(capacity);
  final Float32List _maxLife = Float32List(capacity);
  final Float32List _size = Float32List(capacity);
  final Float32List _hue = Float32List(capacity);
  final Float32List _depth = Float32List(capacity);
  final Float32List _seed = Float32List(capacity);

  final ParticleBatch back = ParticleBatch(capacity);
  final ParticleBatch front = ParticleBatch(capacity);

  final math.Random _rng = math.Random(42);
  int _cursor = 0;
  double _emitOrbit = 0, _emitStream = 0, _emitInflow = 0, _emitWave = 0;
  bool _seeded = false;
  NexusLayout? _layout;

  void resize(NexusLayout layout) {
    final previous = _layout;
    _layout = layout;
    if (previous == null || !_seeded) return;
    final sx = layout.size.width / previous.size.width;
    final sy = layout.size.height / previous.size.height;
    for (var i = 0; i < capacity; i++) {
      if (_kind[i] == _Kind.ambient) {
        _x[i] *= sx;
        _y[i] *= sy;
      }
    }
  }

  double _r() => _rng.nextDouble();

  int _alloc() {
    for (var n = 0; n < capacity; n++) {
      final i = (_cursor + n) % capacity;
      if (_kind[i] == _Kind.dead) {
        _cursor = (i + 1) % capacity;
        return i;
      }
    }
    return -1;
  }

  void _seedAmbient(NexusLayout layout) {
    for (var n = 0; n < _ambientCount; n++) {
      final i = _alloc();
      if (i < 0) return;
      _kind[i] = _Kind.ambient;
      _x[i] = _r() * layout.size.width;
      _y[i] = _r() * layout.size.height;
      _a[i] = (_r() - 0.5) * 6;
      _b[i] = -2 - _r() * 6;
      _size[i] = 0.6 + _r() * 1.6;
      _hue[i] = _r();
      _depth[i] = _r();
      _seed[i] = _r() * 100;
      _life[i] = 0;
      _maxLife[i] = 1;
    }
    _seeded = true;
  }

  void update(double dt, AudioVisualState v, NexusLayout layout, EnergyGeometry geo) {
    if (!_seeded) _seedAmbient(layout);
    _emit(dt, v, layout);

    final cx = layout.orbCenter.dx;
    final cy = layout.orbCenter.dy;
    final w = layout.size.width;
    final h = layout.size.height;
    final scale = layout.scale;
    final flow = v.flowDirection;
    back.count = 0;
    front.count = 0;

    for (var i = 0; i < capacity; i++) {
      final kind = _kind[i];
      if (kind == _Kind.dead) continue;
      var alpha = 1.0;
      var size = _size[i];

      switch (kind) {
        case _Kind.ambient:
          final drift = 0.35 + v.particleEnergy * 1.4;
          _x[i] += (_a[i] + organic(v.time * 0.2, _seed[i]) * 4) * dt * drift;
          _y[i] += _b[i] * dt * drift;
          if (_y[i] < -4) _y[i] = h + 4;
          if (_x[i] < -4) _x[i] = w + 4;
          if (_x[i] > w + 4) _x[i] = -4;
          final dx = _x[i] - cx, dy = _y[i] - cy;
          final near = math.exp(-(dx * dx + dy * dy) / (layout.fieldRadius * layout.fieldRadius * 2.2));
          alpha = (0.18 + 0.22 * (0.5 + 0.5 * math.sin(v.time * 1.3 + _seed[i]))) *
              (0.7 + 0.3 * v.glow + near * v.particleEnergy * 1.2);
        case _Kind.orbit:
          _life[i] += dt;
          _a[i] += _b[i] * dt * (0.6 + v.particleEnergy + v.bass * 0.6);
          final r = _c[i] * geo.ribbonRadius;
          _x[i] = cx + math.cos(_a[i]) * r;
          _y[i] = cy + math.sin(_a[i]) * r * 0.9;
          _depth[i] = 0.5 + 0.5 * math.sin(_a[i]);
          _hue[i] = (1 + math.cos(_a[i])) * 0.5;
          alpha = _fade(i) * (0.55 + 0.45 * v.treble);
        case _Kind.stream:
          _life[i] += dt;
          final dir = flow.abs() < 0.12 ? 0.25 : flow;
          _a[i] += dir * _c[i] * dt * (0.55 + v.amplitude * 1.6);
          final t = _a[i];
          if (t < 0 || t > 1) {
            _kind[i] = _Kind.dead;
            continue;
          }
          geo.streamAt(t, _b[i], strand: _seed[i]);
          _x[i] = geo.outX;
          _y[i] = geo.outY;
          final ends = math.min(t, 1 - t);
          alpha = math.min(1.0, ends * 8) * (0.55 + 0.45 * v.streamEnergy);
          size *= 0.75 + v.amplitude * 0.8;
        case _Kind.inflow:
          _life[i] += dt;
          _a[i] += _b[i] * dt;
          _c[i] -= dt * (0.32 + v.wProcessing * 0.5);
          if (_c[i] < 0.12) {
            _kind[i] = _Kind.dead;
            continue;
          }
          final r = _c[i] * layout.fieldRadius;
          _x[i] = cx + math.cos(_a[i]) * r;
          _y[i] = cy + math.sin(_a[i]) * r * 0.92;
          _depth[i] = 0.5 + 0.5 * math.sin(_a[i]);
          alpha = _fade(i) * math.min(1.0, _c[i] * 2.5);
        case _Kind.wave:
          _life[i] += dt;
          _x[i] += _a[i] * dt;
          _y[i] += _b[i] * dt;
          alpha = _fade(i) * (0.4 + 0.6 * v.waveEnergy);
      }

      if (kind != _Kind.ambient && _life[i] >= _maxLife[i]) {
        _kind[i] = _Kind.dead;
        continue;
      }
      if (alpha <= 0.01) continue;
      final batch = _depth[i] < 0.45 ? back : front;
      batch.add(
        _x[i],
        _y[i],
        size * scale * 2.4 / spriteSize,
        NexusPalette.spectrumArgb(_hue[i], alpha, v.coolness),
      );
    }
  }

  double _fade(int i) {
    final t = _life[i] / _maxLife[i];
    if (t < 0.15) return t / 0.15;
    if (t > 0.7) return math.max(0.0, (1 - t) / 0.3);
    return 1;
  }

  void _emit(double dt, AudioVisualState v, NexusLayout layout) {
    final talk = v.wListening + v.wSpeaking;
    _emitOrbit += dt * (8 + 70 * v.particleEnergy + 55 * v.treble);
    _emitStream += dt * (2.5 + talk * (6 + 120 * v.amplitude));
    _emitInflow += dt * (v.wProcessing * 70 + v.wThinking * 14);
    _emitWave += dt * (2 + 70 * v.waveEnergy);

    while (_emitOrbit >= 1) {
      _emitOrbit -= 1;
      final i = _alloc();
      if (i < 0) break;
      _kind[i] = _Kind.orbit;
      _a[i] = _r() * math.pi * 2;
      _b[i] = (0.3 + _r() * 0.9) * (_r() < 0.5 ? -1 : 1);
      _c[i] = 0.5 + _r() * 0.6;
      _life[i] = 0;
      _maxLife[i] = 1.2 + _r() * 2.2;
      _size[i] = 0.8 + _r() * (1.4 + v.treble * 1.6);
    }

    while (_emitStream >= 1) {
      _emitStream -= 1;
      final i = _alloc();
      if (i < 0) break;
      final inward = v.flowDirection >= -0.12;
      _kind[i] = _Kind.stream;
      _a[i] = inward ? 0.0 : 1.0;
      _b[i] = (_r() * 2 - 1) * 0.95;
      _c[i] = 0.35 + _r() * 0.5;
      _life[i] = 0;
      _maxLife[i] = 6;
      _size[i] = 1.0 + _r() * 1.8;
      _hue[i] = 0.08 + (_b[i] + 1) * 0.5 * 0.75;
      _depth[i] = 1;
      _seed[i] = _r() * 9;
    }

    while (_emitInflow >= 1) {
      _emitInflow -= 1;
      final i = _alloc();
      if (i < 0) break;
      _kind[i] = _Kind.inflow;
      _a[i] = _r() * math.pi * 2;
      _b[i] = 0.6 + _r() * 0.8;
      _c[i] = 1.0 + _r() * 0.7;
      _life[i] = 0;
      _maxLife[i] = 4;
      _size[i] = 0.8 + _r() * 1.4;
      _hue[i] = _r();
    }

    while (_emitWave >= 1) {
      _emitWave -= 1;
      final i = _alloc();
      if (i < 0) break;
      final x01 = _r();
      final x = layout.waveRect.left + x01 * layout.waveRect.width;
      _kind[i] = _Kind.wave;
      _x[i] = x;
      _y[i] = layout.waveRect.center.dy + (_r() - 0.5) * layout.waveRect.height * 0.5 * v.waveEnergy;
      final towardMic = (layout.micCenter.dx - x) * 0.35 * v.flowDirection;
      _a[i] = towardMic + (_r() - 0.5) * 10;
      _b[i] = -6 - _r() * 18 * (0.4 + v.waveEnergy);
      _life[i] = 0;
      _maxLife[i] = 0.8 + _r() * 1.2;
      _size[i] = 0.7 + _r() * 1.3;
      _hue[i] = x01 < 0.5 ? 0.02 + x01 * 0.3 : 0.83 + (x01 - 0.5) * 0.3;
      _depth[i] = 1;
    }
  }
}

/// Packed buffers for one Canvas.drawRawAtlas call.
class ParticleBatch {
  ParticleBatch(int capacity)
      : transforms = Float32List(capacity * 4),
        rects = Float32List(capacity * 4),
        colors = Int32List(capacity) {
    for (var i = 0; i < capacity; i++) {
      rects[i * 4 + 2] = ParticleSystem.spriteSize;
      rects[i * 4 + 3] = ParticleSystem.spriteSize;
    }
  }

  final Float32List transforms;
  final Float32List rects;
  final Int32List colors;
  int count = 0;

  void add(double x, double y, double scale, int argb) {
    final o = count * 4;
    final half = ParticleSystem.spriteSize * scale / 2;
    transforms[o] = scale;
    transforms[o + 1] = 0;
    transforms[o + 2] = x - half;
    transforms[o + 3] = y - half;
    colors[count] = argb;
    count++;
  }

  void draw(ui.Canvas canvas, ui.Image sprite, ui.Paint paint) {
    if (count == 0) return;
    canvas.drawRawAtlas(
      sprite,
      Float32List.sublistView(transforms, 0, count * 4),
      Float32List.sublistView(rects, 0, count * 4),
      Int32List.sublistView(colors, 0, count),
      ui.BlendMode.modulate,
      null,
      paint,
    );
  }
}
