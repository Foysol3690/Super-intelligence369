import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controllers/visual_state_controller.dart';
import '../core/nexus_assistant_state.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';

/// Circular glass microphone: frosted outer shell, dark translucent inner
/// glass, a luminous ring and a reactive spectrum ring that respond to the
/// same audio data as the waveform and the orb.
class NexusMicrophone extends StatelessWidget {
  const NexusMicrophone({
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
    final r = layout.micRadius;
    final box = r * 3.1;
    return Positioned(
      left: layout.micCenter.dx - box / 2,
      top: layout.micCenter.dy - box / 2,
      width: box,
      height: box,
      child: ValueListenableBuilder<NexusAssistantState>(
        valueListenable: controller.nexus.state,
        builder: (context, state, child) => Semantics(
          button: true,
          label: state == NexusAssistantState.listening ? 'Stop listening' : 'Start listening',
          child: child,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            SizedBox.square(
              dimension: r * 2,
              child: ClipOval(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: <Color>[Color(0x8C070C1C), Color(0x5C0B1430), Color(0x260F1A3A)],
                        stops: <double>[0, 0.72, 1],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _MicPainter(controller, r),
                  willChange: true,
                ),
              ),
            ),
            SizedBox.square(
              dimension: r * 2.2,
              child: ClipOval(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onTap();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MicPainter extends CustomPainter {
  _MicPainter(this.c, this.radius) : super(repaint: c);

  final VisualStateController c;
  final double radius;
  final Path _reactive = Path();

  static Paint _stroke() => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  late final ui.Shader _ringShader = ui.Gradient.sweep(
    Offset.zero,
    const <Color>[
      NexusPalette.orange,
      NexusPalette.pink,
      NexusPalette.violet,
      NexusPalette.blue,
      NexusPalette.cyan,
      NexusPalette.blue,
      NexusPalette.violet,
      NexusPalette.orange,
    ],
    const <double>[0, 0.14, 0.3, 0.42, 0.5, 0.62, 0.8, 1],
  );
  late final ui.Shader _iconShader = ui.Gradient.linear(
    Offset(-radius * 0.3, -radius * 0.4),
    Offset(radius * 0.3, radius * 0.45),
    const <Color>[NexusPalette.cyan, Color(0xFF7FA8FF), NexusPalette.violet],
    const <double>[0, 0.5, 1],
  );

  late final Paint _halo = _stroke()..shader = _ringShader..blendMode = BlendMode.plus;
  late final Paint _glow = _stroke()..shader = _ringShader..blendMode = BlendMode.plus;
  late final Paint _ring = _stroke()..shader = _ringShader..blendMode = BlendMode.plus;
  late final Paint _band = _stroke()..shader = _ringShader..blendMode = BlendMode.plus;
  late final Paint _icon = _stroke()..shader = _iconShader;
  final Paint _spec = _stroke()
    ..color = const Color(0x40FFFFFF)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);

  @override
  void paint(Canvas canvas, Size size) {
    final v = c.visual;
    final r = radius;
    final activity = v.micActivity.clamp(0.0, 1.0);
    final talk = (v.wListening + v.wSpeaking).clamp(0.0, 1.0);
    final s = r / 42;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    _halo
      ..strokeWidth = 0.8 * s
      ..color = Color.fromRGBO(255, 255, 255, 0.1 + 0.18 * activity);
    canvas.drawCircle(Offset.zero, r * 1.42, _halo);

    _reactive.reset();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final a = i / steps * math.pi * 2;
      final position = math.cos(a).abs() * 0.9;
      final rr = r * 1.14 + r * 0.26 * v.band(position) * talk * (0.35 + v.amplitude);
      final x = math.cos(a) * rr;
      final y = math.sin(a) * rr;
      if (i == 0) {
        _reactive.moveTo(x, y);
      } else {
        _reactive.lineTo(x, y);
      }
    }
    _band
      ..strokeWidth = 1 * s
      ..color = Color.fromRGBO(255, 255, 255, (0.12 + 0.6 * talk * (0.4 + v.amplitude)).clamp(0.0, 1.0));
    canvas.drawPath(_reactive, _band);

    _glow
      ..strokeWidth = (5 + 6 * v.amplitude * talk) * s
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * s)
      ..color = Color.fromRGBO(255, 255, 255, (0.14 + 0.6 * activity).clamp(0.0, 1.0));
    canvas.drawCircle(Offset.zero, r, _glow);

    _ring
      ..strokeWidth = (1.4 + 1.2 * v.amplitude * talk) * s
      ..color = Color.fromRGBO(255, 255, 255, (0.45 + 0.55 * activity).clamp(0.0, 1.0));
    canvas.drawCircle(Offset.zero, r, _ring);

    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.9),
      math.pi * 1.1,
      math.pi * 0.35,
      false,
      _spec..strokeWidth = 1.6 * s,
    );

    _icon
      ..strokeWidth = 2.2 * s
      ..color = Color.fromRGBO(255, 255, 255, (0.55 + 0.45 * activity).clamp(0.0, 1.0));
    final capsuleW = r * 0.34;
    final capsuleH = r * 0.56;
    final top = -r * 0.42;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-capsuleW / 2, top, capsuleW, capsuleH),
        Radius.circular(capsuleW / 2),
      ),
      _icon,
    );
    final cupR = r * 0.29;
    final cupCenter = Offset(0, top + capsuleH - capsuleW * 0.55);
    canvas.drawArc(Rect.fromCircle(center: cupCenter, radius: cupR), 0.15, math.pi - 0.3, false, _icon);
    final stemTop = cupCenter.dy + cupR;
    canvas.drawLine(Offset(0, stemTop), Offset(0, stemTop + r * 0.16), _icon);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MicPainter old) => old.radius != radius;
}
