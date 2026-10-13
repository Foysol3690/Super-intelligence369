import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/maya_controller.dart';
import 'features/home/home_screen.dart';
import 'maya_boot_screen.dart';
import 'overlay_entry.dart' as overlay_entry;

@pragma('vm:entry-point')
void overlayMain() => overlay_entry.overlayMain();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Color(0xFF02050A),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MayaApp());
}

class MayaApp extends StatefulWidget {
  const MayaApp({super.key});

  @override
  State<MayaApp> createState() => _MayaAppState();
}

class _MayaAppState extends State<MayaApp> {
  final MayaController _mayaController = MayaController();
  bool _booted = false;

  @override
  void dispose() {
    _mayaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MAYA NEXØRA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'MayaSans',
        scaffoldBackgroundColor: const Color(0xFF02050A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D9FF),
          secondary: Color(0xFFFF7A18),
          tertiary: Color(0xFFE6223D),
          surface: Color(0xFF090A11),
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.04, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: _booted
            ? HomeScreen(
                key: const ValueKey('home'), controller: _mayaController)
            : MayaBootScreen(
                key: const ValueKey('boot'),
                onComplete: () {
                  if (mounted) setState(() => _booted = true);
                },
              ),
      ),
    );
  }
}
