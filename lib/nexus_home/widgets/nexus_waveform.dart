import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../controllers/visual_state_controller.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';

/// Flowing, spectrum-driven energy wave around the microphone. Low bands sit
/// near the mic, highs toward the edges; crests travel toward the mic while
/// listening and outward while the AI speaks.
class NexusWaveform extends StatelessWidget {
  const NexusWaveform({super.key, required this.controller, required this.layout});

  final VisualStateController controller;
  final NexusLayout layout;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _WavePainter(controller, layout), willChange: true),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.c, this.layout) : super(repaint: c);

  final VisualStateController c;
  final NexusLayout layout;

  static Paint _stroke() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;

  late final ui.Shader _shader = ui.Gradient.linear(
    Offset(layout.waveRect.left, 0),
    Offset(layout.waveRect.right, 0),
    const <Color>[
      Color(0xFF2F5BFF),
      NexusPalette.cyan,
      Color(0xFFCFF4FF),
      NexusPalette.orange,
      Color(0xFFFF3D6E),
    ],
    const <double>[0, 0.32, 0.5, 0.68, 1],
  );
  late final Paint _glow = _stroke()..shader = _shader;
  late final Paint _main = _stroke()..shader = _shader;
  late final Paint _layers = _stroke()..shader = _shader;
  late final Paint _hair = _stroke()..shader = _shader;
  late final Paint _baseline = _stroke()..shader = _shader;

  @override
  void paint(Canvas canvas, Size size) {
    final v = c.visual;
    final g = c.geometry;
    final s = layout.scale;
    final e = v.waveEnergy.clamp(0.0, 1.0);

    _baseline
      ..strokeWidth = 0.6 * s
      ..color = Color.fromRGBO(255, 255, 255, 0.06 + 0.1 * e);
    canvas.drawLine(
      Offset(layout.waveRect.left, g.waveCenterY),
      Offset(layout.waveRect.right, g.waveCenterY),
      _baseline,
    );

    _hair
      ..strokeWidth = 0.7 * s
      ..color = Color.fromRGBO(255, 255, 255, (0.1 + 0.4 * e).clamp(0.0, 1.0));
    canvas.drawPath(g.waveHairlines, _hair);

    _glow
      ..strokeWidth = 4.5 * s
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * s)
      ..color = Color.fromRGBO(255, 255, 255, (0.16 + 0.55 * e).clamp(0.0, 1.0));
    canvas.drawPath(g.waveMain, _glow);

    _layers
      ..strokeWidth = 0.75 * s
      ..color = Color.fromRGBO(255, 255, 255, (0.2 + 0.45 * e).clamp(0.0, 1.0));
    canvas.drawPath(g.waveLayers, _layers);

    _main
      ..strokeWidth = (1.3 + 0.8 * e) * s
      ..color = Color.fromRGBO(255, 255, 255, (0.42 + 0.58 * e * 1.4).clamp(0.0, 1.0));
    canvas.drawPath(g.waveMain, _main);
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.layout != layout;
}
