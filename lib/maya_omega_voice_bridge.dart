import 'futuristic_core_service.dart';
import 'omega_singularity_service.dart';

/// Voice front door to the OMEGA screen-vision engine that already exists
/// and already works from GOD-MODE's "Omega Vision" / "V9 Status" buttons
/// (MayaOmegaSingularityService, backed by real native Android screen
/// capture, accessibility-tree reading and notification-history lookup in
/// MainActivity.kt — verified against the native handlers, not assumed).
/// This class adds a voice path into that same engine; it does not
/// reimplement any of it, and it cannot do anything the GOD-MODE buttons
/// could not already do.
///
/// Every tag reuses the exact tool-name strings FuturisticCoreService
/// already risk-classifies as medium risk (start_omega_vision_capture,
/// stop_omega_vision_capture, ingest_scene_graph, time_warp_lookup), so the
/// same Safe Mode gate and action ledger that already protect device
/// actions protect these too.
class MayaOmegaVoiceBridge {
  MayaOmegaVoiceBridge({
    MayaOmegaSingularityService? singularity,
    FuturisticCoreService? core,
  })  : _singularity = singularity ?? MayaOmegaSingularityService(),
        _core = core ?? FuturisticCoreService();

  final MayaOmegaSingularityService _singularity;
  final FuturisticCoreService _core;

  static final RegExp _startTag = RegExp(
      r'^\[ACTION:START_OMEGA_VISION_CAPTURE\]\s*',
      caseSensitive: false);
  static final RegExp _stopTag = RegExp(
      r'^\[ACTION:STOP_OMEGA_VISION_CAPTURE\]\s*',
      caseSensitive: false);
  static final RegExp _statusTag =
      RegExp(r'^\[ACTION:OMEGA_VISION_STATUS\]\s*', caseSensitive: false);
  static final RegExp _describeTag =
      RegExp(r'^\[ACTION:DESCRIBE_SCREEN\]\s*', caseSensitive: false);
  static final RegExp _rewindTag = RegExp(
      r'^\[ACTION:TIME_WARP_REWIND:(\d{1,3})\]\s*',
      caseSensitive: false);

  static const String actionSystemPrompt =
      'You can watch the screen, only with an explicit, visible Android consent prompt the owner approves each '
      'time (never hidden). Use exactly one leading tag then a short confirmation: [ACTION:START_OMEGA_VISION_CAPTURE] '
      'when asked to start watching or observing the screen. [ACTION:STOP_OMEGA_VISION_CAPTURE] to stop. '
      '[ACTION:OMEGA_VISION_STATUS] to report whether watching is currently on. [ACTION:DESCRIBE_SCREEN] to describe '
      'what app is open and what is visible right now — only works while Maya Accessibility is enabled and, for '
      'full detail, while screen watching is on. [ACTION:TIME_WARP_REWIND:seconds] to recall what was on screen '
      'that many seconds ago (0-60) — only works during an active, already-consented watching session; the frames '
      'themselves are never saved to disk and are erased the moment watching stops.';

  /// Mirrors MemoryService/MayaPersonaService/MayaAutomationService: returns
  /// the spoken confirmation with the tag stripped, or null if this reply
  /// is not one of this bridge's tags (so the caller tries the next
  /// handler).
  Future<String?> tryHandleActionTag(String aiResponse) async {
    final start = _startTag.firstMatch(aiResponse);
    if (start != null) {
      return _run('start_omega_vision_capture', aiResponse, start.end,
          () async {
        final result = await _singularity.startCapture();
        return result['success'] == true
            ? 'Screen watching is on.'
            : (result['error']?.toString() ??
                'I could not start screen watching.');
      });
    }

    final stop = _stopTag.firstMatch(aiResponse);
    if (stop != null) {
      return _run('stop_omega_vision_capture', aiResponse, stop.end,
          () async {
        final result = await _singularity.stopCapture();
        return result['success'] == true
            ? 'Screen watching is off, and the frames are cleared.'
            : (result['error']?.toString() ??
                'I could not stop screen watching.');
      });
    }

    final status = _statusTag.firstMatch(aiResponse);
    if (status != null) {
      return _run('omega_vision_status', aiResponse, status.end, () async {
        final result = await _singularity.status(online: true);
        final capture = result['capture'] is Map
            ? Map<String, dynamic>.from(result['capture'] as Map)
            : <String, dynamic>{};
        final running = capture['running'] == true;
        if (!running) return 'Screen watching is off right now.';
        final frames = capture['framesSeen'] ?? 0;
        return 'Screen watching is on. $frames frames seen so far, visible consent only.';
      });
    }

    final describe = _describeTag.firstMatch(aiResponse);
    if (describe != null) {
      return _run('ingest_scene_graph', aiResponse, describe.end, () async {
        final result = await _singularity.refreshSceneGraph();
        if (result['success'] != true) {
          return result['error']?.toString() ??
              'I could not read the screen right now.';
        }
        final graph = result['sceneGraph'] is Map
            ? Map<String, dynamic>.from(result['sceneGraph'] as Map)
            : <String, dynamic>{};
        final app = graph['app']?.toString() ?? 'an app';
        final nodes = graph['textNodes'] is List
            ? (graph['textNodes'] as List)
                .whereType<Map>()
                .map((n) => n['label']?.toString() ?? '')
                .where((label) => label.isNotEmpty)
                .take(6)
                .toList()
            : <String>[];
        if (nodes.isEmpty) {
          return "You're in $app. I don't see readable text on screen right now.";
        }
        return "You're in $app. I can see: ${nodes.join(', ')}.";
      });
    }

    final rewind = _rewindTag.firstMatch(aiResponse);
    if (rewind != null) {
      final seconds = int.tryParse(rewind.group(1) ?? '') ?? 0;
      return _run('time_warp_lookup', aiResponse, rewind.end, () async {
        final result = await _singularity.timeWarp(seconds);
        if (result['success'] != true) {
          return result['error']?.toString() ??
              'I could not rewind that far back.';
        }
        final notification = result['nearestNotification'] is Map
            ? Map<String, dynamic>.from(
                result['nearestNotification'] as Map)
            : null;
        if (notification != null) {
          final title = notification['title']?.toString() ?? '';
          final text = notification['text']?.toString() ?? '';
          return 'Around $seconds seconds ago, the closest thing I have is a notification: $title $text'
              .trim();
        }
        return 'I checked $seconds seconds back, but nothing notable was recorded for that moment.';
      });
    }

    return null;
  }

  Future<String> _run(
    String tool,
    String aiResponse,
    int tagEnd,
    Future<String> Function() action,
  ) async {
    final trailing = aiResponse.substring(tagEnd).trim();
    if (await _core.blockedBySafeMode(tool)) {
      const blocked = 'Maya Safe Mode blocked this action.';
      await _core.record(tool, {'success': false, 'message': blocked});
      return blocked;
    }
    String spoken;
    bool success;
    try {
      spoken = await action();
      success = !spoken.toLowerCase().contains('could not') &&
          !spoken.toLowerCase().contains('error');
    } catch (e) {
      spoken = 'That did not work: $e';
      success = false;
    }
    await _core.record(tool, {'success': success, 'message': spoken});
    // The model's own trailing words (if any) are appended after the real
    // result rather than replacing it, same as the other handlers — Maya
    // should never claim success before the actual result is known, so the
    // factual half always comes from the service call above.
    return trailing.isEmpty ? spoken : '$spoken $trailing';
  }
}
