import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'analyzer_worker_inline.dart'
    if (dart.library.io) 'analyzer_worker_isolate.dart';
import 'audio_feature_frame.dart';

enum AudioChannel { input, output }

enum MicStatus { unknown, ready, denied, unavailable }

/// Captures real microphone PCM, analyses it off the UI thread and exposes
/// the latest normalised features per channel. It also accepts external audio
/// (TTS PCM, STT sound levels) so the AI voice drives the same visual system.
class AudioAnalyzer {
  AudioAnalyzer({this.sampleRate = 16000});

  final int sampleRate;
  final AudioFeatureFrame input = AudioFeatureFrame();
  final AudioFeatureFrame output = AudioFeatureFrame();
  final ValueNotifier<MicStatus> micStatus = ValueNotifier(MicStatus.unknown);

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _micSubscription;
  AnalyzerWorker? _worker;
  Future<void>? _initializing;
  bool _disposed = false;

  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    _worker = await AnalyzerWorker.spawn(_onFeatures);
    if (_disposed) {
      _worker?.dispose();
      return;
    }
    try {
      _recorder = AudioRecorder();
      final granted = await _recorder!.hasPermission(request: false);
      micStatus.value = granted ? MicStatus.ready : MicStatus.unknown;
    } catch (_) {
      micStatus.value = MicStatus.unavailable;
    }
  }

  bool get isCapturing => _micSubscription != null;

  /// Starts streaming the microphone into the analyzer. Returns false when the
  /// permission is denied or no input device exists.
  Future<bool> startMicrophone() async {
    await init();
    final recorder = _recorder;
    if (recorder == null || _disposed) return false;
    if (_micSubscription != null) return true;
    try {
      if (!await recorder.hasPermission()) {
        micStatus.value = MicStatus.denied;
        return false;
      }
      final stream = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _micSubscription = stream.listen(
        (chunk) => feedPcm16(AudioChannel.input, chunk, sampleRate: sampleRate),
        onError: (Object _) => micStatus.value = MicStatus.unavailable,
      );
      micStatus.value = MicStatus.ready;
      return true;
    } catch (_) {
      micStatus.value = MicStatus.unavailable;
      return false;
    }
  }

  Future<void> stopMicrophone() async {
    final subscription = _micSubscription;
    _micSubscription = null;
    await subscription?.cancel();
    try {
      await _recorder?.stop();
    } catch (_) {}
  }

  /// Feed raw little-endian mono PCM16 (e.g. your TTS output buffer).
  void feedPcm16(AudioChannel channel, Uint8List bytes, {int? sampleRate}) {
    if (bytes.lengthInBytes < 4) return;
    _worker?.process(channel.index, bytes, sampleRate ?? this.sampleRate);
  }

  /// Feed a 0..1 loudness value when only a level is available.
  void feedLevel(AudioChannel channel, double level) => _frame(channel).applyLevel(level);

  /// Feed a decaying envelope hit (e.g. a TTS word-boundary callback).
  void pulse(AudioChannel channel, [double strength = 1]) => _frame(channel).pulse(strength);

  AudioFeatureFrame _frame(AudioChannel channel) =>
      channel == AudioChannel.input ? input : output;

  void _onFeatures(int channel, Float32List features) {
    if (_disposed) return;
    (channel == AudioChannel.input.index ? input : output).applyFeatures(features);
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopMicrophone();
    await _recorder?.dispose();
    _worker?.dispose();
    micStatus.dispose();
  }
}
