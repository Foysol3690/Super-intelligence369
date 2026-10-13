import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Opt-in gaze/dwell state for the floating orb.
///
/// Camera estimation belongs to the visible camera screen. This service only
/// evaluates supplied dwell observations and never injects hidden input.
class MayaOmegaGazeOrbService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'maya_omega_v9_gaze_orb_v1';

  Future<Map<String, dynamic>> configure({
    required bool enabled,
    int dwellMilliseconds = 1500,
    bool allowTrustedOpen = false,
  }) async {
    final state = <String, dynamic>{
      'enabled': enabled,
      'dwellMilliseconds': dwellMilliseconds.clamp(750, 5000),
      'allowTrustedOpen': allowTrustedOpen,
      'cameraPermissionRequired': enabled,
      'visibleIndicatorRequired': enabled,
      'configuredAt': DateTime.now().toUtc().toIso8601String(),
      'policy': allowTrustedOpen
          ? 'Only owner-approved app targets may be proposed after dwell.'
          : 'Dwell produces a suggestion and never opens an app automatically.',
    };
    await _write(state);
    return {'success': true, 'state': state};
  }

  Future<Map<String, dynamic>> observeDwell({
    required String target,
    required int milliseconds,
    bool trustedTarget = false,
  }) async {
    final state = await _read();
    if (state['enabled'] != true) {
      return {
        'success': false,
        'error': 'Gaze orb is disabled.',
        'actionExecuted': false,
      };
    }
    final cleanTarget = target.trim();
    if (cleanTarget.isEmpty) {
      return {
        'success': false,
        'error': 'A visible target label is required.',
        'actionExecuted': false,
      };
    }
    final threshold = (state['dwellMilliseconds'] as num?)?.round() ?? 1500;
    final reached = milliseconds >= threshold;
    final trusted = trustedTarget && state['allowTrustedOpen'] == true;
    return {
      'success': true,
      'target': cleanTarget,
      'observedMilliseconds': milliseconds.clamp(0, 10000),
      'thresholdMilliseconds': threshold,
      'thresholdReached': reached,
      'trustedTarget': trusted,
      'suggestOpen': reached,
      'confirmationRequired': reached && !trusted,
      'actionExecuted': false,
      'message': !reached
          ? 'Dwell threshold not reached.'
          : trusted
              ? 'Trusted dwell recognized. Route through the normal open-app tool for audit.'
              : 'Dwell recognized. Ask for confirmation before opening the target.',
    };
  }

  Future<Map<String, dynamic>> status() async =>
      {'success': true, 'state': await _read()};

  Future<Map<String, dynamic>> _read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return {
        'enabled': false,
        'dwellMilliseconds': 1500,
        'allowTrustedOpen': false,
      };
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {}
    return {'enabled': false};
  }

  Future<void> _write(Map<String, dynamic> state) =>
      _storage.write(key: _key, value: jsonEncode(state));
}
