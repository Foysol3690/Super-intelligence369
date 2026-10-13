import 'package:flutter/widgets.dart';

import '../audio/audio_analyzer.dart';
import '../controllers/visual_state_controller.dart';
import '../core/nexus_assistant_state.dart';
import '../core/nexus_layout.dart';
import '../core/nexus_palette.dart';
import 'nexus_glass.dart';

const String kNexusFontFamily = 'Sora';

/// One cell of the top status capsule.
class NexusStatusSegment {
  const NexusStatusSegment({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;
}

/// Builds the voice and microphone status cells from live state. Override via
/// NexusHome.statusBuilder to show your own system flags.
typedef NexusStatusBuilder = List<NexusStatusSegment> Function(
  NexusAssistantState state,
  MicStatus mic,
);

List<NexusStatusSegment> defaultNexusStatus(NexusAssistantState state, MicStatus mic) =>
    <NexusStatusSegment>[
      NexusStatusSegment(
        label: 'VOICE',
        value: state.orbStatus,
        color: state == NexusAssistantState.idle
            ? NexusPalette.aqua
            : NexusPalette.violet,
      ),
      NexusStatusSegment(
        label: 'MIC',
        value: state == NexusAssistantState.listening
            ? 'LIVE'
            : switch (mic) {
                MicStatus.ready => 'READY',
                MicStatus.denied => 'ALLOW',
                MicStatus.unavailable => 'ERROR',
                MicStatus.unknown => 'TAP',
              },
        color: switch (mic) {
          MicStatus.denied || MicStatus.unavailable => NexusPalette.rose,
          MicStatus.unknown => NexusPalette.amber,
          MicStatus.ready => NexusPalette.aqua,
        },
      ),
    ];

/// Minimal translucent glass voice-status capsule at the top of the screen.
class NexusStatus extends StatelessWidget {
  const NexusStatus({
    super.key,
    required this.controller,
    required this.layout,
    this.builder = defaultNexusStatus,
  });

  final VisualStateController controller;
  final NexusLayout layout;
  final NexusStatusBuilder builder;

  @override
  Widget build(BuildContext context) {
    final rect = layout.statusRect;
    final fontSize = (11.5 * layout.scale).clamp(9.5, 13.5);
    return Positioned.fromRect(
      rect: rect,
      child: NexusGlass(
        controller: controller,
        borderRadius: BorderRadius.circular(rect.height / 2),
        child: ValueListenableBuilder<NexusAssistantState>(
          valueListenable: controller.nexus.state,
          builder: (context, state, _) => ValueListenableBuilder<MicStatus>(
            valueListenable: controller.nexus.analyzer.micStatus,
            builder: (context, mic, _) {
              final segments = builder(state, mic);
              return Semantics(
                container: true,
                label: segments.map((s) => '${s.label} ${s.value}').join(', '),
                child: ExcludeSemantics(
                  child: Row(
                    children: <Widget>[
                      for (var i = 0; i < segments.length; i++) ...<Widget>[
                        if (i > 0) const _Divider(),
                        Expanded(child: _Segment(segment: segments[i], fontSize: fontSize)),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.segment, required this.fontSize});

  final NexusStatusSegment segment;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: kNexusFontFamily,
      fontSize: fontSize,
      height: 1.35,
      letterSpacing: fontSize * 0.2,
      fontVariations: const <FontVariation>[FontVariation.weight(500)],
      color: segment.color,
      shadows: <Shadow>[Shadow(color: segment.color.withOpacity((0.55).clamp(0.0, 1.0)), blurRadius: 8)],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: Column(
              key: ValueKey<String>(segment.value),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(segment.label, style: style, maxLines: 1),
                Text(segment.value, style: style, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const FractionallySizedBox(
        heightFactor: 0.5,
        child: SizedBox(
          width: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x00FFFFFF), Color(0x40FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
          ),
        ),
      );
}

/// "NEXUS READY" headline and hint, cross-fading as the assistant changes state.
class NexusCaption extends StatelessWidget {
  const NexusCaption({super.key, required this.controller, required this.layout});

  final VisualStateController controller;
  final NexusLayout layout;

  @override
  Widget build(BuildContext context) {
    final s = layout.scale;
    final headlineSize = (24 * s).clamp(19.0, 32.0);
    final hintSize = (10.5 * s).clamp(9.0, 13.0);
    return Positioned(
      left: 16,
      right: 16,
      top: layout.captionTop,
      height: layout.captionHeight,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ValueListenableBuilder<NexusAssistantState>(
            valueListenable: controller.nexus.state,
            builder: (context, state, _) => Semantics(
              liveRegion: true,
              label: '${state.headline}. ${state.hint}',
              child: ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _Fade(
                      id: state.headline,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _GradientHeadline(text: state.headline, fontSize: headlineSize),
                      ),
                    ),
                    SizedBox(height: 10 * s),
                    _Fade(
                      id: state.hint,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          state.hint,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: kNexusFontFamily,
                            fontSize: hintSize,
                            letterSpacing: hintSize * 0.38,
                            fontVariations: const <FontVariation>[FontVariation.weight(400)],
                            color: const Color(0x99B8C6E6),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey<String>(id), child: child),
      );
}

class _GradientHeadline extends StatelessWidget {
  const _GradientHeadline({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          colors: <Color>[
            NexusPalette.cyan,
            Color(0xFF7FD8FF),
            Color(0xFFE9EEFF),
            Color(0xFFFF9DB0),
            NexusPalette.rose,
          ],
          stops: <double>[0, 0.35, 0.55, 0.8, 1],
        ).createShader(bounds),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontFamily: kNexusFontFamily,
            fontSize: fontSize,
            letterSpacing: fontSize * 0.52,
            fontVariations: const <FontVariation>[FontVariation.weight(400)],
            color: const Color(0xFFFFFFFF),
            shadows: const <Shadow>[Shadow(color: Color(0x663FE6FF), blurRadius: 14)],
          ),
        ),
      );
}
