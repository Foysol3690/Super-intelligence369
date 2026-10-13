import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'jarvis_orb.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}

class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    color: Colors.transparent,
    home: FloatingOrbOverlay(),
  );
}

/// System-wide draggable renderer of Maya's original JarvisOrb.
class FloatingOrbOverlay extends StatefulWidget {
  const FloatingOrbOverlay({super.key});

  @override
  State<FloatingOrbOverlay> createState() => _FloatingOrbOverlayState();
}

class _FloatingOrbOverlayState extends State<FloatingOrbOverlay> {
  String _state = 'idle';
  String _persona = 'maya';
  String _status = 'Maya ready';
  double _audioLevel = .1;
  bool _visionActive = false;
  StreamSubscription<dynamic>? _overlaySub;

  Color get _stateColor => switch (_state) {
    'listening' => const Color(0xFF24E5FF),
    'processing' => const Color(0xFFFF9A3D),
    'speaking' => const Color(0xFF36D9FF),
    _ => const Color(0xFF24E5FF),
  };

  Color get _primaryColor => switch (_persona) {
    'venom' => const Color(0xFFFF4B46),
    'professional' => const Color(0xFF5B8DFF),
    _ => _stateColor,
  };

  Color get _coreColor => switch (_state) {
    'listening' => const Color(0xFFF4FEFF),
    'processing' => const Color(0xFFFFF1D6),
    'speaking' => const Color(0xFFF4FEFF),
    _ => const Color(0xFFE7FBFF),
  };

  @override
  void initState() {
    super.initState();
    _overlaySub = FlutterOverlayWindow.overlayListener.listen(
      _handleSharedData,
      onError: (_) {},
    );
  }

  void _handleSharedData(dynamic event) {
    if (!mounted) return;
    try {
      final dynamic decoded = event is String ? jsonDecode(event) : event;
      if (decoded is! Map) return;
      final rawLevel = decoded['audioLevel'];
      setState(() {
        _state = decoded['state']?.toString() ?? _state;
        _persona = decoded['persona']?.toString() ?? _persona;
        _status = decoded['status']?.toString() ?? _status;
        _visionActive = decoded['visionActive'] == true;
        _audioLevel =
            (rawLevel is num ? rawLevel.toDouble() : _audioLevel)
                .clamp(0.0, 1.0)
                .toDouble();
      });
    } catch (_) {}
  }

  Future<void> _wakeMaya() =>
      FlutterOverlayWindow.shareData(jsonEncode({'action': 'user_tap'}));

  @override
  void dispose() {
    _overlaySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _wakeMaya,
    onDoubleTap: _wakeMaya,
    child: Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        label:
            'Maya system orb. ${_visionActive ? 'Screen vision active. ' : ''}$_status. Tap to wake Maya.',
        child: Stack(
          alignment: Alignment.center,
          children: [
            JarvisOrb(
              size: 166,
              audioLevel: _audioLevel,
              listening: _state == 'listening' || _state == 'speaking',
              primaryColor: _primaryColor,
              coreColor: _coreColor,
              secondaryColor: const Color(0xFFFF7438),
            ),
            Positioned(
              right: 11,
              bottom: 13,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _visionActive ? const Color(0xFFFFA04A) : _stateColor,
                  border: Border.all(color: Colors.black, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color:
                          _visionActive ? const Color(0xFFFFA04A) : _stateColor,
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
