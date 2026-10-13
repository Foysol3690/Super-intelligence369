import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../controllers/visual_state_controller.dart';
import '../render/particle_system.dart';
import 'energy_ribbons.dart';

/// Renders one depth layer of the shared particle simulation with a single
/// drawRawAtlas call (one soft glow sprite, tinted per particle).
class ParticleField extends StatelessWidget {
  const ParticleField({super.key, required this.controller, required this.depth});

  final VisualStateController controller;
  final RibbonDepth depth;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _ParticlePainter(controller, depth), willChange: true),
      );
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.c, this.depth) : super(repaint: c);

  final VisualStateController c;
  final RibbonDepth depth;
  final Paint _paint = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.low;

  static ui.Image? _sprite;

  static ui.Image get sprite => _sprite ??= _buildSprite();

  static ui.Image _buildSprite() {
    const size = ParticleSystem.spriteSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(size / 2, size / 2);
    canvas.drawCircle(
      center,
      size / 2,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          size / 2,
          const <Color>[Color(0xFFFFFFFF), Color(0xCCFFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)],
          const <double>[0, 0.14, 0.4, 1],
        ),
    );
    return recorder.endRecording().toImageSync(size.toInt(), size.toInt());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final batch = depth == RibbonDepth.back ? c.particles.back : c.particles.front;
    batch.draw(canvas, sprite, _paint);
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.depth != depth;
}
