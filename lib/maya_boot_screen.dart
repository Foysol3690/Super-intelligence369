import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'jarvis_orb.dart';

class MayaBootScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const MayaBootScreen({super.key, required this.onComplete});

  @override
  State<MayaBootScreen> createState() => _MayaBootScreenState();
}

class _MayaBootScreenState extends State<MayaBootScreen>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFFF304F);
  static const _orange = Color(0xFFFF8A24);
  static const _cyan = Color(0xFF19E6FF);
  static const _bootDuration = Duration(milliseconds: 7600);
  // Matches the bass impact in maya_v10_boot.wav (6.55s / 7.6s).
  static const _impactAt = .862;
  static const _lines = <String>[
    'SOVEREIGN CORE V10',
    'REACTIVE AUDIO REACTOR',
    'COGNITIVE MESH ONLINE',
    'ENCRYPTED PROVIDER VAULT',
    'DEVICE CONTROL LATTICE',
    'PREDICTIVE VOICE CHANNEL',
  ];

  late final AnimationController _timeline;
  final AudioPlayer _player = AudioPlayer();
  bool _finished = false;
  int _lastHapticLine = 0;
  bool _impactFired = false;

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: _bootDuration,
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      })
      ..addListener(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timeline.forward(from: 0);
      _playBootTheme();
    });
  }

  Future<void> _playBootTheme() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(.85);
      await _player.play(AssetSource('audio/maya_v10_boot.wav'));
    } catch (_) {
      // Never block startup if an OEM audio service starts slowly.
    }
  }

  void _onTick() {
    final v = _timeline.value;
    final line = (v * (_lines.length + 1)).floor().clamp(0, _lines.length);
    if (line > _lastHapticLine) {
      _lastHapticLine = line;
      HapticFeedback.selectionClick();
    }
    if (!_impactFired && v >= _impactAt) {
      _impactFired = true;
      HapticFeedback.heavyImpact();
    }
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _player.dispose();
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020408),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 720;
          return Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _BootAtmospherePainter(_timeline),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _ScanBeamPainter(_timeline)),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, compact ? 12 : 20, 20, 22),
                  child: Column(
                    children: [
                      _telemetry(),
                      SizedBox(height: compact ? 22 : 42),
                      Expanded(
                        flex: 5,
                        child: Center(child: _animatedIdentity(compact)),
                      ),
                      SizedBox(height: compact ? 12 : 22),
                      _bootGlass(compact),
                      const Spacer(),
                      _progress(),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ShockwavePainter(_timeline, _impactAt)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _telemetry() => Row(
        children: [
          _pill('SYS // AWAKENING', _cyan),
          Expanded(
            child: AnimatedBuilder(
              animation: _timeline,
              builder: (context, _) => Opacity(
                opacity:
                    .45 + .4 * math.sin(_timeline.value * math.pi * 8).abs(),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'SECURE LINK',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _pill('GODMODE', _orange),
        ],
      );

  Widget _animatedIdentity(bool compact) => AnimatedBuilder(
        animation: _timeline,
        builder: (context, _) {
          final t = Curves.easeOutCubic
              .transform((_timeline.value / .32).clamp(0, 1));
          final pulse = .5 + .5 * math.sin(_timeline.value * math.pi * 6);
          return Opacity(
            opacity: t,
            child: Transform.scale(
              scale: .84 + .16 * t,
              child: SizedBox(
                width: compact ? 300 : 340,
                height: compact ? 210 : 250,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    JarvisOrb(
                      size: compact ? 206 : 238,
                      audioLevel:
                          (.18 + _timeline.value * .72).clamp(0.0, 1.0),
                      listening: true,
                      booting: true,
                      primaryColor: _cyan,
                      coreColor: Colors.white,
                      centerLabel: 'V10',
                    ),
                    Container(
                      width: compact ? 190 : 224,
                      height: compact ? 190 : 224,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _cyan.withOpacity((.13 + pulse * .05).clamp(0.0, 1.0)),
                            _orange.withOpacity((.055).clamp(0.0, 1.0)),
                            Colors.transparent,
                          ],
                        ),
                        border: Border.all(color: _cyan.withOpacity((.24).clamp(0.0, 1.0))),
                        boxShadow: [
                          BoxShadow(
                            color: _cyan.withOpacity((.09 + pulse * .04).clamp(0.0, 1.0)),
                            blurRadius: 48,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    CustomPaint(
                      size: Size.square(compact ? 290 : 330),
                      painter: _HoloRadarPainter(progress: _timeline.value),
                    ),
                    Transform.rotate(
                      angle: _timeline.value * math.pi * 1.6,
                      child: CustomPaint(
                        size: Size.square(compact ? 206 : 242),
                        painter: _ArcRingPainter(progress: _timeline.value),
                      ),
                    ),
                    _glitchTitle(compact, t),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _glitchTitle(bool compact, double t) {
    final v = _timeline.value;
    // Strong RGB split while assembling, then occasional micro-glitches.
    final seed = (v * 60).floor();
    final burst = v < .34 || (seed % 17 == 0 && v < .85);
    final jitter = burst ? (math.sin(seed * 12.9898) * 43758.5453) % 1 : 0.0;
    final dx = burst ? (jitter - .5) * (v < .34 ? 10 : 4) : 0.0;
    final style = TextStyle(
      color: Colors.white,
      fontSize: compact ? 46 : 56,
      fontWeight: FontWeight.w900,
      letterSpacing: 9 - 3 * t,
      height: 1,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        if (burst) ...[
          Transform.translate(
            offset: Offset(dx, 0),
            child: Text('MAYA',
                style: style.copyWith(color: _red.withOpacity(.55))),
          ),
          Transform.translate(
            offset: Offset(-dx, 0),
            child: Text('MAYA',
                style: style.copyWith(color: _cyan.withOpacity(.55))),
          ),
        ],
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1 + v * 2, -1),
            end: Alignment(1 + v * 2, 1),
            colors: const [_red, _orange, Colors.white, _cyan],
          ).createShader(bounds),
          child: Text('MAYA', style: style),
        ),
      ],
    );
  }

  Widget _bootGlass(bool compact) => AnimatedBuilder(
        animation: _timeline,
        builder: (context, _) {
          final visible =
              ((_timeline.value - .13) / .12).clamp(0.0, 1.0).toDouble();
          final completed = ((_timeline.value * (_lines.length + 1)).floor())
              .clamp(0, _lines.length);
          return Opacity(
            opacity: visible,
            child: Transform.translate(
              offset: Offset(0, 18 * (1 - visible)),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 14 : 18),
                decoration: _glassDecoration(
                  radius: 22,
                  border: Colors.white.withOpacity((.16).clamp(0.0, 1.0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'BOOT MATRIX',
                          style: TextStyle(
                            color: _orange,
                            fontSize: 9,
                            letterSpacing: 2.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${completed.toString().padLeft(2, '0')} / 06',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontFamily: 'MayaMono',
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: compact ? 9 : 13),
                    for (var index = 0; index < _lines.length; index++)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 260),
                        opacity: index < completed ? 1 : .18,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: compact ? 5 : 7),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: index < completed
                                      ? (index.isEven ? _cyan : _orange)
                                      : Colors.white24,
                                  boxShadow: index < completed
                                      ? [
                                          BoxShadow(
                                            color:
                                                (index.isEven ? _cyan : _orange)
                                                    .withOpacity((.45).clamp(0.0, 1.0)),
                                            blurRadius: 7,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 11),
                              Text(
                                _typed(index, completed),
                                style: TextStyle(
                                  color: index < completed
                                      ? Colors.white70
                                      : Colors.white24,
                                  fontFamily: 'MayaMono',
                                  fontSize: compact ? 8 : 9,
                                  letterSpacing: 1.3,
                                ),
                              ),
                              const Spacer(),
                              if (index < completed)
                                const Icon(Icons.check_rounded,
                                    color: _cyan, size: 13),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  String _typed(int index, int completed) {
    if (index < completed) return _lines[index];
    if (index > completed) return _lines[index].replaceAll(RegExp(r'[A-Z0-9]'), '·');
    final slot = 1 / (_lines.length + 1);
    final local = ((_timeline.value - completed * slot) / slot).clamp(0.0, 1.0);
    final n = (_lines[index].length * local).round();
    final cursor = (_timeline.value * 40).floor().isEven ? '▌' : ' ';
    return _lines[index].substring(0, n) + cursor;
  }

  Widget _progress() => AnimatedBuilder(
        animation: _timeline,
        builder: (context, _) => Column(
          children: [
            Row(
              children: [
                const Text(
                  'NEURAL HANDSHAKE',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 7, letterSpacing: 2.1),
                ),
                const Spacer(),
                Text(
                  '${(_timeline.value * 100).round()}%',
                  style: const TextStyle(
                      color: _cyan, fontSize: 9, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: Curves.easeInOutCubic.transform(_timeline.value),
                minHeight: 3,
                backgroundColor: Colors.white.withOpacity((.07).clamp(0.0, 1.0)),
                valueColor: const AlwaysStoppedAnimation(_cyan),
              ),
            ),
          ],
        ),
      );

  BoxDecoration _glassDecoration(
          {required double radius, required Color border}) =>
      BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity((.10).clamp(0.0, 1.0)),
            Colors.white.withOpacity((.025).clamp(0.0, 1.0))
          ],
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity((.30).clamp(0.0, 1.0)),
              blurRadius: 28,
              offset: const Offset(0, 14)),
          BoxShadow(color: _cyan.withOpacity((.025).clamp(0.0, 1.0)), blurRadius: 18),
        ],
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: color.withOpacity((.055).clamp(0.0, 1.0)),
          border: Border.all(color: color.withOpacity((.30).clamp(0.0, 1.0))),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 7,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _BootAtmospherePainter extends CustomPainter {
  final Animation<double> animation;

  _BootAtmospherePainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * math.pi * 2;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF020408), Color(0xFF0B0509), Color(0xFF01151C)],
        ).createShader(rect),
    );

    void glow(Offset center, double radius, Color color, double opacity) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withOpacity((opacity).clamp(0.0, 1.0)), Colors.transparent],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    glow(
      Offset(size.width * (.16 + .035 * math.sin(t)), size.height * .25),
      size.width * .54,
      const Color(0xFFFF304F),
      .13,
    );
    glow(
      Offset(size.width * (.92 + .025 * math.cos(t)), size.height * .44),
      size.width * .57,
      const Color(0xFFFF8A24),
      .10,
    );
    glow(
      Offset(size.width * (.50 + .05 * math.cos(t)), size.height * .94),
      size.width * .70,
      const Color(0xFF19E6FF),
      .12,
    );

    final grid = Paint()
      ..color = const Color(0xFF19E6FF).withOpacity((.022).clamp(0.0, 1.0))
      ..strokeWidth = .5;
    const step = 38.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final particle = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 30; i++) {
      final seed = i * 2.399;
      final x =
          ((math.sin(seed) + 1) * .5 * size.width + math.sin(t + seed) * 7) %
              size.width;
      final y = ((math.cos(seed * 1.7) + 1) * .5 * size.height +
              animation.value * 26) %
          size.height;
      particle.color = (i % 3 == 0
              ? const Color(0xFFFF304F)
              : i % 3 == 1
                  ? const Color(0xFFFF8A24)
                  : const Color(0xFF19E6FF))
          .withOpacity((.12).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), i % 4 == 0 ? 1.3 : .7, particle);
    }
  }

  @override
  bool shouldRepaint(covariant _BootAtmospherePainter oldDelegate) => true;
}

class _ArcRingPainter extends CustomPainter {
  final double progress;
  const _ArcRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .47;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    const colors = [Color(0xFFFF304F), Color(0xFFFF8A24), Color(0xFF19E6FF)];
    for (var i = 0; i < 3; i++) {
      paint.color = colors[i].withOpacity((.65).clamp(0.0, 1.0));
      canvas.drawArc(
        rect.deflate(i * 7),
        -math.pi / 2 + i * 2.1,
        math.pi * (.34 + .08 * math.sin(progress * math.pi * 2 + i)),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}


class _ScanBeamPainter extends CustomPainter {
  final Animation<double> animation;
  _ScanBeamPainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final v = animation.value;
    // Two vertical scan passes during boot.
    final pass = (v * 2.2) % 1;
    final y = size.height * pass;
    final fade = v > .86 ? (1 - (v - .86) / .14).clamp(0.0, 1.0) : 1.0;
    final band = Rect.fromLTWH(0, y - 70, size.width, 140);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            const Color(0xFF19E6FF).withOpacity(.07 * fade),
            Colors.transparent,
          ],
        ).createShader(band),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = const Color(0xFF19E6FF).withOpacity(.35 * fade)
        ..strokeWidth = .8,
    );
    // CRT scanlines
    final lines = Paint()..color = Colors.black.withOpacity(.10 * fade);
    for (double yy = 0; yy < size.height; yy += 3) {
      canvas.drawRect(Rect.fromLTWH(0, yy, size.width, 1), lines);
    }
    // corner HUD brackets
    final hud = Paint()
      ..color = const Color(0xFF19E6FF).withOpacity(.45 * fade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const l = 22.0, m = 14.0;
    for (final c in [
      Offset(m, m + 40),
      Offset(size.width - m, m + 40),
      Offset(m, size.height - m),
      Offset(size.width - m, size.height - m),
    ]) {
      final sx = c.dx < size.width / 2 ? 1.0 : -1.0;
      final sy = c.dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy + sy * l)
          ..lineTo(c.dx, c.dy)
          ..lineTo(c.dx + sx * l, c.dy),
        hud,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScanBeamPainter oldDelegate) => true;
}

class _HoloRadarPainter extends CustomPainter {
  final double progress;
  const _HoloRadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final appear = Curves.easeOutBack.transform((progress / .25).clamp(0.0, 1.0));
    if (appear <= 0) return;
    final rr = r * appear;
    // tick ring
    final tick = Paint()..strokeWidth = 1;
    const ticks = 72;
    final lit = (progress * ticks * 1.15).floor();
    for (var i = 0; i < ticks; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / ticks;
      final long = i % 6 == 0;
      tick.color = (i <= lit ? const Color(0xFF19E6FF) : Colors.white)
          .withOpacity(i <= lit ? .7 : .12);
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (rr - (long ? 10 : 5)),
        c + Offset(math.cos(a), math.sin(a)) * rr,
        tick,
      );
    }
    // radar sweep
    final sweepA = progress * math.pi * 6;
    final rect = Rect.fromCircle(center: c, radius: rr - 12);
    canvas.drawArc(
      rect,
      sweepA - .9,
      .9,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweepA - .9,
          endAngle: sweepA,
          colors: [Colors.transparent, const Color(0xFF19E6FF).withOpacity(.22)],
        ).createShader(rect),
    );
    // counter-rotating hex dashes
    final hex = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFFFF8A24).withOpacity(.5);
    for (var k = 0; k < 6; k++) {
      final a = -progress * math.pi * 2 + k * math.pi / 3;
      canvas.drawArc(Rect.fromCircle(center: c, radius: rr - 20), a, .32, false, hex);
    }
  }

  @override
  bool shouldRepaint(covariant _HoloRadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ShockwavePainter extends CustomPainter {
  final Animation<double> animation;
  final double impactAt;
  _ShockwavePainter(this.animation, this.impactAt) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final v = animation.value;
    if (v < impactAt) return;
    final k = ((v - impactAt) / (1 - impactAt)).clamp(0.0, 1.0);
    final c = Offset(size.width / 2, size.height * .36);
    final maxR = size.longestSide;
    for (var i = 0; i < 3; i++) {
      final kk = (k - i * .12).clamp(0.0, 1.0);
      if (kk <= 0) continue;
      canvas.drawCircle(
        c,
        maxR * Curves.easeOutCubic.transform(kk),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - kk) + .5
          ..color = (i == 1 ? const Color(0xFFFF8A24) : const Color(0xFF19E6FF))
              .withOpacity(.8 * (1 - kk)),
      );
    }
    final flash = k < .15 ? k / .15 : (1 - (k - .15) / .85);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withOpacity((.55 * flash).clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(covariant _ShockwavePainter oldDelegate) => true;
}
