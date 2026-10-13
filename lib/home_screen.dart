import 'dart:async';

import 'package:flutter/material.dart';

import '../../config_screen.dart';
import '../../core/maya_controller.dart';
import '../../god_mode_dashboard.dart';
import '../../nexus_home/bridge/maya_voice_bridge.dart';
import '../../nexus_home/core/nexus_palette.dart';
import '../../nexus_home/nexus_home.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final MayaController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final MayaVoiceBridge _bridge;
  String? _shownError;

  MayaController get _maya => widget.controller;

  @override
  void initState() {
    super.initState();
    _bridge = MayaVoiceBridge(maya: _maya);
    _maya.init();
    _maya.addListener(_onChanged);
  }

  void _onChanged() {
    final err = _maya.lastError;
    if (err != null && err != _shownError && mounted) {
      _shownError = err;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(err),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF111A33),
          ),
        );
    } else if (err == null) {
      _shownError = null;
    }
  }

  @override
  void dispose() {
    _maya.removeListener(_onChanged);
    _bridge.dispose();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConfigScreen(
          onConfigComplete: () {
            unawaited(_maya.refreshConfig());
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Future<void> _openGodMode() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GodModeDashboard(maya: _maya),
      ),
    );
    if (mounted) unawaited(_maya.refreshConfig());
  }

  List<NexusStatusSegment> _buildStatus(
    NexusAssistantState state,
    MicStatus mic,
  ) {
    final micStatus = state == NexusAssistantState.listening
        ? 'LIVE'
        : switch (mic) {
            MicStatus.ready => 'READY',
            MicStatus.denied => 'ALLOW',
            MicStatus.unavailable => 'ERROR',
            MicStatus.unknown => 'TAP',
          };
    final micColor = switch (mic) {
      MicStatus.denied || MicStatus.unavailable => NexusPalette.rose,
      MicStatus.unknown => NexusPalette.amber,
      MicStatus.ready => NexusPalette.aqua,
    };
    return <NexusStatusSegment>[
      NexusStatusSegment(
        label: 'VOICE',
        value: state.orbStatus,
        color: state == NexusAssistantState.idle
            ? NexusPalette.aqua
            : NexusPalette.violet,
      ),
      NexusStatusSegment(
        label: 'AI',
        value: _maya.systemOnline ? 'READY' : 'SETUP',
        color: _maya.systemOnline ? NexusPalette.aqua : NexusPalette.amber,
      ),
      NexusStatusSegment(
        label: 'MIC',
        value: micStatus,
        color: micColor,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexusPalette.void0,
      body: Stack(
        children: [
          NexusHome(
            bridge: _bridge,
            statusBuilder: _buildStatus,
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 16,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: const Icon(
                  Icons.bolt_outlined,
                  color: Color(0x66B8C6E6),
                  size: 20,
                ),
                tooltip: 'MAYA GOD-MODE device capabilities',
                onPressed: _openGodMode,
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 16,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                icon: const Icon(
                  Icons.settings_outlined,
                  color: Color(0x66B8C6E6),
                  size: 20,
                ),
                tooltip: 'Voice assistant settings',
                onPressed: _openSettings,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
