import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_core/maya_boot_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final sans = FontLoader('MayaSans')
      ..addFont(rootBundle.load('assets/fonts/MayaSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/MayaSans-Bold.ttf'));
    final mono = FontLoader('MayaMono')
      ..addFont(rootBundle.load('assets/fonts/MayaMono-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/MayaMono-Bold.ttf'));
    await Future.wait([sans.load(), mono.load()]);
  });

  testWidgets('v9.3 boot remains visible for its full timeline',
      (tester) async {
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MayaBootScreen(onComplete: () => completed = true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 7500));
    expect(completed, isFalse);
    await tester.pump(const Duration(milliseconds: 150));
    expect(completed, isTrue);
  });

  testWidgets('v9.3 boot visual is preserved', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'MayaSans'),
        ),
        home: MayaBootScreen(onComplete: () {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3800));
    await expectLater(
      find.byType(MayaBootScreen),
      matchesGoldenFile('goldens/v930_boot.png'),
    );
  });
}
