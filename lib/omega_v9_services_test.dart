import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_core/services/omega_predictive_vision_service.dart';
import 'package:jarvis_core/services/omega_singularity_service.dart';

void main() {
  group('OMEGA v9 adaptive vision profile', () {
    test('uses the balanced Realme C15 profile when unconstrained', () {
      final profile = MayaOmegaSingularityService.adaptiveProfile({
        'thermalStatus': 1,
        'lowMemory': false,
        'powerSaveMode': false,
        'route': {'constrained': false},
      });

      expect(profile['targetAnalysisFps'], 4);
      expect(profile['dropStaleFrames'], isTrue);
      expect(profile['thumbnailWidth'], 720);
    });

    test('reduces analysis under memory or battery pressure', () {
      final profile = MayaOmegaSingularityService.adaptiveProfile({
        'thermalStatus': 1,
        'lowMemory': true,
        'powerSaveMode': false,
        'route': {'constrained': true},
      });

      expect(profile['targetAnalysisFps'], 2);
      expect(profile['thumbnailWidth'], 480);
    });

    test('uses one analysis frame per second under severe heat', () {
      final profile = MayaOmegaSingularityService.adaptiveProfile({
        'thermalStatus': 4,
        'lowMemory': false,
        'powerSaveMode': false,
        'route': {'constrained': false},
      });

      expect(profile['targetAnalysisFps'], 1);
    });
  });

  test('predictive vision returns suggestions without executing actions',
      () async {
    final service = MayaOmegaPredictiveVisionService();
    final result = await service.suggest({
      'changes': [
        {'type': 'app_changed', 'to': 'WhatsApp'},
        {
          'type': 'text_appeared',
          'value': 'Permission failed',
          'confidence': 0.9,
        },
      ],
    });

    expect(result['success'], isTrue);
    expect(result['actionExecuted'], isFalse);
    expect((result['suggestions'] as List).length, 2);
  });

  test('wallpaper workflow never claims an unavailable provider action',
      () async {
    final service = MayaOmegaSingularityService();
    final result = await service.wallpaperPlan(
      instruction: 'Animate the selected cyberpunk wallpaper',
      confirmed: true,
    );

    expect(result['success'], isTrue);
    expect(result['stage'], 'provider_required');
    expect(result['actionExecuted'], isFalse);
  });
}
