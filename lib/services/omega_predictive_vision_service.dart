class MayaOmegaPredictiveVisionService {
  /// Builds suggestions from explicit scene changes. It never executes them.
  Future<Map<String, dynamic>> suggest(
    Map<String, dynamic> sceneGraph, {
    bool proactiveEnabled = true,
  }) async {
    if (!proactiveEnabled) {
      return {
        'success': true,
        'suggestions': <Map<String, dynamic>>[],
        'policy': 'Predictive assistance is disabled.',
      };
    }
    final changes = sceneGraph['changes'] is List
        ? sceneGraph['changes'] as List
        : const <dynamic>[];
    final suggestions = <Map<String, dynamic>>[];
    for (final raw in changes.take(20)) {
      if (raw is! Map) continue;
      final change = raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      switch (change['type']?.toString()) {
        case 'app_changed':
          suggestions.add({
            'type': 'context',
            'message': 'Offer help for ${change['to'] ?? 'the current app'}.',
            'confidence': 0.7,
            'requiresConfirmation': false,
          });
          break;
        case 'text_appeared':
          final value = change['value']?.toString().toLowerCase() ?? '';
          if (value.contains('error') ||
              value.contains('failed') ||
              value.contains('permission')) {
            suggestions.add({
              'type': 'recovery',
              'message':
                  'A possible problem appeared on screen: ${change['value']}. Offer diagnosis.',
              'confidence': change['confidence'] ?? 0.6,
              'requiresConfirmation': false,
            });
          }
          break;
        default:
          break;
      }
    }
    return {
      'success': true,
      'suggestions': suggestions.take(8).toList(),
      'actionExecuted': false,
      'policy':
          'Suggestions only. Predictive vision cannot silently open apps, send input, or change device state.',
    };
  }
}
