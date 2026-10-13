import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/maya_vision_service.dart';
import 'services/tts_service.dart';

enum MayaCameraLens { front, back }

class MayaVisionScreen extends StatefulWidget {
  final MayaCameraLens initialLens;
  final bool analyzeOnOpen;
  final bool startContinuous;

  const MayaVisionScreen({
    super.key,
    this.initialLens = MayaCameraLens.front,
    this.analyzeOnOpen = false,
    this.startContinuous = false,
  });

  @override
  State<MayaVisionScreen> createState() => _MayaVisionScreenState();
}

class _MayaVisionScreenState extends State<MayaVisionScreen>
    with WidgetsBindingObserver {
  final MayaVisionService _vision = MayaVisionService();
  final TtsService _tts = TtsService();
  final TextEditingController _question = TextEditingController(
    text: 'What can you see, and what useful help can you offer?',
  );

  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  MayaCameraLens _lens = MayaCameraLens.front;
  Timer? _continuousTimer;
  Timer? _sessionLimitTimer;
  bool _initializing = true;
  bool _analyzing = false;
  bool _continuous = false;
  int _consecutiveFailures = 0;
  bool _speakResults = true;
  bool _torch = false;
  bool _immersive = true;
  String _resolutionLabel = '1080P';
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  Offset? _focusPoint;
  Timer? _focusTimer;
  String _status = 'Requesting camera permission…';
  String _analysis = 'Maya vision has not analyzed a frame yet.';
  String _provider = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lens = widget.initialLens;
    unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    unawaited(_tts.init());
    unawaited(_initializeCamera(
      analyzeAfter: widget.analyzeOnOpen,
      continuousAfter: widget.startContinuous,
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopContinuous(reason: 'Vision paused while Maya is not visible.');
      final camera = _camera;
      _camera = null;
      unawaited(camera?.dispose());
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera({
    bool analyzeAfter = false,
    bool continuousAfter = false,
  }) async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _status = 'Starting visible camera session…';
      });
    }
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = permission.isPermanentlyDenied
            ? 'Camera permission is blocked. Enable it in Android Settings.'
            : 'Camera permission was not granted.';
      });
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty)
        throw StateError('No camera is available on this phone.');
      final wanted = _lens == MayaCameraLens.front
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final selected = _cameras.firstWhere(
        (camera) => camera.lensDirection == wanted,
        orElse: () => _cameras.first,
      );
      _lens = selected.lensDirection == CameraLensDirection.front
          ? MayaCameraLens.front
          : MayaCameraLens.back;
      final previous = _camera;
      _camera = null;
      await previous?.dispose();

      CameraController? controller;
      Object? initializationError;
      const profiles = <(ResolutionPreset, String)>[
        (ResolutionPreset.veryHigh, '1080P'),
        (ResolutionPreset.high, '720P'),
        (ResolutionPreset.medium, '480P'),
      ];
      for (final profile in profiles) {
        final candidate = CameraController(
          selected,
          profile.$1,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        try {
          await candidate.initialize();
          controller = candidate;
          _resolutionLabel = profile.$2;
          break;
        } catch (error) {
          initializationError = error;
          await candidate.dispose();
        }
      }
      if (controller == null) {
        throw StateError('Camera initialization failed: $initializationError');
      }
      _camera = controller;
      await controller.setFlashMode(FlashMode.off);
      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = math.min(await controller.getMaxZoomLevel(), 8.0).toDouble();
        _zoom = _minZoom.clamp(_minZoom, _maxZoom).toDouble();
        await controller.setZoomLevel(_zoom);
      } catch (_) {
        _minZoom = 1;
        _maxZoom = 1;
        _zoom = 1;
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _initializing = false;
        _torch = false;
        _status =
            '${_lens == MayaCameraLens.front ? 'Front' : 'Back'} camera active • $_resolutionLabel analysis • tap preview to focus';
      });
      if (analyzeAfter || continuousAfter) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (!mounted) return;
        if (continuousAfter) {
          _toggleContinuous(true);
        } else {
          await _analyzeFrame();
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _status = 'Camera failed: ${_short(error)}';
      });
    }
  }

  Future<void> _switchLens() async {
    if (_analyzing || _initializing) return;
    _stopContinuous();
    setState(() {
      _lens = _lens == MayaCameraLens.front
          ? MayaCameraLens.back
          : MayaCameraLens.front;
    });
    await _initializeCamera();
  }

  Future<void> _toggleTorch() async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    if (_lens == MayaCameraLens.front) {
      setState(() => _status = 'Torch is available only on the back camera.');
      return;
    }
    try {
      _torch = !_torch;
      await controller.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
      if (mounted)
        setState(() => _status = _torch ? 'Back-camera torch on' : 'Torch off');
    } catch (error) {
      if (mounted)
        setState(() => _status = 'Torch unavailable: ${_short(error)}');
    }
  }

  Future<void> _focusAt(Offset normalized) async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    final point = Offset(
      normalized.dx.clamp(0.0, 1.0).toDouble(),
      normalized.dy.clamp(0.0, 1.0).toDouble(),
    );
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
      _focusTimer?.cancel();
      if (mounted)
        setState(() {
          _focusPoint = point;
          _status =
              'Focus and exposure locked at selected point • $_resolutionLabel';
        });
      _focusTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _focusPoint = null);
      });
    } catch (error) {
      if (mounted)
        setState(() => _status = 'Tap focus unavailable: ${_short(error)}');
    }
  }

  Future<void> _setZoom(double value) async {
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) return;
    final safe = value.clamp(_minZoom, _maxZoom).toDouble();
    try {
      await controller.setZoomLevel(safe);
      if (mounted)
        setState(() {
          _zoom = safe;
          _status = '${safe.toStringAsFixed(1)}× zoom • $_resolutionLabel';
        });
    } catch (error) {
      if (mounted)
        setState(() => _status = 'Zoom unavailable: ${_short(error)}');
    }
  }

  Future<void> _analyzeFrame() async {
    final controller = _camera;
    if (_analyzing || controller == null || !controller.value.isInitialized)
      return;
    if (controller.value.isTakingPicture) return;
    setState(() {
      _analyzing = true;
      _status = 'Capturing one frame for the configured cloud vision provider…';
    });
    XFile? capture;
    try {
      HapticFeedback.mediumImpact();
      capture = await controller.takePicture();
      final bytes = await capture.readAsBytes();
      if (mounted)
        setState(() => _status = 'Analyzing with configured vision providers…');
      final result = await _vision.analyze(
        bytes,
        question: _question.text.trim().isEmpty
            ? 'What can you see, and what useful help can you offer?'
            : _question.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _analysis = result.text;
        _provider = result.provider;
        _status = 'Analysis complete • frame discarded';
        _consecutiveFailures = 0;
      });
      if (_speakResults) await _tts.speak(result.text);
    } catch (error) {
      if (mounted) {
        if (_continuous) _consecutiveFailures += 1;
        final shouldStop = _continuous && _consecutiveFailures >= 3;
        setState(() {
          _analysis = 'Vision error: ${_short(error)}';
          _status = shouldStop
              ? 'Real-time Vision stopped after 3 consecutive errors • no frame retained'
              : _continuous
                  ? 'Real-time analysis failed ($_consecutiveFailures/3) • no frame retained'
                  : 'Analysis failed • no frame retained';
        });
        if (shouldStop) _stopContinuous();
      }
    } finally {
      if (capture != null) {
        try {
          final file = File(capture.path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _toggleContinuous(bool enabled) {
    if (enabled) {
      final controller = _camera;
      if (controller == null ||
          !controller.value.isInitialized ||
          _initializing) {
        if (mounted)
          setState(() => _status = 'Camera is not ready for Real-time Vision.');
        return;
      }
      _continuousTimer?.cancel();
      _sessionLimitTimer?.cancel();
      _consecutiveFailures = 0;
      setState(() {
        _continuous = true;
        _status =
            'Real-time Vision active • one visible $_resolutionLabel frame every 6 seconds • 10-minute limit';
      });
      unawaited(_analyzeFrame());
      _continuousTimer = Timer.periodic(
        const Duration(seconds: 6),
        (_) {
          if (!_analyzing) unawaited(_analyzeFrame());
        },
      );
      _sessionLimitTimer = Timer(const Duration(minutes: 10), () {
        _stopContinuous(
            reason:
                'Real-time Vision reached its 10-minute safety limit and stopped.');
      });
    } else {
      _stopContinuous(reason: 'Real-time Vision stopped.');
    }
  }

  void _stopContinuous({String? reason}) {
    _continuousTimer?.cancel();
    _continuousTimer = null;
    _sessionLimitTimer?.cancel();
    _sessionLimitTimer = null;
    _consecutiveFailures = 0;
    if (!mounted) return;
    setState(() {
      _continuous = false;
      if (reason != null) _status = reason;
    });
  }

  Future<void> _openSettings() => openAppSettings();

  Future<void> _setImmersive(bool value) async {
    await SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    if (mounted) setState(() => _immersive = value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _continuousTimer?.cancel();
    _sessionLimitTimer?.cancel();
    _focusTimer?.cancel();
    _question.dispose();
    unawaited(_tts.dispose());
    final camera = _camera;
    if (camera != null) unawaited(camera.dispose());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _camera;
    if (_immersive) return _buildImmersiveCamera(context, controller);
    return Scaffold(
      backgroundColor: const Color(0xFF03030A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080A12),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MAYA OMEGA VISION',
                style: TextStyle(fontSize: 15, letterSpacing: 1.8)),
            Text('VISIBLE CAMERA SESSION',
                style: TextStyle(
                    fontSize: 9, color: Color(0xFF67DFFF), letterSpacing: 1.4)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open full-screen camera',
            onPressed: () => _setImmersive(true),
            icon: const Icon(Icons.fullscreen),
          ),
          IconButton(
            tooltip: 'Switch front/back camera',
            onPressed: _switchLens,
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
          IconButton(
            tooltip: 'Camera permission settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _privacyBanner(),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 260, maxHeight: 430),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _continuous
                      ? const Color(0xFFFF7849)
                      : const Color(0xFF42D9FF),
                  width: 1.2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null && controller.value.isInitialized)
                    Center(
                      child: AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: LayoutBuilder(
                          builder: (context, preview) => GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (details) => _focusAt(Offset(
                              details.localPosition.dx / preview.maxWidth,
                              details.localPosition.dy / preview.maxHeight,
                            )),
                            child: CameraPreview(controller),
                          ),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: _initializing
                          ? const CircularProgressIndicator(
                              color: Color(0xFF42D9FF))
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(_status,
                                  textAlign: TextAlign.center,
                                  style:
                                      const TextStyle(color: Colors.white70)),
                            ),
                    ),
                  IgnorePointer(
                      child: CustomPaint(
                          painter: _VisionHudPainter(
                              active: _continuous, focusPoint: _focusPoint))),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _statusPill(
                      _continuous ? '● REAL-TIME' : '● CAMERA ACTIVE',
                      _continuous
                          ? const Color(0xFFFF7849)
                          : const Color(0xFF42D9FF),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _statusPill(
                      '$_resolutionLabel • ${_lens == MayaCameraLens.front ? 'FRONT' : 'BACK'}',
                      Colors.white70,
                    ),
                  ),
                  if (_analyzing)
                    Container(
                      color: Colors.black45,
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFFFA04A)),
                          SizedBox(height: 12),
                          Text('MAYA IS ANALYZING',
                              style: TextStyle(
                                  letterSpacing: 1.8,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _controlButton(
                        Icons.cameraswitch_outlined, 'FLIP', _switchLens)),
                const SizedBox(width: 8),
                Expanded(
                    child: _controlButton(
                        _torch ? Icons.flash_on : Icons.flash_off,
                        'TORCH',
                        _toggleTorch)),
                const SizedBox(width: 8),
                Expanded(
                    child: _controlButton(
                        Icons.center_focus_strong, 'ANALYZE', _analyzeFrame,
                        accent: true)),
              ],
            ),
            if (_maxZoom > _minZoom) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0D15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_in,
                        size: 18, color: Color(0xFF58DFFF)),
                    const SizedBox(width: 8),
                    Text('${_zoom.toStringAsFixed(1)}×',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Slider(
                        value: _zoom.clamp(_minZoom, _maxZoom).toDouble(),
                        min: _minZoom,
                        max: _maxZoom,
                        divisions: math
                            .max(1, ((_maxZoom - _minZoom) * 4).round())
                            .toInt(),
                        onChanged: _analyzing
                            ? null
                            : (value) => unawaited(_setZoom(value)),
                      ),
                    ),
                    Text(_resolutionLabel,
                        style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFFFA04A),
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _promptChip('Describe',
                    'Describe the important visible details and suggest useful help.'),
                _promptChip('Read text',
                    'Read and summarize visible non-sensitive text. Do not repeat passwords, OTPs, or financial data.'),
                _promptChip('Inspect object',
                    'Identify the main object, explain what it may be used for, and mention visible damage or safety concerns.'),
                _promptChip('Guide me',
                    'Understand what I am doing and give the next practical step without making unsupported assumptions.'),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _question,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Ask Maya about this view',
                hintText:
                    'Read this document, identify this object, or explain what I am showing…',
                prefixIcon: const Icon(Icons.visibility_outlined),
                filled: true,
                fillColor: const Color(0xFF0C1019),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            _switchTile(
              title: 'Real-time Vision',
              subtitle:
                  'Visible, foreground-only $_resolutionLabel analysis every 6 seconds • auto-stops after 10 minutes',
              value: _continuous,
              onChanged: _toggleContinuous,
              color: const Color(0xFFFF7849),
            ),
            _switchTile(
              title: 'Speak results',
              subtitle: 'Use Laomedeia or Android TTS for visual descriptions',
              value: _speakResults,
              onChanged: (value) => setState(() => _speakResults = value),
              color: const Color(0xFF42D9FF),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0D15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          size: 18, color: Color(0xFFFFA04A)),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('VISUAL INTELLIGENCE',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.3))),
                      if (_provider.isNotEmpty)
                        Text(_provider,
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF42D9FF))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(_analysis,
                      style:
                          const TextStyle(color: Colors.white70, height: 1.45)),
                  const SizedBox(height: 10),
                  Text(_status,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImmersiveCamera(
    BuildContext context,
    CameraController? controller,
  ) {
    final ready = controller != null && controller.value.isInitialized;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) =>
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              LayoutBuilder(
                builder: (context, bounds) {
                  final size = controller.value.previewSize;
                  final width = size?.height ?? bounds.maxWidth;
                  final height = size?.width ?? bounds.maxHeight;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _focusAt(Offset(
                      details.localPosition.dx / bounds.maxWidth,
                      details.localPosition.dy / bounds.maxHeight,
                    )),
                    child: ClipRect(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),
                  );
                },
              )
            else
              Center(
                child: _initializing
                    ? const CircularProgressIndicator(color: Color(0xFF42D9FF))
                    : Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
              ),
            IgnorePointer(
              child: CustomPaint(
                painter: _VisionHudPainter(
                  active: _continuous,
                  focusPoint: _focusPoint,
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      _roundCameraButton(
                        Icons.arrow_back,
                        () => Navigator.of(context).maybePop(),
                        'Close camera',
                      ),
                      const SizedBox(width: 8),
                      _statusPill(
                        '$_resolutionLabel • ${_lens == MayaCameraLens.front ? 'FRONT' : 'BACK'}',
                        const Color(0xFF8BEAFF),
                      ),
                      const Spacer(),
                      _roundCameraButton(
                        Icons.fullscreen_exit,
                        () => _setImmersive(false),
                        'Show vision controls',
                      ),
                      _roundCameraButton(
                        Icons.cameraswitch_outlined,
                        _switchLens,
                        'Switch camera',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  42,
                  16,
                  MediaQuery.paddingOf(context).bottom + 14,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    if (_maxZoom > _minZoom)
                      Slider(
                        value: _zoom.clamp(_minZoom, _maxZoom).toDouble(),
                        min: _minZoom,
                        max: _maxZoom,
                        onChanged: _analyzing
                            ? null
                            : (value) => unawaited(_setZoom(value)),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _roundCameraButton(
                          _torch ? Icons.flash_on : Icons.flash_off,
                          _toggleTorch,
                          'Torch',
                        ),
                        FloatingActionButton.large(
                          heroTag: 'mayaVisionAnalyze',
                          backgroundColor: const Color(0xFFFF7849),
                          foregroundColor: Colors.white,
                          onPressed: _analyzing ? null : _analyzeFrame,
                          child: _analyzing
                              ? const CircularProgressIndicator(
                                  color: Colors.white)
                              : const Icon(Icons.center_focus_strong, size: 34),
                        ),
                        _roundCameraButton(
                          _continuous
                              ? Icons.stop_circle_outlined
                              : Icons.visibility,
                          () => _toggleContinuous(!_continuous),
                          _continuous
                              ? 'Stop Real-time Vision'
                              : 'Start Real-time Vision',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundCameraButton(
    IconData icon,
    FutureOr<void> Function() onPressed,
    String tooltip,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: () => onPressed(),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black54,
            foregroundColor: Colors.white,
          ),
          icon: Icon(icon),
        ),
      );

  Widget _promptChip(String label, String prompt) => ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        avatar: const Icon(Icons.bolt, size: 16, color: Color(0xFFFFA04A)),
        backgroundColor: const Color(0xFF111522),
        side: const BorderSide(color: Colors.white12),
        onPressed: _analyzing
            ? null
            : () {
                _question.text = prompt;
                unawaited(_analyzeFrame());
              },
      );

  Widget _privacyBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF09202A),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: const Color(0xFF42D9FF).withOpacity((.35).clamp(0.0, 1.0))),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF42D9FF), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Camera works only while this screen is visible. Real-time Vision analyzes at most one frame every 6 seconds, stops after 10 minutes or 3 consecutive errors, and stops immediately when Maya is hidden. Frames sent to your configured cloud provider are deleted locally and never added to long-term memory automatically.',
                style: TextStyle(
                    fontSize: 12, color: Colors.white70, height: 1.35),
              ),
            ),
          ],
        ),
      );

  Widget _statusPill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity((.68).clamp(0.0, 1.0)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity((.55).clamp(0.0, 1.0))),
        ),
        child: Text(text,
            style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1)),
      );

  Widget _controlButton(
    IconData icon,
    String label,
    Future<void> Function() action, {
    bool accent = false,
  }) =>
      SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _initializing || _analyzing ? null : action,
          icon: Icon(icon, size: 19),
          label: Text(label,
              style: const TextStyle(fontSize: 11, letterSpacing: 1.1)),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                accent ? const Color(0xFFFFA04A) : const Color(0xFF58DFFF),
            side: BorderSide(
                color:
                    (accent ? const Color(0xFFFFA04A) : const Color(0xFF58DFFF))
                        .withOpacity((.5).clamp(0.0, 1.0))),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
      );

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color color,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0D15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: SwitchListTile.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: color,
          title: Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ),
      );

  static String _short(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 180 ? text : '${text.substring(0, 180)}…';
  }
}

class _VisionHudPainter extends CustomPainter {
  final bool active;
  final Offset? focusPoint;
  const _VisionHudPainter({required this.active, this.focusPoint});

  @override
  void paint(Canvas canvas, Size size) {
    final color = active ? const Color(0xFFFF7849) : const Color(0xFF42D9FF);
    final paint = Paint()
      ..color = color.withOpacity((.8).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const length = 28.0;
    const inset = 16.0;
    final paths = <Path>[
      Path()
        ..moveTo(inset, inset + length)
        ..lineTo(inset, inset)
        ..lineTo(inset + length, inset),
      Path()
        ..moveTo(size.width - inset - length, inset)
        ..lineTo(size.width - inset, inset)
        ..lineTo(size.width - inset, inset + length),
      Path()
        ..moveTo(inset, size.height - inset - length)
        ..lineTo(inset, size.height - inset)
        ..lineTo(inset + length, size.height - inset),
      Path()
        ..moveTo(size.width - inset - length, size.height - inset)
        ..lineTo(size.width - inset, size.height - inset)
        ..lineTo(size.width - inset, size.height - inset - length),
    ];
    for (final path in paths) canvas.drawPath(path, paint);
    final scanPaint = Paint()
      ..color = color.withOpacity((active ? .32 : .14).clamp(0.0, 1.0));
    canvas.drawRect(
        Rect.fromLTWH(24, size.height * .5, size.width - 48, 1), scanPaint);
    final focus = focusPoint;
    if (focus != null) {
      final center = Offset(focus.dx * size.width, focus.dy * size.height);
      canvas.drawCircle(center, 26, paint);
      canvas.drawLine(
          center - const Offset(36, 0), center - const Offset(18, 0), paint);
      canvas.drawLine(
          center + const Offset(18, 0), center + const Offset(36, 0), paint);
      canvas.drawLine(
          center - const Offset(0, 36), center - const Offset(0, 18), paint);
      canvas.drawLine(
          center + const Offset(0, 18), center + const Offset(0, 36), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisionHudPainter oldDelegate) =>
      oldDelegate.active != active || oldDelegate.focusPoint != focusPoint;
}
