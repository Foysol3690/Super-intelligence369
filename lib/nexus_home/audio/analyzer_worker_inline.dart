import 'dart:typed_data';

import 'feature_extractor.dart';

typedef FeatureCallback = void Function(int channel, Float32List features);

/// Web fallback: browsers have no Dart isolates, so analysis runs inline.
/// A 1024-point FFT per audio chunk is well under a millisecond.
class AnalyzerWorker {
  AnalyzerWorker._(this._onFeatures);

  final FeatureCallback _onFeatures;
  final Map<int, FeatureExtractor> _extractors = <int, FeatureExtractor>{};

  static Future<AnalyzerWorker> spawn(FeatureCallback onFeatures) async =>
      AnalyzerWorker._(onFeatures);

  void process(int channel, Uint8List pcm16, int sampleRate) {
    final extractor = _extractors.putIfAbsent(
      channel,
      () => FeatureExtractor(sampleRate: sampleRate),
    )..setSampleRate(sampleRate);
    _onFeatures(channel, extractor.process(pcm16));
  }

  void dispose() => _extractors.clear();
}
