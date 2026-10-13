import 'package:flutter/foundation.dart';

import '../controllers/nexus_state_controller.dart';

/// Adapter between the NEXUS visual layer and your existing AI/STT/TTS code.
///
/// The home screen only drives visuals. Subclass this, start/stop your speech
/// recognition in the callbacks, and report progress back through
/// [controller] (setThinking, beginSpeaking, feedOutputPcm16, endSpeaking ...).
abstract class NexusVoiceBridge {
  NexusStateController? _controller;

  NexusStateController get controller {
    final c = _controller;
    assert(c != null, 'NexusVoiceBridge used before NexusHome attached it.');
    return c!;
  }

  bool get isAttached => _controller != null;

  @mustCallSuper
  void attach(NexusStateController controller) => _controller = controller;

  @mustCallSuper
  void detach() => _controller = null;

  /// Return false if your STT engine needs exclusive microphone access
  /// (common on Android). NEXUS then skips its own capture and you feed
  /// levels with controller.feedInputLevel / feedInputPcm16 instead.
  bool get usesInternalMicrophone => true;

  /// The user tapped the core / mic, or a wake word fired. Start STT here.
  Future<void> onListeningStarted() async {}

  /// Listening ended. Stop STT and send the transcript to your AI. The screen
  /// is already in PROCESSING; call controller.setThinking() once the model is
  /// working and controller.beginSpeaking() when the reply audio starts.
  Future<void> onListeningStopped() async {}

  /// The user tapped while the AI was speaking. Stop your TTS here.
  Future<void> onInterrupted() async {}

  void dispose() {}
}
