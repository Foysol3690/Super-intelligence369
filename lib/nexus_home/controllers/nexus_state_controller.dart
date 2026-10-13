import 'package:flutter/foundation.dart';

import '../audio/audio_analyzer.dart';
import '../bridge/nexus_voice_bridge.dart';
import '../core/nexus_assistant_state.dart';

/// Owns the assistant state machine and the audio analyzer. This is the only
/// object your app logic needs to talk to.
class NexusStateController {
  NexusStateController({NexusVoiceBridge? bridge, AudioAnalyzer? analyzer})
      : analyzer = analyzer ?? AudioAnalyzer(),
        // Keeps the public `bridge:` parameter name while the field stays private.
        // ignore: prefer_initializing_formals
        _bridge = bridge {
    _bridge?.attach(this);
  }

  final AudioAnalyzer analyzer;
  final NexusVoiceBridge? _bridge;
  final ValueNotifier<NexusAssistantState> state =
      ValueNotifier(NexusAssistantState.idle);

  NexusAssistantState get current => state.value;

  bool get _internalMic => _bridge?.usesInternalMicrophone ?? true;

  Future<void> init() => analyzer.init();

  /// Single entry point for taps on the orb or the microphone.
  Future<void> onCoreTap() async {
    switch (current) {
      case NexusAssistantState.idle:
        await startListening();
      case NexusAssistantState.listening:
        await stopListening();
      case NexusAssistantState.speaking:
        await interrupt();
      case NexusAssistantState.processing:
      case NexusAssistantState.thinking:
        break;
    }
  }

  /// Also call this from your wake-word ("MAYA") detector.
  Future<void> wakeWordDetected() async {
    if (current == NexusAssistantState.idle || current == NexusAssistantState.speaking) {
      if (current == NexusAssistantState.speaking) await _bridge?.onInterrupted();
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (current == NexusAssistantState.listening) return;
    analyzer.input.reset();
    state.value = NexusAssistantState.listening;
    if (_internalMic) await analyzer.startMicrophone();
    await _bridge?.onListeningStarted();
  }

  Future<void> stopListening() async {
    if (current != NexusAssistantState.listening) return;
    state.value = NexusAssistantState.processing;
    if (_internalMic) await analyzer.stopMicrophone();
    await _bridge?.onListeningStopped();
  }

  Future<void> interrupt() async {
    await _bridge?.onInterrupted();
    analyzer.output.reset();
    await startListening();
  }

  void setProcessing() => state.value = NexusAssistantState.processing;
  void setThinking() => state.value = NexusAssistantState.thinking;

  void beginSpeaking() {
    analyzer.output.reset();
    state.value = NexusAssistantState.speaking;
  }

  void endSpeaking() {
    if (current == NexusAssistantState.speaking) state.value = NexusAssistantState.idle;
  }

  void setIdle() => state.value = NexusAssistantState.idle;

  // Input (user voice) when your STT owns the microphone.
  void feedInputLevel(double level) => analyzer.feedLevel(AudioChannel.input, level);
  void feedInputPcm16(Uint8List pcm, {int? sampleRate}) =>
      analyzer.feedPcm16(AudioChannel.input, pcm, sampleRate: sampleRate);

  // Output (AI voice). PCM gives full FFT reactivity; levels / word pulses
  // work for TTS engines that hide their audio buffer.
  void feedOutputPcm16(Uint8List pcm, {int? sampleRate}) =>
      analyzer.feedPcm16(AudioChannel.output, pcm, sampleRate: sampleRate);
  void feedOutputLevel(double level) => analyzer.feedLevel(AudioChannel.output, level);
  void ttsWordPulse([double strength = 1]) => analyzer.pulse(AudioChannel.output, strength);

  Future<void> dispose() async {
    _bridge?.detach();
    _bridge?.dispose();
    state.dispose();
    await analyzer.dispose();
  }
}
