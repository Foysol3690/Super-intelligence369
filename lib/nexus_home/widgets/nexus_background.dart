import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../controllers/visual_state_controller.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';

/// Near-black navy atmosphere with soft volumetric light that breathes with
/// the orb's energy: brighter and wider when active, darker when calm.
class NexusBackground extends StatelessWidget {
  const NexusBackground({super.key, required this.controller, required this.layout});

  final VisualStateController controller;
  final NexusLayout layout;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _BackgroundPainter(controller, layout),
        willChange: true,
      );
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.c, this.layout) : super(repaint: c);

  final VisualStateController c;
  final NexusLayout layout;

  final Paint _base = Paint();
  final Paint _glow = Paint()..blendMode = BlendMode.plus;
  final Paint _sheen = Paint()..blendMode = BlendMode.plus;
  final Paint _vignette = Paint();
  final Map<int, ui.Shader> _radial = <int, ui.Shader>{};
  ui.Shader? _baseShader;
  ui.Shader? _sheenShader;
  ui.Shader? _vignetteShader;

  ui.Shader _radialShader(Color color, double radius) => _radial.putIfAbsent(
        Object.hash(color, radius.round()),
        () => ui.Gradient.radial(
          Offset.zero,
          radius,
          <Color>[color, color.withOpacity((color.opacity * 0.35).clamp(0.0, 1.0)), color.withOpacity(0.0)],
          const <double>[0, 0.45, 1],
        ),
      );

  void _drawGlow(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    if (alpha <= 0.004) return;
    _glow
      ..shader = _radialShader(color, radius)
      ..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..drawCircle(Offset.zero, radius, _glow)
      ..restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = c.visual;
    final rect = Offset.zero & size;
    final w = size.width;
    final h = size.height;
    final orb = layout.orbCenter;
    final r = layout.fieldRadius;

    _baseShader ??= ui.Gradient.linear(
      Offset.zero,
      Offset(0, h),
      const <Color>[NexusPalette.void0, NexusPalette.void1, NexusPalette.void2, NexusPalette.void0],
      const <double>[0, 0.35, 0.7, 1],
    );
    canvas.drawRect(rect, _base..shader = _baseShader);

    final drift = organic(v.time * 0.05, 1.0);
    final warm = 1 - v.coolness * 0.75;

    _drawGlow(canvas, orb.translate(drift * r * 0.12, 0), r * 2.2,
        const Color(0xFF1A2A78), 0.26 + 0.34 * v.glow);
    _drawGlow(canvas, Offset(w * 0.1, orb.dy + r * 0.55 + drift * 12), w * 0.78,
        const Color(0xFF0A4A6A), 0.14 + 0.14 * v.glow);
    _drawGlow(canvas, Offset(w * 0.94, orb.dy - r * 0.35 - drift * 10), w * 0.6,
        const Color(0xFF5A2216), (0.1 + 0.12 * v.glow) * warm);
    _drawGlow(canvas, orb, r * 2.7, const Color(0xFF34208A), 0.22 * v.coolness);
    _drawGlow(canvas, Offset(layout.micCenter.dx, layout.micCenter.dy + layout.micRadius),
        w * 0.6, const Color(0xFF123C8E), 0.1 + 0.42 * v.waveEnergy);

    _sheenShader ??= ui.Gradient.linear(
      Offset(0, h * 0.1),
      Offset(w, h * 0.6),
      const <Color>[Color(0x00FFFFFF), Color(0x0FFFFFFF), Color(0x00FFFFFF), Color(0x08FFFFFF), Color(0x00FFFFFF)],
      const <double>[0.3, 0.42, 0.5, 0.6, 0.7],
    );
    _sheen
      ..shader = _sheenShader
      ..color = Color.fromRGBO(255, 255, 255, (0.35 + 0.65 * v.glow).clamp(0.0, 1.0));
    canvas.drawRect(rect, _sheen);

    _vignetteShader ??= ui.Gradient.radial(
      Offset(w / 2, orb.dy),
      h * 0.8,
      const <Color>[Color(0x00000000), Color(0x33000000), Color(0xB3000000)],
      const <double>[0.35, 0.7, 1],
    );
    canvas.drawRect(rect, _vignette..shader = _vignetteShader);
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.layout != layout;
}
