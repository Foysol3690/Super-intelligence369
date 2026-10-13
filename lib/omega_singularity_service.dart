import 'dart:convert';

import 'package:flutter/services.dart';

import 'omega_gaze_orb_service.dart';
import 'omega_predictive_vision_service.dart';
import 'omega_resource_service.dart';
import 'omega_scene_graph_service.dart';

/// Safe implementation boundary for the v9 OMEGA Singularity vision concepts.
class MayaOmegaSingularityService {
  static const _channel =
      MethodChannel('com.foysol.jarvis/accessibility_bridge');

  MayaOmegaSingularityService({
    MayaOmegaSceneGraphService? sceneGraph,
    MayaOmegaPredictiveVisionService? predictive,
    MayaOmegaGazeOrbService? gazeOrb,
    MayaOmegaResourceService? resources,
  })  : sceneGraph = sceneGraph ?? MayaOmegaSceneGraphService(),
        predictive = predictive ?? MayaOmegaPredictiveVisionService(),
        gazeOrb = gazeOrb ?? MayaOmegaGazeOrbService(),
        resources = resources ?? MayaOmegaResourceService();

  final MayaOmegaSceneGraphService sceneGraph;
  final MayaOmegaPredictiveVisionService predictive;
  final MayaOmegaGazeOrbService gazeOrb;
  final MayaOmegaResourceService resources;

  Future<Map<String, dynamic>> startCapture() async {
    try {
      final raw =
          await _channel.invokeMethod<dynamic>('requestOmegaScreenCapture');
      return _map(raw, fallback: 'Android did not return capture state.');
    } on PlatformException catch (error) {
      return {
        'success': false,
        'error': error.message ?? 'Screen-capture consent could not open.',
        'code': error.code,
      };
    } catch (_) {
      return {
        'success': false,
        'error': 'Screen-capture consent is unavailable on this device.',
      };
    }
  }

  Future<Map<String, dynamic>> stopCapture() async {
    try {
      final raw =
          await _channel.invokeMethod<dynamic>('stopOmegaScreenCapture');
      await sceneGraph.clear();
      return _map(raw, fallback: 'Capture stop state was unavailable.');
    } catch (_) {
      return {
        'success': false,
        'error': 'OMEGA capture could not be stopped through Android.',
      };
    }
  }

  Future<Map<String, dynamic>> status({required bool online}) async {
    final capture = await _invokeMap('omegaScreenCaptureStatus');
    final resource = await resources.snapshot(online: online);
    return {
      'success': true,
      'version': '9.0.0',
      'capture': capture,
      'performance': adaptiveProfile(resource),
      'sceneGraph': await sceneGraph.snapshot(),
      'gazeOrb': await gazeOrb.status(),
      'security': {
        'hiddenDisplayApi': false,
        'inputInjection': false,
        'visibleConsent': true,
        'timeWarpPersistence': false,
      },
    };
  }

  Future<Map<String, dynamic>> timeWarp(int secondsAgo) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'omegaTimeWarpInfo',
        {'secondsAgo': secondsAgo.clamp(0, 60)},
      );
      final nearestNotification =
          await _nearestNotification(secondsAgo.clamp(0, 60));
      return {
        ..._map(raw, fallback: 'No rewind frame is available.'),
        if (nearestNotification != null) 'success': true,
        if (nearestNotification != null)
          'nearestNotification': nearestNotification,
        'privacy':
            'Frames stay in memory and are erased when capture stops. Notification details are returned only for this explicit rewind request.',
      };
    } catch (_) {
      return {
        'success': false,
        'error': 'Time-Warp requires an active, consented capture session.',
      };
    }
  }

  Future<Map<String, dynamic>?> _nearestNotification(int secondsAgo) async {
    try {
      final raw =
          await _channel.invokeMethod<dynamic>('getRecentNotifications');
      if (raw is! List) return null;
      final target = DateTime.now().millisecondsSinceEpoch - secondsAgo * 1000;
      Map<String, dynamic>? nearest;
      int? nearestDelta;
      for (final item in raw.take(100)) {
        dynamic decoded = item;
        if (item is String) {
          try {
            decoded = jsonDecode(item);
          } catch (_) {
            continue;
          }
        }
        if (decoded is! Map) continue;
        final map = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final time = (map['time'] as num?)?.round();
        if (time == null) continue;
        final delta = (time - target).abs();
        if (nearestDelta == null || delta < nearestDelta) {
          nearestDelta = delta;
          nearest = map;
        }
      }
      if (nearest == null || nearestDelta == null || nearestDelta > 15000) {
        return null;
      }
      return {
        ...nearest,
        'differenceFromRequestedMs': nearestDelta,
        'source': 'notification_listener_history',
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> refreshSceneGraph() async {
    try {
      final capture = await _invokeMap('omegaScreenCaptureStatus');
      final tree = await _channel.invokeMethod<dynamic>('getScreenNodeTree');
      return await sceneGraph.ingestAccessibilityTree(
        tree,
        captureActive: capture['running'] == true,
      );
    } on PlatformException catch (error) {
      return {
        'success': false,
        'error': error.message ??
            'Enable Maya Accessibility to build the semantic scene graph.',
        'code': error.code,
      };
    } catch (_) {
      return {
        'success': false,
        'error':
            'The active Android screen could not be converted to a scene graph.',
      };
    }
  }

  Future<Map<String, dynamic>> wallpaperPlan({
    required String instruction,
    required bool confirmed,
  }) async {
    final clean = instruction.trim();
    if (clean.isEmpty) {
      return {'success': false, 'error': 'Wallpaper instruction is required.'};
    }
    return {
      'success': true,
      'instruction': clean,
      'confirmed': confirmed,
      'stage': confirmed ? 'provider_required' : 'awaiting_confirmation',
      'actionExecuted': false,
      'requirements': [
        'User-selected source image',
        'Configured image/video generation provider or PC companion',
        'Android live-wallpaper renderer',
        'Final preview and explicit apply confirmation',
      ],
      'message': confirmed
          ? 'The safe generation plan is ready, but no media provider or live-wallpaper renderer is connected.'
          : 'Preview and confirmation are required before generating or applying a live wallpaper.',
    };
  }

  static Map<String, dynamic> adaptiveProfile(
    Map<String, dynamic> resource,
  ) {
    final route = resource['route'] is Map
        ? Map<String, dynamic>.from(resource['route'] as Map)
        : <String, dynamic>{};
    final constrained = route['constrained'] == true;
    final thermal = (resource['thermalStatus'] as num?)?.round() ?? -1;
    final lowMemory = resource['lowMemory'] == true;
    final powerSave = resource['powerSaveMode'] == true;
    final severeThermal = thermal >= 4;
    final targetFps = severeThermal
        ? 1
        : constrained || lowMemory || powerSave
            ? 2
            : 4;
    return {
      'targetAnalysisFps': targetFps,
      'captureMode': 'acquire_latest_image',
      'dropStaleFrames': true,
      'thumbnailWidth': constrained ? 480 : 720,
      'reason': severeThermal
          ? 'Thermal throttling protection.'
          : constrained || lowMemory || powerSave
              ? 'Battery or memory protection.'
              : 'Balanced Realme C15 profile.',
    };
  }

  Future<Map<String, dynamic>> _invokeMap(String method) async {
    try {
      return _map(
        await _channel.invokeMethod<dynamic>(method),
        fallback: '$method returned no state.',
      );
    } catch (error) {
      return {'success': false, 'error': error.toString()};
    }
  }

  static Map<String, dynamic> _map(
    dynamic raw, {
    required String fallback,
  }) {
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return {'success': false, 'error': fallback};
  }
}
