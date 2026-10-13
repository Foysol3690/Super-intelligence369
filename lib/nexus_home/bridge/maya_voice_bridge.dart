import 'dart:async';

import '../../core/maya_controller.dart';
import '../../core/maya_state.dart';
import '../controllers/nexus_state_controller.dart';
import '../core/nexus_assistant_state.dart';
import 'nexus_voice_bridge.dart';

/// Bridges [MayaController] (STT -> Gemini/UnifiedAI -> TTS) to the NEXUS visual system.
class MayaVoiceBridge extends NexusVoiceBridge {
  MayaVoiceBridge({required this.maya});

  final MayaController maya;
  bool _syncing = false;

  @override
  bool get usesInternalMicrophone => false;

  @override
  void attach(NexusStateController controller) {
    super.attach(controller);
    maya.addListener(_syncMayaState);
    maya.level.addListener(_syncLevel);
    _syncMayaState();
  }

  @override
  void detach() {
    maya.removeListener(_syncMayaState);
    maya.level.removeListener(_syncLevel);
    super.detach();
  }

  void _syncMayaState() {
    if (!isAttached || _syncing) return;
    _syncing = true;
    try {
      switch (maya.state) {
        case OrbState.idle:
          if (controller.current != NexusAssistantState.idle) {
            controller.setIdle();
          }
          break;
        case OrbState.listening:
          if (controller.current != NexusAssistantState.listening) {
            controller.state.value = NexusAssistantState.listening;
          }
          break;
        case OrbState.thinking:
          if (controller.current != NexusAssistantState.thinking) {
            controller.setThinking();
          }
          break;
        case OrbState.speaking:
          if (controller.current != NexusAssistantState.speaking) {
            controller.beginSpeaking();
          }
          break;
        case OrbState.error:
          if (controller.current != NexusAssistantState.idle) {
            controller.setIdle();
          }
          break;
      }
    } finally {
      _syncing = false;
    }
  }

  void _syncLevel() {
    if (!isAttached) return;
    final lvl = maya.level.value;
    if (maya.state == OrbState.listening) {
      controller.feedInputLevel(lvl);
    } else if (maya.state == OrbState.speaking) {
      controller.feedOutputLevel(lvl);
      if (lvl > 0.3) {
        controller.ttsWordPulse(lvl);
      }
    }
  }

  @override
  Future<void> onListeningStarted() async {
    if (maya.state != OrbState.listening) {
      await maya.toggle();
    }
  }

  @override
  Future<void> onListeningStopped() async {
    if (maya.state == OrbState.listening) {
      await maya.toggle();
    }
  }

  @override
  Future<void> onInterrupted() async {
    if (maya.state == OrbState.speaking) {
      await maya.toggle();
    }
  }
}
