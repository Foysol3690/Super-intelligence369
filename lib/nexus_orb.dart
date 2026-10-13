import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controllers/visual_state_controller.dart';
import '../core/nexus_assistant_state.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';
import 'energy_ribbons.dart';
import 'nexus_glass.dart';
import 'particle_field.dart';

/// The hero AI core, composed back-to-front:
/// back particles -> back ribbons -> optical glass lens -> energy stream ->
/// plasma core -> front ribbons -> front particles.
class NexusOrb extends StatelessWidget {
  const NexusOrb({
    super.key,
    required this.controller,
    required this.layout,
    required this.onTap,
  });

  final VisualStateController controller;
  final NexusLayout layout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hitRadius = layout.fieldRadius * 0.95;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ParticleField(controller: controller, depth: RibbonDepth.back),
        EnergyRibbons(controller: controller, layout: layout, depth: RibbonDepth.back),
        NexusGlassLayer(controller: controller, layout: layout),
        EnergyStream(controller: controller, layout: layout),
        OrbEnergyField(controller: controller, layout: layout),
        EnergyRibbons(controller: controller, layout: layout, depth: RibbonDepth.front),
        ParticleField(controller: controller, depth: RibbonDepth.front),
        Positioned.fromRect(
          rect: Rect.fromCircle(center: layout.orbCenter, radius: hitRadius),
          child: ValueListenableBuilder<NexusAssistantState>(
            valueListenable: controller.nexus.state,
            builder: (context, state, _) => Semantics(
              button: true,
              label: 'NEXUS core',
              hint: state == NexusAssistantState.listening
                  ? 'Double tap to send'
                  : 'Double tap to start listening',
              child: ClipOval(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onTap();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Inner light field + GPU plasma core (fragment shader), with a gradient
/// fallback while the shader loads or on devices that cannot compile it.
class OrbEnergyField extends StatelessWidget {
  const OrbEnergyField({super.key, required this.controller, required this.layout});

  final VisualStateController controller;
  final NexusLayout layout;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _CorePainter(controller, layout), willChange: true),
      );
}

class _CorePainter extends CustomPainter {
  _CorePainter(this.c, this.layout) : super(repaint: c);

  final VisualStateController c;
  final NexusLayout layout;
  final Paint _field = Paint()..blendMode = BlendMode.plus;
  final Paint _core = Paint();
  final Paint _fallback = Paint();
  int _fieldBucket = -1;

  void _bindShader(ui.FragmentShader shader, double radius) {
    final v = c.visual;
    shader
      ..setFloat(0, layout.orbCenter.dx)
      ..setFloat(1, layout.orbCenter.dy)
      ..setFloat(2, radius)
      ..setFloat(3, v.time)
      ..setFloat(4, v.orbEnergy.clamp(0.0, 1.0))
      ..setFloat(5, v.bass)
      ..setFloat(6, v.treble)
      ..setFloat(7, v.coolness.clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = c.visual;
    final center = layout.orbCenter;
    final fieldR = layout.fieldRadius * 0.78;

    final bucket = (v.coolness * 20).round();
    if (bucket != _fieldBucket) {
      _fieldBucket = bucket;
      final cool = bucket / 20;
      _field.shader = ui.Gradient.radial(
        Offset.zero,
        fieldR,
        <Color>[
          NexusPalette.spectrum(0.3, 0.9, cool),
          NexusPalette.spectrum(0.45, 0.35, cool),
          NexusPalette.spectrum(0.5, 0, cool),
        ],
        const <double>[0, 0.35, 1],
      );
    }
    _field.color = Color.fromRGBO(255, 255, 255, (0.1 + 0.32 * v.orbEnergy).clamp(0.0, 1.0));
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..drawCircle(Offset.zero, fieldR, _field)
      ..restore();

    final radius = layout.coreRadius * v.orbScale;
    final shader = c.coreShader;
    if (shader != null) {
      _bindShader(shader, radius);
      canvas.drawRect(Rect.fromCircle(center: center, radius: radius * 3.4), _core..shader = shader);
      return;
    }

    _fallback.shader = ui.Gradient.radial(
      center.translate(-radius * 0.3, -radius * 0.35),
      radius * 1.3,
      <Color>[
        const Color(0xFFFFFFFF),
        NexusPalette.spectrum(0.15, 1, v.coolness),
        NexusPalette.spectrum(0.5, 0.95, v.coolness),
        NexusPalette.spectrum(0.7, 0.8, v.coolness),
      ],
      const <double>[0, 0.2, 0.7, 1],
    );
    canvas.drawCircle(center, radius, _fallback);
  }

  @override
  bool shouldRepaint(_CorePainter old) => old.layout != layout;
}
