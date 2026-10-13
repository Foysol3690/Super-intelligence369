
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class JarvisOrb extends StatefulWidget {
  final double size;
  final double audioLevel;
  final bool listening;
  final Color primaryColor;
  final Color coreColor;
  final String? centerLabel;
  final bool booting;
  final Color? secondaryColor;

  const JarvisOrb({
    super.key,
    this.size = 280,
    this.audioLevel = 0.0,
    this.listening = false,
    this.booting = false,
    this.primaryColor = const Color(0xFF50D2FF),
    this.coreColor = const Color(0xFFBEF0FF),
    this.secondaryColor,
    String? centerLabel,
    String? centerText,
  }) : centerLabel = centerLabel ?? centerText;

  @override
  State<JarvisOrb> createState() => _JarvisOrbState();
}

class _JarvisOrbState extends State<JarvisOrb>
    with TickerProviderStateMixin {
  late final AnimationController _mainCtrl;
  late final List<_Particle> _particles;
  late final List<_HexCell> _hexCells;
  late final List<_ArcSpark> _arcs;
  double _smoothedLevel = 0.0;
  double _time = 0.0;
  Timer? _idleTimer;
  double _idlePhase = 0.0;

  static const int particleCount = 420;
  static const int hexCount = 48;
  static const int arcCount = 6;

  @override
  void initState() {
    super.initState();
    _mainCtrl = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..repeat();
    _mainCtrl.addListener(_onTick);

    final rng = math.Random(42);
    _particles = List.generate(particleCount, (i) {
      final phi = math.acos(1 - 2 * (i + 0.5) / particleCount);
      final theta = math.pi * (1 + math.sqrt(5)) * i;
      return _Particle(
        phi: phi,
        theta: theta,
        speed: 0.12 + rng.nextDouble() * 0.22,
        jitterPhase: rng.nextDouble() * math.pi * 2,
        jitterSpeed: 0.5 + rng.nextDouble() * 0.9,
        baseSize: 0.9 + rng.nextDouble() * 1.8,
        layer: rng.nextInt(3),
      );
    });

    _hexCells = List.generate(hexCount, (i) {
      return _HexCell(
        angle: (i / hexCount) * math.pi * 2,
        radiusMul: 1.28 + rng.nextDouble() * 0.18,
        pulseOffset: rng.nextDouble() * math.pi * 2,
        rotSpeed: (rng.nextBool() ? 1 : -1) * (0.08 + rng.nextDouble() * 0.1),
      );
    });

    _arcs = List.generate(arcCount, (i) {
      return _ArcSpark(
        startAngle: rng.nextDouble() * math.pi * 2,
        length: 0.3 + rng.nextDouble() * 0.6,
        speed: 0.4 + rng.nextDouble() * 0.6,
        radiusMul: 1.05 + rng.nextDouble() * 0.15,
        life: rng.nextDouble(),
      );
    });

    _idleTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!widget.listening) _idlePhase += 0.05;
    });
  }

  void _onTick() {
    _time += 0.016;
    final target = widget.listening
        ? widget.audioLevel.clamp(0.0, 1.0)
        : 0.05 + math.sin(_idlePhase) * 0.04;
    _smoothedLevel += (target - _smoothedLevel) * 0.18;
    setState(() {});
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _JarvisOrbPainter(
            time: _time,
            level: _smoothedLevel,
            particles: _particles,
            hexCells: _hexCells,
            arcs: _arcs,
            primary: widget.primaryColor,
            core: widget.coreColor,
            label: widget.centerLabel,
            listening: widget.listening,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double phi, theta, speed, jitterPhase, jitterSpeed, baseSize;
  final int layer;
  _Particle({
    required this.phi, required this.theta, required this.speed,
    required this.jitterPhase, required this.jitterSpeed,
    required this.baseSize, required this.layer,
  });
}

class _HexCell {
  final double angle, radiusMul, pulseOffset, rotSpeed;
  _HexCell({
    required this.angle, required this.radiusMul,
    required this.pulseOffset, required this.rotSpeed,
  });
}

class _ArcSpark {
  final double startAngle, length, speed, radiusMul;
  double life;
  _ArcSpark({
    required this.startAngle, required this.length,
    required this.speed, required this.radiusMul, required this.life,
  });
}

class _JarvisOrbPainter extends CustomPainter {
  final double time, level;
  final List<_Particle> particles;
  final List<_HexCell> hexCells;
  final List<_ArcSpark> arcs;
  final Color primary, core;
  final String? label;
  final bool listening;

  _JarvisOrbPainter({
    required this.time, required this.level,
    required this.particles, required this.hexCells, required this.arcs,
    required this.primary, required this.core,
    required this.label, required this.listening,
  });

  Color _a(Color c, double alpha) => c.withOpacity(alpha.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = size.width * 0.285;
    final pulse = 1 + level * 0.32 + math.sin(time * 1.3) * 0.015;
    final r = baseR * pulse;

    _paintCoreGlow(canvas, cx, cy, r);
    _paintHexShell(canvas, cx, cy, r);
    _paintParticleField(canvas, cx, cy, r);
    _paintScanRings(canvas, cx, cy, r);
    _paintWaveformRing(canvas, cx, cy, r);
    _paintArcSparks(canvas, cx, cy, r);
    _paintOuterRim(canvas, cx, cy, r);
    if (label != null) _paintLabel(canvas, cx, cy);
  }

  void _paintCoreGlow(Canvas canvas, double cx, double cy, double r) {
    final gradient = ui.Gradient.radial(
      Offset(cx, cy), r * 0.62,
      [_a(core, 0.55 + level * 0.35), _a(primary, 0.22 + level * 0.2), _a(primary, 0.0)],
      [0.0, 0.55, 1.0],
    );
    canvas.drawRect(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.62),
      Paint()..shader = gradient..blendMode = BlendMode.plus,
    );
  }

  void _paintHexShell(Canvas canvas, double cx, double cy, double r) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _a(primary, 0.14 + level * 0.12);
    for (final hex in hexCells) {
      final angle = hex.angle + time * hex.rotSpeed;
      final pulse = 0.85 + 0.15 * math.sin(time * 1.4 + hex.pulseOffset);
      final rr = r * hex.radiusMul * pulse;
      final x = cx + math.cos(angle) * rr;
      final y = cy + math.sin(angle) * rr * 0.55;
      _drawHexagon(canvas, Offset(x, y), 2.4 + level * 1.5, paint);
    }
  }

  void _drawHexagon(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final a = (math.pi / 3) * i;
      final p = Offset(center.dx + radius * math.cos(a), center.dy + radius * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _paintParticleField(Canvas canvas, double cx, double cy, double r) {
    for (final p in particles) {
      final layerScale = switch (p.layer) { 0 => 0.72, 1 => 0.92, _ => 1.12 };
      final th = p.theta + time * p.speed * 0.32;
      final wobble = math.sin(time * p.jitterSpeed + p.jitterPhase) * (0.035 + level * 0.14);
      final rr = r * layerScale * (1 + wobble);
      final x = cx + rr * math.sin(p.phi) * math.cos(th);
      final y = cy + rr * math.sin(p.phi) * math.sin(th) * 0.92;
      final z = math.cos(p.phi);
      final depth = (z + 1) / 2;
      final alpha = (0.12 + depth * 0.6 + level * 0.18).clamp(0.0, 0.95);
      final sz = p.baseSize * (0.55 + depth * 0.85) * (1 + level * 0.45);
      canvas.drawCircle(Offset(x, y), math.max(sz, 0.4),
          Paint()..color = _a(primary, alpha)..blendMode = BlendMode.plus);
      if (depth > 0.7 && level > 0.15) {
        canvas.drawCircle(Offset(x, y), sz * 1.8,
            Paint()..color = _a(core, (alpha * 0.4).clamp(0.0, 0.5))
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
              ..blendMode = BlendMode.plus);
      }
    }
  }

  void _paintScanRings(Canvas canvas, double cx, double cy, double r) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
    for (int ring = 0; ring < 3; ring++) {
      final rot = time * 0.16 * (ring.isEven ? 1 : -1) + ring * 1.05;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(rot);
      canvas.scale(1, 0.4 - ring * 0.07);
      paint.color = _a(primary, 0.16 + level * 0.22);
      canvas.drawCircle(Offset.zero, r * (1.15 + ring * 0.13 + level * 0.09), paint);
      canvas.restore();
    }
  }

  void _paintWaveformRing(Canvas canvas, double cx, double cy, double r) {
    if (level < 0.04) return;
    final path = Path();
    const segments = 96;
    final waveR = r * 1.32;
    for (int i = 0; i <= segments; i++) {
      final angle = (i / segments) * math.pi * 2;
      final noise = math.sin(angle * 6 + time * 3) * level * 8
                  + math.sin(angle * 13 - time * 5) * level * 4;
      final rr = waveR + noise;
      final x = cx + math.cos(angle) * rr;
      final y = cy + math.sin(angle) * rr;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 1.2
      ..color = _a(primary, 0.35 + level * 0.35)..blendMode = BlendMode.plus);
  }

  void _paintArcSparks(Canvas canvas, double cx, double cy, double r) {
    if (level < 0.1) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round..blendMode = BlendMode.plus;
    for (final arc in arcs) {
      final start = arc.startAngle + time * arc.speed;
      final sweep = arc.length * (0.5 + level * 0.5);
      final rr = r * arc.radiusMul;
      paint.color = _a(core, (0.2 + level * 0.4) * (0.5 + 0.5 * math.sin(time * 2 + arc.startAngle)));
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: rr), start, sweep, false, paint);
    }
  }

  void _paintOuterRim(Canvas canvas, double cx, double cy, double r) {
    if (level < 0.03) return;
    canvas.drawCircle(Offset(cx, cy), r * 1.02, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 1.5
      ..color = _a(core, 0.3 * level)..blendMode = BlendMode.plus);
  }

  void _paintLabel(Canvas canvas, double cx, double cy) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: _a(core, 0.75 + level * 0.25),
          fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2,
          shadows: [Shadow(color: _a(primary, 0.9), blurRadius: 8 + level * 10)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _JarvisOrbPainter o) => true;
}
