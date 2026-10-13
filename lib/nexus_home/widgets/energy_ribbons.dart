import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../controllers/visual_state_controller.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';

enum RibbonDepth { back, front }

/// Draws the orbital ribbons for one depth layer. Colour comes from a single
/// spatial spectrum gradient (cyan on the left through to warm orange on the
/// right), additive-blended so crossings bloom like real light.
class EnergyRibbons extends StatelessWidget {
  const EnergyRibbons({
    super.key,
    required this.controller,
    required this.layout,
    required this.depth,
  });

  final VisualStateController controller;
  final NexusLayout layout;
  final RibbonDepth depth;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _RibbonPainter(controller, layout, depth),
          willChange: true,
        ),
      );
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.c, this.layout, this.depth) : super(repaint: c);

  final VisualStateController c;
  final NexusLayout layout;
  final RibbonDepth depth;

  final Paint _core = _stroke();
  final Paint _filament = _stroke();
  final Paint _glow = _stroke();
  int _shaderBucket = -1;
  ui.Shader? _shader;

  static Paint _stroke() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;

  ui.Shader _spectrumShader(double cool) {
    final bucket = (cool * 20).round();
    if (bucket != _shaderBucket || _shader == null) {
      _shaderBucket = bucket;
      final r = layout.fieldRadius;
      final o = layout.orbCenter;
      _shader = ui.Gradient.linear(
        o.translate(-r * 1.05, -r * 0.55),
        o.translate(r * 1.05, r * 0.55),
        NexusPalette.ribbonColors(bucket / 20),
        const <double>[0, 0.2, 0.42, 0.62, 0.8, 1],
      );
    }
    return _shader!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = c.visual;
    final g = c.geometry;
    final s = layout.scale;
    final shader = _spectrumShader(v.coolness);
    final e = v.orbEnergy;
    final isFront = depth == RibbonDepth.front;
    final mul = isFront ? 1.0 : 0.6;

    _core
      ..shader = shader
      ..strokeWidth = (1.35 + 0.6 * e) * s
      ..color = Color.fromRGBO(255, 255, 255, ((0.55 + 0.45 * e) * mul).clamp(0.0, 1.0));
    _filament
      ..shader = shader
      ..strokeWidth = 0.7 * s
      ..color = Color.fromRGBO(255, 255, 255, ((0.26 + 0.4 * e) * mul).clamp(0.0, 1.0));

    if (isFront) {
      _glow
        ..shader = shader
        ..strokeWidth = 5 * s
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * s)
        ..color = Color.fromRGBO(255, 255, 255, (0.18 + 0.4 * v.glow).clamp(0.0, 1.0));
      canvas.drawPath(g.frontCore, _glow);
      canvas.drawPath(g.frontFilaments, _filament);
      canvas.drawPath(g.frontCore, _core);
      _filament.color =
          Color.fromRGBO(255, 255, 255, (0.2 + 0.45 * v.treble + 0.35 * e).clamp(0.0, 1.0));
      canvas.drawPath(g.coreFilaments, _filament);
    } else {
      canvas.drawPath(g.backFilaments, _filament);
      canvas.drawPath(g.backCore, _core);
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.layout != layout || old.depth != depth;
}

/// The visible link between microphone and orb: a bundle of filaments whose
/// light pulses travel mic -> orb while the user speaks and orb -> mic while
/// the AI answers. Brightness and spread follow the shared audio amplitude.
class EnergyStream extends StatelessWidget {
  const EnergyStream({super.key, required this.controller, required this.layout});

  final VisualStateController controller;
  final NexusLayout layout;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(painter: _StreamPainter(controller, layout), willChange: true),
      );
}

class _StreamPainter extends CustomPainter {
  _StreamPainter(this.c, this.layout) : super(repaint: c);

  final VisualStateController c;
  final NexusLayout layout;
  final Paint _strand = _RibbonPainter._stroke();
  final Paint _pulse = _RibbonPainter._stroke();
  final Paint _haze = _RibbonPainter._stroke();

  static const List<double> _groupHue = <double>[0.12, 0.45, 0.85];

  @override
  void paint(Canvas canvas, Size size) {
    final v = c.visual;
    final g = c.geometry;
    final s = layout.scale;
    final energy = v.streamEnergy.clamp(0.0, 1.0);

    _haze
      ..strokeWidth = 7 * s
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * s)
      ..color = NexusPalette.spectrum(0.3, 0.05 + 0.18 * energy, v.coolness);
    canvas.drawPath(g.streamAll, _haze);

    _strand.strokeWidth = (0.6 + 0.6 * energy) * s;
    for (var i = 0; i < g.streamGroups.length; i++) {
      _strand.color = NexusPalette.spectrum(_groupHue[i], 0.12 + 0.55 * energy, v.coolness);
      canvas.drawPath(g.streamGroups[i], _strand);
    }

    final start = layout.streamStart;
    final end = layout.streamEnd;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final length = math.sqrt(dx * dx + dy * dy);
    if (length < 1) return;
    final ux = dx / length, uy = dy / length;
    final period = length / 3.2;
    final offset = (v.streamPhase % 1) * period;
    final from = Offset(start.dx + ux * offset, start.dy + uy * offset);
    final to = Offset(from.dx + ux * period, from.dy + uy * period);
    final talk = (v.wListening + v.wSpeaking).clamp(0.0, 1.0);
    _pulse
      ..strokeWidth = (1.1 + 1.2 * v.amplitude) * s
      ..shader = ui.Gradient.linear(
        from,
        to,
        const <Color>[Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0xFFE8F6FF), Color(0x00FFFFFF)],
        const <double>[0, 0.55, 0.8, 1],
        TileMode.repeated,
      )
      // 0.18 base (was 0.08) so the travelling highlight reads clearly even
      // at rest instead of being almost entirely gated behind talk/processing.
      ..color = Color.fromRGBO(
          255, 255, 255, (0.18 + talk * (0.3 + 0.6 * v.amplitude) + v.wProcessing * 0.2).clamp(0.0, 1.0));
    canvas.drawPath(g.streamAll, _pulse);
  }

  @override
  bool shouldRepaint(_StreamPainter old) => old.layout != layout;
}
