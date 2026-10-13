import 'dart:async';

import 'package:flutter/material.dart';

import 'config_screen.dart';
import 'core/maya_controller.dart';
import 'maya_vision_screen.dart';
import 'models/maya_capability.dart';
import 'services/advanced_device_service.dart';
import 'services/maya_settings_service.dart';
import 'services/memory_service.dart';
import 'services/omega_singularity_service.dart';
import 'services/telegram_service.dart';
import 'whiteboard_screen.dart';

class GodModeDashboard extends StatefulWidget {
  const GodModeDashboard({super.key, required this.maya});

  /// Needed so saving provider keys here can immediately tell the voice
  /// engine to re-check them, instead of leaving the AI status badge on
  /// the home screen stuck on "SETUP" until the next app restart.
  final MayaController maya;

  @override
  State<GodModeDashboard> createState() => _GodModeDashboardState();
}

class _GodModeDashboardState extends State<GodModeDashboard> {
  final _settings = MayaSettingsService();
  final _memory = MemoryService();
  final _singularity = MayaOmegaSingularityService();
  Map<String, dynamic> _values = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.load();
    if (!mounted) return;
    setState(() {
      _values = Map<String, dynamic>.from(MayaSettingsService.defaults)
        ..addAll({});
      _loading = false;
    });
    final snapshot = await _settings.snapshot();
    if (mounted) setState(() => _values = snapshot);
  }

  Future<void> _toggle(String key, bool value) async {
    await _settings.set(key, value);
    if (mounted) setState(() => _values[key] = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF03030A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090912),
        title: const Text('MAYA GOD-MODE',
            style: TextStyle(letterSpacing: 2, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Provider keys',
            icon: const Icon(Icons.key),
            onPressed: _openProviders,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _hero(),
                const SizedBox(height: 16),
                _quickSetup(),
                const SizedBox(height: 20),
                ..._categorySections(),
              ],
            ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: const Color(0xFF50D2FF).withOpacity((.45).clamp(0.0, 1.0))),
          gradient: const LinearGradient(
            colors: [Color(0xFF101629), Color(0xFF12091D)],
          ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MAYA OMEGA • V9.0',
                style: TextStyle(
                    color: Color(0xFF50D2FF),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5)),
            SizedBox(height: 8),
            Text(
                'Consented low-latency screen vision, semantic scene graph, private Time-Warp, predictive suggestions, adaptive performance, encrypted plans and verified Android controls.',
                style: TextStyle(color: Colors.white70, height: 1.4)),
          ],
        ),
      );

  Widget _quickSetup() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0C14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('QUICK SETUP',
                style: TextStyle(
                    color: Colors.white70,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionChip('Providers', Icons.key, _openProviders),
                _actionChip('Accessibility', Icons.touch_app,
                    AdvancedDeviceService.openAccessibilitySettings),
                _actionChip('Lock phone', Icons.lock_outline,
                    () => _secureDeviceAction(lock: true)),
                _actionChip('Unlock request', Icons.lock_open,
                    () => _secureDeviceAction(lock: false)),
                _actionChip('Omega Vision', Icons.visibility_outlined,
                    () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const MayaVisionScreen()),
                  );
                }),
                _actionChip('OMEGA Screen', Icons.screen_share_outlined,
                    _startOmegaScreen),
                _actionChip('Stop Screen', Icons.stop_screen_share_outlined,
                    _stopOmegaScreen),
                _actionChip(
                    'V9 Status', Icons.hub_outlined, _showOmegaV9Status),
                _actionChip('Notifications', Icons.notifications_active,
                    AdvancedDeviceService.openNotificationAccessSettings),
                _actionChip('Test Telegram', Icons.send_outlined, () async {
                  final bot = TelegramService();
                  final ready = await bot.restart();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(ready
                              ? 'Telegram connected: ${bot.status}'
                              : bot.status)),
                    );
                  }
                }),
                _actionChip('Whiteboard', Icons.draw, () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const WhiteboardScreen()));
                }),
                _actionChip(
                    'Erase memory', Icons.delete_outline, _confirmClearMemory),
              ],
            ),
          ],
        ),
      );

  Future<void> _secureDeviceAction({required bool lock}) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(lock ? 'Lock this phone?' : 'Request secure unlock?'),
            content: Text(
              lock
                  ? 'Maya will lock the display using the enabled Accessibility service.'
                  : 'Maya will wake the display and open Android’s official fingerprint, face, PIN, pattern, or password authentication. It cannot bypass the secure keyguard.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('CANCEL'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(lock ? 'LOCK' : 'CONTINUE'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    String message;
    if (lock) {
      final success = await AdvancedDeviceService.lockScreen();
      message = success
          ? 'Phone locked.'
          : 'Lock failed. Enable Maya Accessibility first.';
    } else {
      final result = await AdvancedDeviceService.requestSecureUnlock();
      message = result['alreadyUnlocked'] == true
          ? 'Phone is already unlocked.'
          : result['requested'] == true
              ? 'Android authentication opened. Authenticate on the phone.'
              : (result['message']?.toString() ?? 'Unlock request failed.');
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _startOmegaScreen() async {
    final result = await _singularity.startCapture();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['message']?.toString() ??
              result['error']?.toString() ??
              'OMEGA screen consent flow completed.',
        ),
      ),
    );
  }

  Future<void> _stopOmegaScreen() async {
    final result = await _singularity.stopCapture();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['message']?.toString() ??
              result['error']?.toString() ??
              'OMEGA screen vision stopped.',
        ),
      ),
    );
  }

  Future<void> _showOmegaV9Status() async {
    final result = await _singularity.status(online: true);
    if (!mounted) return;
    final capture = result['capture'] is Map
        ? Map<String, dynamic>.from(result['capture'] as Map)
        : <String, dynamic>{};
    final performance = result['performance'] is Map
        ? Map<String, dynamic>.from(result['performance'] as Map)
        : <String, dynamic>{};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('OMEGA v9 STATUS'),
        content: Text(
          'Capture: ${capture['running'] == true ? 'ACTIVE' : 'STOPPED'}\n'
          'Frames: ${capture['framesSeen'] ?? 0}\n'
          'Time-Warp: ${capture['timeWarpFrames'] ?? 0}/60\n'
          'Analysis profile: ${performance['targetAnalysisFps'] ?? 0} FPS\n'
          'Security: visible consent, no hidden capture, no input injection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
          String label, IconData icon, Future<void> Function() action) =>
      ActionChip(
        avatar: Icon(icon, size: 18, color: const Color(0xFF50D2FF)),
        label: Text(label),
        onPressed: () => action(),
        backgroundColor: const Color(0xFF151520),
        side: const BorderSide(color: Colors.white12),
      );

  List<Widget> _categorySections() {
    final categories = <String>[];
    for (final item in mayaCapabilities) {
      if (!categories.contains(item.category)) categories.add(item.category);
    }
    return categories.map((category) {
      final items =
          mayaCapabilities.where((item) => item.category == category).toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(category.toUpperCase(),
                  style: const TextStyle(
                      color: Color(0xFF50D2FF),
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700)),
            ),
            ...items.map(_capabilityTile),
          ],
        ),
      );
    }).toList();
  }

  Widget _capabilityTile(MayaCapability item) {
    final color = switch (item.state) {
      CapabilityState.ready => const Color(0xFF46D38A),
      CapabilityState.permission => const Color(0xFFFFB800),
      CapabilityState.setup => const Color(0xFF50D2FF),
      CapabilityState.companion => const Color(0xFFBD70FF),
      CapabilityState.planned => Colors.white38,
    };
    final status = switch (item.state) {
      CapabilityState.ready => 'READY',
      CapabilityState.permission => 'PERMISSION',
      CapabilityState.setup => 'SETUP',
      CapabilityState.companion => 'COMPANION',
      CapabilityState.planned => 'PLANNED',
    };
    final settingKey = item.settingsKey;
    final enabled = settingKey == null ? null : (_values[settingKey] == true);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        title: Text(item.title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(item.description,
              style: const TextStyle(
                  color: Colors.white60, height: 1.35, fontSize: 12)),
        ),
        leading: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        trailing: enabled == null
            ? Text(status,
                style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .8))
            : Switch.adaptive(
                value: enabled,
                activeColor: color,
                onChanged: (value) => _toggle(settingKey!, value),
              ),
      ),
    );
  }

  Future<void> _openProviders() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ConfigScreen(
          onConfigComplete: () {
            unawaited(widget.maya.refreshConfig());
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _confirmClearMemory() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase Maya memory?'),
        content: const Text(
            'This permanently removes user-approved long-term memories.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Erase')),
        ],
      ),
    );
    if (yes == true) await _memory.clear();
  }
}
