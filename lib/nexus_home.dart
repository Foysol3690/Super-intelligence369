import 'package:flutter/widgets.dart';

import 'bridge/nexus_voice_bridge.dart';
import 'controllers/nexus_state_controller.dart';
import 'controllers/visual_state_controller.dart';
import 'core/nexus_layout.dart';
import 'core/nexus_palette.dart';
import 'widgets/nexus_background.dart';
import 'widgets/nexus_microphone.dart';
import 'widgets/nexus_orb.dart';
import 'widgets/nexus_status.dart';
import 'widgets/nexus_waveform.dart';

export 'audio/audio_analyzer.dart' show AudioAnalyzer, AudioChannel, MicStatus;
export 'bridge/nexus_voice_bridge.dart';
export 'controllers/nexus_state_controller.dart';
export 'core/nexus_assistant_state.dart';
export 'widgets/nexus_status.dart' show NexusStatusSegment, NexusStatusBuilder, defaultNexusStatus;

/// The NEXUS home screen: one living system where microphone, waveform,
/// energy stream and orb are all driven by the same audio/assistant state.
///
/// Pass your own [bridge] to connect existing STT/TTS/AI logic, or a
/// [controller] if you want to own the state machine yourself.
class NexusHome extends StatefulWidget {
  const NexusHome({
    super.key,
    this.bridge,
    this.controller,
    this.statusBuilder = defaultNexusStatus,
  });

  final NexusVoiceBridge? bridge;
  final NexusStateController? controller;
  final NexusStatusBuilder statusBuilder;

  @override
  State<NexusHome> createState() => _NexusHomeState();
}

class _NexusHomeState extends State<NexusHome> with SingleTickerProviderStateMixin {
  late final NexusStateController _nexus =
      widget.controller ?? NexusStateController(bridge: widget.bridge);
  late final VisualStateController _visual =
      VisualStateController(vsync: this, nexus: _nexus);

  @override
  void initState() {
    super.initState();
    _nexus.init();
    _visual.loadShader();
  }

  @override
  void dispose() {
    _visual.dispose();
    if (widget.controller == null) _nexus.dispose();
    super.dispose();
  }

  void _onCoreTap() => _nexus.onCoreTap();

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: NexusPalette.void0,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: kNexusFontFamily, color: Color(0xFFE6ECFF)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final layout = NexusLayout.resolve(constraints.biggest, padding);
            _visual.layout = layout;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                NexusBackground(controller: _visual, layout: layout),
                NexusOrb(controller: _visual, layout: layout, onTap: _onCoreTap),
                NexusWaveform(controller: _visual, layout: layout),
                NexusMicrophone(controller: _visual, layout: layout, onTap: _onCoreTap),
                NexusCaption(controller: _visual, layout: layout),
                NexusStatus(controller: _visual, layout: layout, builder: widget.statusBuilder),
              ],
            );
          },
        ),
      ),
    );
  }
}
