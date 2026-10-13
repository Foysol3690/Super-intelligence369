import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_core/jarvis_orb.dart';

void main() {
  testWidgets(
    'living orb keeps producing frames when system animations are disabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Center(
              child: JarvisOrb(
                size: 220,
                listening: true,
                audioLevel: .75,
                centerText: 'LISTENING',
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final paintFinder = find.descendant(
        of: find.byType(JarvisOrb),
        matching: find.byType(CustomPaint),
      );
      final firstPainter = tester.widget<CustomPaint>(paintFinder).painter;

      await tester.pump(const Duration(milliseconds: 250));
      final secondPainter = tester.widget<CustomPaint>(paintFinder).painter;

      expect(identical(firstPainter, secondPainter), isFalse);
      expect(tester.hasRunningAnimations, isTrue);
    },
  );
}
