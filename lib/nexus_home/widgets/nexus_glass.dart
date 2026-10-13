import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../controllers/visual_state_controller.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';

/// Real frosted glass: the backdrop is blurred with BackdropFilter, then a
/// very low-opacity smoked fill, specular top highlight and a hairline
/// luminous edge are painted on top. Highlights brighten with orb energy.
class NexusGlass extends StatelessWidget {
  const NexusGlass({
    super.key,
    required this.controller,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 16,
  });

  final VisualStateController controller;
  final BorderRadius borderRadius;
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            painter: _GlassSurfacePainter(controller, borderRadius),
            child: RepaintBoundary(child: child),
          ),
        ),
      );
}

class _GlassSurfacePainter extends CustomPainter {
  _GlassSurfacePainter(this.c, this.radius) : super(repaint: c);

  final VisualStateController c;
  final BorderRadius radius;
  final Paint _fill = Paint();
  final Paint _sheen = Paint();
  final Paint _edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _edgeGlow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..blendMode = BlendMode.plus;
  Size? _cachedSize;

  void _build(Size size) {
    _cachedSize = size;
    final h = size.height;
    final w = size.width;
    _fill.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(w, h),
      const <Color>[Color(0x14FFFFFF), Color(0x08A9C8FF), Color(0x1A050A1A)],
      const <double>[0, 0.5, 1],
    );
    _sheen.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, h * 0.55),
      const <Color>[Color(0x1FFFFFFF), Color(0x00FFFFFF)],
    );
    _edge.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(w, h),
      <Color>[
        const Color(0x59FFFFFF),
        NexusPalette.cyan.withOpacity((0.18).clamp(0.0, 1.0)),
        const Color(0x0DFFFFFF),
        NexusPalette.orange.withOpacity((0.16).clamp(0.0, 1.0)),
        const Color(0x33FFFFFF),
      ],
      const <double>[0, 0.25, 0.5, 0.8, 1],
    );
    _edgeGlow.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(w, 0),
      <Color>[
        NexusPalette.cyan.withOpacity((0.5).clamp(0.0, 1.0)),
        NexusPalette.violet.withOpacity((0.2).clamp(0.0, 1.0)),
        NexusPalette.orange.withOpacity((0.5).clamp(0.0, 1.0)),
      ],
      const <double>[0, 0.5, 1],
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (_cachedSize != size) _build(size);
    final glow = c.visual.glow;
    final rrect = radius.toRRect(Offset.zero & size);
    canvas.drawRRect(rrect, _fill);
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.55),
        _sheen..color = Color.fromRGBO(255, 255, 255, 0.6 + 0.4 * glow));
    canvas.restore();
    final inner = rrect.deflate(0.5);
    canvas.drawRRect(inner, _edgeGlow..color = Color.fromRGBO(255, 255, 255, 0.08 + 0.22 * glow));
    canvas.drawRRect(inner, _edge..color = Color.fromRGBO(255, 255, 255, 0.55 + 0.45 * glow));
  }

  @override
  bool shouldRepaint(_GlassSurfacePainter old) => old.radius != radius;
}

/// The optical glass lens the orb is suspended in. Back ribbons and back
/// particles are painted *before* it, so the BackdropFilter genuinely blurs
/// energy that passes behind the glass, while the front strands stay sharp.
class NexusGlassLayer extends StatelessWidget {
  const NexusGlassLayer({super.key, required this.controller, required this.layout});

  final VisualStateController controller;
  final NexusLayout layout;

  @override
  Widget build(BuildContext context) {
    final r = layout.lensRadius;
    final sigma = 2.4 * layout.scale;
    return Positioned.fromRect(
      rect: Rect.fromCircle(center: layout.orbCenter, radius: r),
      child: IgnorePointer(
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: CustomPaint(painter: _LensPainter(controller, r)),
          ),
        ),
      ),
    );
  }
}

class _LensPainter extends CustomPainter {
  _LensPainter(this.c, this.radius) : super(repaint: c);

  final VisualStateController c;
  final double radius;

  late final Paint _body = Paint()
    ..shader = ui.Gradient.radial(
      Offset.zero,
      radius,
      const <Color>[Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x06A8C4FF), Color(0x12FFFFFF)],
      const <double>[0, 0.62, 0.9, 1],
    );
  late final Paint _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..blendMode = BlendMode.plus
    ..shader = ui.Gradient.sweep(
      Offset.zero,
      <Color>[
        const Color(0x00FFFFFF),
        const Color(0x40FFFFFF),
        NexusPalette.cyan.withOpacity((0.2).clamp(0.0, 1.0)),
        const Color(0x00FFFFFF),
        NexusPalette.orange.withOpacity((0.22).clamp(0.0, 1.0)),
        const Color(0x30FFFFFF),
        const Color(0x00FFFFFF),
      ],
      const <double>[0, 0.12, 0.28, 0.45, 0.62, 0.8, 1],
    );
  final Paint _spec = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

  @override
  void paint(Canvas canvas, Size size) {
    final v = c.visual;
    final glow = v.glow;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    _body.color = Color.fromRGBO(255, 255, 255, 0.55 + 0.45 * glow);
    canvas.drawCircle(Offset.zero, radius, _body);

    canvas.save();
    canvas.rotate(v.ribbonPhase * 0.08);
    _rim.color = Color.fromRGBO(255, 255, 255, (0.25 + 0.75 * glow).clamp(0.0, 1.0));
    canvas.drawCircle(Offset.zero, radius - 0.6, _rim);
    canvas.restore();

    final arcRect = Rect.fromCircle(center: Offset.zero, radius: radius - 3);
    _spec
      ..strokeWidth = 2
      ..color = Color.fromRGBO(255, 255, 255, 0.05 + 0.12 * glow);
    canvas.drawArc(arcRect, math.pi * 1.08, math.pi * 0.32, false, _spec);
    _spec.color = NexusPalette.orange.withOpacity((0.03 + 0.1 * glow * (1 - v.coolness).clamp(0.0, 1.0)));
    canvas.drawArc(arcRect, math.pi * 0.08, math.pi * 0.26, false, _spec);
    _spec.color = NexusPalette.cyan.withOpacity((0.03 + 0.08 * glow).clamp(0.0, 1.0));
    canvas.drawArc(arcRect, math.pi * 0.62, math.pi * 0.2, false, _spec);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LensPainter old) => old.radius != radius;
}
