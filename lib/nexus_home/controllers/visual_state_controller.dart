import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../audio/audio_feature_frame.dart';
import '../core/audio_visual_state.dart';
import '../core/nexus_assistant_state.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';
import '../render/energy_geometry.dart';
import '../render/particle_system.dart';
import 'nexus_state_controller.dart';

/// Converts assistant state + raw audio features into the smoothed
/// [AudioVisualState], advances the shared geometry and particle simulation,
/// and notifies the painters once per vsync. Painters listen to this directly
/// so no widgets rebuild during animation.
class VisualStateController extends ChangeNotifier {
  VisualStateController({
    required TickerProvider vsync,
    required this.nexus,
  }) {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  final NexusStateController nexus;
  final AudioVisualState visual = AudioVisualState();
  final EnergyGeometry geometry = EnergyGeometry();
  final ParticleSystem particles = ParticleSystem();

  /// Loaded asynchronously; painters fall back to gradients until ready.
  ui.FragmentShader? coreShader;

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  NexusLayout? _layout;

  NexusLayout? get layout => _layout;

  set layout(NexusLayout? value) {
    if (_layout == value) return;
    _layout = value;
    if (value != null) {
      particles.resize(value);
    }
  }

  Future<void> loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/nexus_core.frag');
      coreShader = program.fragmentShader();
    } catch (error) {
      debugPrint('NEXUS core shader unavailable, using gradient fallback: $error');
    }
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;
    dt = math.min(dt, 1 / 24);

    _advance(dt);
    final layout = _layout;
    if (layout != null) {
      geometry.update(visual, layout);
      particles.update(dt, visual, layout, geometry);
    }
    notifyListeners();
  }

  void _advance(double dt) {
    final v = visual;
    final s = nexus.current;

    const stateRate = 3.2;
    v.wIdle = approach(v.wIdle, s == NexusAssistantState.idle ? 1 : 0, stateRate, dt);
    v.wListening =
        approach(v.wListening, s == NexusAssistantState.listening ? 1 : 0, stateRate, dt);
    v.wProcessing =
        approach(v.wProcessing, s == NexusAssistantState.processing ? 1 : 0, stateRate, dt);
    v.wThinking =
        approach(v.wThinking, s == NexusAssistantState.thinking ? 1 : 0, stateRate * 0.8, dt);
    v.wSpeaking =
        approach(v.wSpeaking, s == NexusAssistantState.speaking ? 1 : 0, stateRate, dt);

    final now = NexusClock.micros;
    final input = nexus.analyzer.input;
    final output = nexus.analyzer.output;
    final inGain = v.wListening * input.freshness(now);
    final outFresh = output.freshness(now);
    final outPulse = output.pulseEnvelope(now);
    final outGain = v.wSpeaking;

    double mix(double a, double b) =>
        a * inGain + math.max(b * outFresh, outPulse) * outGain;

    v.amplitude = attackRelease(v.amplitude, mix(input.level, output.level), dt,
        attack: 24, release: 7);
    v.bass = attackRelease(v.bass, mix(input.bass, output.bass), dt, attack: 14, release: 4.5);
    v.mid = attackRelease(v.mid, mix(input.mid, output.mid), dt, attack: 16, release: 5);
    v.treble =
        attackRelease(v.treble, mix(input.treble, output.treble), dt, attack: 26, release: 8);
    for (var i = 0; i < kNexusBandCount; i++) {
      final x = i / (kNexusBandCount - 1);
      final pulseProfile = outPulse * (0.4 + 0.6 * math.exp(-math.pow((x - 0.35) / 0.3, 2)));
      final target = input.bands[i] * inGain +
          math.max(output.bands[i] * outFresh, pulseProfile) * outGain;
      v.bands[i] = attackRelease(v.bands[i], target, dt, attack: 26, release: 7);
    }

    v.time += dt;
    v.thinkingPulse = 0.5 + 0.5 * math.sin(v.time * 1.7);
    final a = v.amplitude;

    v.orbEnergy = v.wIdle * 0.18 +
        v.wListening * (0.3 + 0.62 * a) +
        v.wProcessing * 0.72 +
        v.wThinking * (0.4 + 0.2 * v.thinkingPulse) +
        v.wSpeaking * (0.36 + 0.62 * a);
    v.waveEnergy = v.wIdle * 0.05 +
        v.wListening * (0.1 + 0.95 * a) +
        v.wProcessing * 0.1 +
        v.wThinking * 0.07 +
        v.wSpeaking * (0.1 + 0.95 * a);
    v.particleEnergy = v.wIdle * 0.12 +
        v.wListening * (0.28 + 0.55 * a + 0.3 * v.treble) +
        v.wProcessing * 0.65 +
        v.wThinking * 0.28 +
        v.wSpeaking * (0.28 + 0.55 * a + 0.2 * v.treble);
    v.glow = approach(v.glow, 0.2 + 0.8 * v.orbEnergy, 4, dt);
    v.coolness = approach(v.coolness, v.wThinking + v.wProcessing * 0.4, 2.2, dt);
    v.flowDirection = approach(v.flowDirection, v.wListening - v.wSpeaking, 3, dt);

    final scaleTarget =
        1 + 0.16 * a + 0.07 * v.bass + v.wThinking * 0.06 * v.thinkingPulse + v.wProcessing * 0.08;
    const stiffness = 140.0;
    const damping = 13.0;
    v.orbScaleVelocity +=
        ((scaleTarget - v.orbScale) * stiffness - v.orbScaleVelocity * damping) * dt;
    v.orbScale += v.orbScaleVelocity * dt;

    final speed = (0.32 * v.wIdle +
            0.55 * v.wListening +
            1.05 * v.wProcessing +
            0.42 * v.wThinking +
            0.6 * v.wSpeaking +
            0.6 * v.bass) *
        (0.85 + 0.15 * organic(v.time * 0.3, 1.3));
    v.ribbonPhase += dt * speed;

    final travel = v.flowDirection.abs() < 0.15 ? 0.15 : v.flowDirection;
    v.wavePhase += dt * (1.1 + 4.2 * v.waveEnergy) * travel;
    v.streamPhase += dt * (0.22 + 1.4 * a + v.wProcessing * 0.4) * travel;
  }

  @override
  void dispose() {
    _ticker.dispose();
    coreShader?.dispose();
    super.dispose();
  }
}
