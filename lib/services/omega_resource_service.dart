import 'package:flutter/services.dart';

class MayaOmegaResourceService {
  static const _channel =
      MethodChannel('com.foysol.jarvis/accessibility_bridge');

  Future<Map<String, dynamic>> snapshot({required bool online}) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('resourceSnapshot');
      final native = raw is Map
          ? raw.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
      return {
        'success': true,
        'online': online,
        ...native,
        'route': _route(
          online: online,
          batteryPercent: _number(native['batteryPercent']),
          lowMemory: native['lowMemory'] == true,
          powerSaveMode: native['powerSaveMode'] == true,
        ),
      };
    } on PlatformException catch (error) {
      return {
        'success': false,
        'online': online,
        'error': error.message ?? 'Native resource telemetry unavailable.',
        'route': _route(online: online),
      };
    } catch (_) {
      return {
        'success': false,
        'online': online,
        'error': 'Native resource telemetry unavailable.',
        'route': _route(online: online),
      };
    }
  }

  static Map<String, dynamic> _route({
    required bool online,
    num? batteryPercent,
    bool lowMemory = false,
    bool powerSaveMode = false,
  }) {
    final constrainedBattery =
        batteryPercent != null && batteryPercent >= 0 && batteryPercent <= 15;
    final constrained = lowMemory || powerSaveMode || constrainedBattery;
    final model = !online || constrained ? 'offline_rules' : 'cloud_general';
    return {
      'modelId': model,
      'reason': !online
          ? 'Network unavailable.'
          : lowMemory
              ? 'Android reports low memory.'
              : powerSaveMode
                  ? 'Power-save mode is active.'
                  : constrainedBattery
                      ? 'Battery is critically low.'
                      : 'General online route.',
      'constrained': constrained,
    };
  }

  static num? _number(dynamic value) {
    if (value is num) return value;
    return num.tryParse('$value');
  }
}
