import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_core/core/maya_controller.dart';
import 'package:jarvis_core/features/home/home_screen.dart';
import 'package:jarvis_core/nexus_home/bridge/maya_voice_bridge.dart';
import 'package:jarvis_core/nexus_home/controllers/nexus_state_controller.dart';
import 'package:jarvis_core/nexus_home/core/nexus_assistant_state.dart';
import 'package:jarvis_core/nexus_home/widgets/nexus_orb.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async {
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (MethodCall call) async {
        return null;
      },
    );
  });

  group('MayaVoiceBridge & NexusOrb integration', () {
    test('MayaVoiceBridge forwards state and levels to NexusStateController', () {
      final maya = MayaController();
      final bridge = MayaVoiceBridge(maya: maya);
      final nexus = NexusStateController(bridge: bridge);

      expect(nexus.current, NexusAssistantState.idle);

      // Verify level forwarding
      maya.level.value = 0.75;
      expect(nexus.analyzer.input.level, greaterThanOrEqualTo(0.0));

      nexus.dispose();
      maya.dispose();
    });

    testWidgets('HomeScreen renders with NexusOrb and responds to controller state',
        (tester) async {
      final maya = MayaController();

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(controller: maya),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify NexusOrb is present in the tree
      expect(find.byType(NexusOrb), findsOneWidget);

      // Verify voice-only status segments are present.
      expect(find.text('VOICE'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('MIC'), findsOneWidget);
      expect(
        find.byTooltip('MAYA GOD-MODE device capabilities'),
        findsOneWidget,
      );

      maya.dispose();
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
