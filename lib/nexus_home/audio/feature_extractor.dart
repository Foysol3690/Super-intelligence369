import 'dart:math' as math;
import 'dart:typed_data';

import '../core/audio_visual_state.dart';

/// Layout of the Float32List produced by [FeatureExtractor.process].
abstract final class FeatureIndex {
  static const int level = 0;
  static const int bass = 1;
  static const int mid = 2;
  static const int treble = 3;
  static const int bands = 4;
  static const int length = bands + kNexusBandCount;
}

/// Pure-Dart RMS + FFT analysis of PCM16 mono audio. Runs inside a background
/// isolate on mobile (see analyzer_worker_isolate.dart) so the UI thread never
/// does audio maths. Output values are normalised to 0..1 with an adaptive
/// noise floor and auto-gain, so quiet rooms and loud voices both read well.
class FeatureExtractor {
  FeatureExtractor({this.sampleRate = 16000}) {
    for (var i = 0; i < _n; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_n - 1));
    }
    for (var i = 0; i < _n ~/ 2; i++) {
      _cos[i] = math.cos(-2 * math.pi * i / _n);
      _sin[i] = math.sin(-2 * math.pi * i / _n);
    }
    var j = 0;
    for (var i = 0; i < _n; i++) {
      _bitReverse[i] = j;
      var bit = _n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j |= bit;
    }
    _configureBands();
  }

  static const int _n = 1024;
  int sampleRate;

  final Float32List _ring = Float32List(_n);
  int _ringPos = 0;

  final Float64List _re = Float64List(_n);
  final Float64List _im = Float64List(_n);
  final Float64List _window = Float64List(_n);
  final Float64List _cos = Float64List(_n ~/ 2);
  final Float64List _sin = Float64List(_n ~/ 2);
  final Int32List _bitReverse = Int32List(_n);
  final Float64List _mag = Float64List(_n ~/ 2);

  final Int32List _bandLo = Int32List(kNexusBandCount);
  final Int32List _bandHi = Int32List(kNexusBandCount);

  late final List<_AutoGain> _gains = List<_AutoGain>.generate(
    FeatureIndex.length,
    (i) => i == FeatureIndex.level ? _AutoGain(floor: -58, range: 34) : _AutoGain(),
    growable: false,
  );

  final Float32List _out = Float32List(FeatureIndex.length);

  void _configureBands() {
    final binHz = sampleRate / _n;
    const minHz = 60.0;
    final maxHz = math.min(7200.0, sampleRate / 2 - binHz);
    for (var b = 0; b < kNexusBandCount; b++) {
      final lo = minHz * math.pow(maxHz / minHz, b / kNexusBandCount);
      final hi = minHz * math.pow(maxHz / minHz, (b + 1) / kNexusBandCount);
      final loBin = (lo / binHz).floor().clamp(1, _n ~/ 2 - 1);
      final hiBin = math.max((hi / binHz).ceil(), loBin + 1).clamp(2, _n ~/ 2);
      _bandLo[b] = loBin;
      _bandHi[b] = hiBin;
    }
  }

  void setSampleRate(int rate) {
    if (rate == sampleRate) return;
    sampleRate = rate;
    _configureBands();
  }

  /// Consumes little-endian PCM16 bytes and returns the feature vector.
  /// The returned list is reused between calls; copy it if you keep it.
  Float32List process(Uint8List pcm16) {
    final data = ByteData.sublistView(pcm16);
    final count = pcm16.lengthInBytes ~/ 2;
    if (count == 0) return _out;

    var sumSquares = 0.0;
    for (var i = 0; i < count; i++) {
      final s = data.getInt16(i * 2, Endian.little) / 32768.0;
      sumSquares += s * s;
      _ring[_ringPos] = s;
      _ringPos = (_ringPos + 1) & (_n - 1);
    }
    final rms = math.sqrt(sumSquares / count);
    _out[FeatureIndex.level] = _gains[FeatureIndex.level].normalize(_db(rms * rms));

    _fft();

    var bass = 0.0, mid = 0.0, treble = 0.0;
    final binHz = sampleRate / _n;
    for (var k = 1; k < _n ~/ 2; k++) {
      final p = _mag[k];
      final hz = k * binHz;
      if (hz < 250) {
        bass += p;
      } else if (hz < 2000) {
        mid += p;
      } else if (hz < 7500) {
        treble += p;
      }
    }
    // Per-band auto-gain alone lets FFT leakage saturate quiet bands, so each
    // range is also weighted by its share of the dominant range's power.
    final dominant = math.max(bass, math.max(mid, treble)) + 1e-12;
    double balance(double p) => math.pow(p / dominant, 0.35).toDouble();
    _out[FeatureIndex.bass] = _gains[FeatureIndex.bass].normalize(_db(bass)) * balance(bass);
    _out[FeatureIndex.mid] = _gains[FeatureIndex.mid].normalize(_db(mid)) * balance(mid);
    _out[FeatureIndex.treble] =
        _gains[FeatureIndex.treble].normalize(_db(treble)) * balance(treble);

    for (var b = 0; b < kNexusBandCount; b++) {
      var e = 0.0;
      for (var k = _bandLo[b]; k < _bandHi[b]; k++) {
        e += _mag[k];
      }
      final idx = FeatureIndex.bands + b;
      _out[idx] = _gains[idx].normalize(_db(e / (_bandHi[b] - _bandLo[b])));
    }
    return _out;
  }

  void _fft() {
    for (var i = 0; i < _n; i++) {
      final src = (_ringPos + i) & (_n - 1);
      _re[_bitReverse[i]] = _ring[src] * _window[i];
      _im[_bitReverse[i]] = 0;
    }
    for (var size = 2; size <= _n; size <<= 1) {
      final half = size >> 1;
      final step = _n ~/ size;
      for (var start = 0; start < _n; start += size) {
        for (var k = 0; k < half; k++) {
          final wr = _cos[k * step];
          final wi = _sin[k * step];
          final a = start + k;
          final b = a + half;
          final tr = _re[b] * wr - _im[b] * wi;
          final ti = _re[b] * wi + _im[b] * wr;
          _re[b] = _re[a] - tr;
          _im[b] = _im[a] - ti;
          _re[a] += tr;
          _im[a] += ti;
        }
      }
    }
    for (var k = 0; k < _n ~/ 2; k++) {
      _mag[k] = _re[k] * _re[k] + _im[k] * _im[k];
    }
  }

  static double _db(double power) => 10 * math.log(power + 1e-12) / math.ln10;
}

/// Tracks a slowly rising noise floor and a decaying peak so the 0..1 output
/// adapts to the room and the speaker instead of using a fixed threshold.
class _AutoGain {
  // ignore: prefer_initializing_formals
  _AutoGain({double? floor, this.range = 30}) : _floor = floor;

  final double range;
  double? _floor;
  double? _peak;

  double normalize(double db) {
    final floor = _floor ??= db;
    _floor = db < floor ? floor + (db - floor) * 0.35 : floor + 0.015;
    final minPeak = _floor! + range;
    var peak = _peak ?? minPeak;
    peak = db > peak ? db : peak - 0.04;
    if (peak < minPeak) peak = minPeak;
    _peak = peak;
    final gate = _floor! + 3;
    final v = (db - gate) / (peak - gate);
    return v.clamp(0.0, 1.0).toDouble();
  }
}
