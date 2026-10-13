import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'secure_config_manager.dart';

class ConfigScreen extends StatefulWidget {
  final VoidCallback onConfigComplete;
  const ConfigScreen({super.key, required this.onConfigComplete});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ProviderField {
  final String key;
  final String label;
  final String hint;
  final Future<String?> Function() getter;
  final Future<void> Function(String) setter;
  const _ProviderField(
    this.key,
    this.label,
    this.hint,
    this.getter,
    this.setter,
  );
}

class _ConfigScreenState extends State<ConfigScreen>
    with SingleTickerProviderStateMixin {
  static const _red = Color(0xFFFF304F);
  static const _orange = Color(0xFFFF8A24);
  static const _cyan = Color(0xFF19E6FF);

  final _config = SecureConfigManager();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _visible = {};
  Map<String, bool> _active = {};
  bool _isLoading = false;
  bool _loadingExisting = true;
  String? _errorText;
  late final AnimationController _ambient;

  late final List<_ProviderField> _fields = [
    _ProviderField(
      'groq',
      'Groq',
      'sk-...',
      _config.getGroqKey,
      _config.setGroqKey,
    ),
    _ProviderField(
      'claude',
      'Claude',
      'sk-ant-...',
      _config.getClaudeKey,
      _config.setClaudeKey,
    ),
    _ProviderField(
      'openai',
      'OpenAI',
      'sk-proj-...',
      _config.getOpenAIKey,
      _config.setOpenAIKey,
    ),
    _ProviderField(
      'gemini',
      'Gemini Live + TTS',
      'AIza...',
      _config.getGeminiKey,
      _config.setGeminiKey,
    ),
    _ProviderField(
      'nara',
      'Nara Router',
      'nara_...',
      _config.getNaraKey,
      _config.setNaraKey,
    ),
    _ProviderField(
      'cerebras',
      'Cerebras',
      'csbr_...',
      _config.getCerebrasKey,
      _config.setCerebrasKey,
    ),
    _ProviderField(
      'mistral',
      'Mistral',
      'sk_...',
      _config.getMistralKey,
      _config.setMistralKey,
    ),
    _ProviderField(
      'openrouter',
      'OpenRouter',
      'sk-or-...',
      _config.getOpenRouterKey,
      _config.setOpenRouterKey,
    ),
    _ProviderField(
      'huggingface',
      'Hugging Face',
      'hf_...',
      _config.getHuggingFaceKey,
      _config.setHuggingFaceKey,
    ),
    _ProviderField(
      'telegram',
      'Telegram Bot',
      '123456:token...',
      _config.getTelegramToken,
      _config.setTelegramToken,
    ),
    _ProviderField(
      'telegramChat',
      'Telegram Owner Chat ID',
      'Send /whoami or use your numeric chat ID',
      _config.getTelegramChatId,
      _config.setTelegramChatId,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    for (final field in _fields) {
      _controllers[field.key] = TextEditingController();
      _visible[field.key] = false;
    }
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      for (final field in _fields) {
        final existing = await field.getter().timeout(
          const Duration(seconds: 4),
          onTimeout: () => null,
        );
        if (existing != null && existing.isNotEmpty) {
          _controllers[field.key]?.text = existing;
        }
      }
      final backends = await _config.getAvailableBackends().timeout(
        const Duration(seconds: 6),
        onTimeout: () => {},
      );
      if (mounted) setState(() => _active = backends);
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorText =
              'Vault read failed. Save the provider settings again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      for (final field in _fields) {
        await field.setter(_controllers[field.key]?.text.trim() ?? '');
      }
      await _config.markConfigured();
      final backends = await _config.getAvailableBackends();
      if (mounted) setState(() => _active = backends);
      if (mounted) widget.onConfigComplete();
    } catch (error) {
      if (mounted) setState(() => _errorText = 'Vault write failed: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF020408),
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _VaultAtmospherePainter(_ambient)),
            ),
          ),
          SafeArea(
            child: CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  sliver: SliverToBoxAdapter(child: _header()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                  sliver: SliverToBoxAdapter(child: _securityPanel()),
                ),
                if (_loadingExisting)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: _cyan),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    sliver: SliverList.builder(
                      itemCount: _fields.length,
                      itemBuilder: (context, index) => RepaintBoundary(
                        child: _providerCard(_fields[index], index),
                      ),
                    ),
                  ),
                if (!_loadingExisting)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 5, 18, 38),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          if (_errorText != null) ...[
                            _errorPanel(),
                            const SizedBox(height: 12),
                          ],
                          _saveButton(),
                          const SizedBox(height: 14),
                          const Text(
                            'AES-BACKED ANDROID SECURE STORAGE  •  LOCAL DEVICE ONLY',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white30,
                              fontSize: 7,
                              letterSpacing: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedBuilder(
              animation: _ambient,
              builder: (context, child) => ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment(-1.2 + _ambient.value * 2.4, -1),
                  end: Alignment(.2 + _ambient.value * 2.4, 1),
                  colors: const [_red, _orange, Colors.white, _cyan],
                ).createShader(bounds),
                child: child,
              ),
              child: const Text(
                'MAYA  GODMODE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'SOVEREIGN PROVIDER VAULT',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 8,
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
      ),
      _iconButton(Icons.close_rounded, widget.onConfigComplete),
    ],
  );

  Widget _securityPanel() {
    final connected = _active.values.where((value) => value).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _glassDecoration(_cyan.withOpacity((.25).clamp(0.0, 1.0)), 22),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [_red, _orange, _cyan]),
              boxShadow: [
                BoxShadow(color: _cyan.withOpacity((.16).clamp(0.0, 1.0)), blurRadius: 24),
              ],
            ),
            child: const Icon(Icons.shield_outlined, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$connected / ${_fields.length} CHANNELS ARMED',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Encrypted locally. Empty channels remain safely disabled.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected > 0 ? _cyan : Colors.white24,
              boxShadow: connected > 0
                  ? [
                      BoxShadow(
                        color: _cyan.withOpacity((.55).clamp(0.0, 1.0)),
                        blurRadius: 9,
                      ),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerCard(_ProviderField field, int index) {
    final accent = const [_red, _orange, _cyan][index % 3];
    final active = _active[field.key] ?? false;
    final visible = _visible[field.key] ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
        decoration: _glassDecoration(
          accent.withOpacity((active ? .46 : .19).clamp(0.0, 1.0)),
          19,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: accent.withOpacity((.08).clamp(0.0, 1.0)),
                border: Border.all(color: accent.withOpacity((.25).clamp(0.0, 1.0))),
              ),
              child: Icon(
                active ? Icons.bolt_rounded : Icons.key_rounded,
                color: active ? accent : Colors.white30,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _controllers[field.key],
                obscureText: !visible,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  labelText: field.label.toUpperCase(),
                  labelStyle: TextStyle(
                    color: accent,
                    fontSize: 9,
                    letterSpacing: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                  hintText: field.hint,
                  hintStyle: const TextStyle(
                    color: Colors.white24,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: visible ? 'Hide key' : 'Reveal key',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _visible[field.key] = !visible),
              icon: Icon(
                visible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: Colors.white38,
                size: 19,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveButton() => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(17),
      gradient: const LinearGradient(colors: [_red, _orange, _cyan]),
      boxShadow: [
        BoxShadow(color: _cyan.withOpacity((.12).clamp(0.0, 1.0)), blurRadius: 24),
      ],
    ),
    child: ElevatedButton.icon(
      onPressed: _isLoading ? null : _saveConfig,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
      icon: _isLoading
          ? const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(
              Icons.lock_outline_rounded,
              color: Colors.white,
              size: 19,
            ),
      label: Text(
        _isLoading ? 'ENCRYPTING VAULT...' : 'ENCRYPT & ARM PROVIDERS',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.35,
          fontSize: 10,
        ),
      ),
    ),
  );

  Widget _errorPanel() => Container(
    padding: const EdgeInsets.all(13),
    decoration: _glassDecoration(_red.withOpacity((.45).clamp(0.0, 1.0)), 16),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: _red, size: 18),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            _errorText!,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ),
      ],
    ),
  );

  Widget _iconButton(IconData icon, VoidCallback action) => IconButton(
    onPressed: action,
    icon: Icon(icon, color: Colors.white70),
    style: IconButton.styleFrom(
      backgroundColor: Colors.white.withOpacity((.055).clamp(0.0, 1.0)),
      side: BorderSide(color: Colors.white.withOpacity((.13).clamp(0.0, 1.0))),
    ),
  );

  BoxDecoration _glassDecoration(Color border, double radius) => BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: border),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withOpacity((.085).clamp(0.0, 1.0)),
        Colors.white.withOpacity((.022).clamp(0.0, 1.0)),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity((.24).clamp(0.0, 1.0)),
        blurRadius: 20,
        offset: const Offset(0, 9),
      ),
    ],
  );
}

class _VaultAtmospherePainter extends CustomPainter {
  final Animation<double> animation;
  _VaultAtmospherePainter(this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF020408), Color(0xFF0A0509), Color(0xFF01141B)],
        ).createShader(rect),
    );
    final t = animation.value * math.pi * 2;

    void glow(Offset center, double radius, Color color, double opacity) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withOpacity((opacity).clamp(0.0, 1.0)),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    glow(
      Offset(size.width * (.08 + .035 * math.sin(t)), size.height * .15),
      size.width * .62,
      const Color(0xFFFF304F),
      .105,
    );
    glow(
      Offset(size.width * (.97 + .025 * math.cos(t)), size.height * .46),
      size.width * .60,
      const Color(0xFFFF8A24),
      .085,
    );
    glow(
      Offset(size.width * (.48 + .04 * math.cos(t)), size.height * .92),
      size.width * .76,
      const Color(0xFF19E6FF),
      .105,
    );

    final line = Paint()
      ..color = const Color(0xFF19E6FF).withOpacity((.018).clamp(0.0, 1.0))
      ..strokeWidth = .5;
    const step = 42.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _VaultAtmospherePainter oldDelegate) => false;
}
