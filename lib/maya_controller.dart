import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import '../secure_config_manager.dart';
import '../services/device_control_service.dart';
import '../services/language_intelligence_service.dart';
import '../services/maya_automation_service.dart';
import '../services/maya_omega_voice_bridge.dart';
import '../services/maya_persona_service.dart';
import '../services/maya_settings_service.dart';
import '../services/memory_service.dart';
import '../services/nexus_gemini_service.dart';
import '../services/nexus_speech_service.dart';
import '../services/nexus_tts_service.dart';
import 'maya_state.dart';

class MayaController extends ChangeNotifier {
  MayaController({
    GeminiService? gemini,
    SpeechService? speech,
    TtsService? tts,
  })  : _gemini = gemini ?? GeminiService(),
        _speech = speech ?? SpeechService(),
        _tts    = tts    ?? TtsService();

  static const _maxTurns = 20;

  final GeminiService _gemini;
  final SpeechService _speech;
  final TtsService    _tts;
  final _settings    = MayaSettingsService();
  final _memory      = MemoryService();
  final _automations = MayaAutomationService();
  final _omegaVision = MayaOmegaVoiceBridge();

  final List<ChatTurn> _history = [];
  OrbState _state     = OrbState.idle;
  String   _transcript = '';
  String?  _lastError;
  bool     _systemOnline = false;
  bool     _initialized  = false;
  Timer?   _speakPulse;

  // Auto wake-word ("say 'Maya' to start talking") — passive, foreground-only
  // listening while idle. _passiveBlocked latches true after a real mic/STT
  // error so a denied permission can't retry-storm; refreshConfig() (run
  // again every time Settings/GOD-MODE closes) clears it and tries again.
  bool _wakeWordEnabled  = true;
  bool _speechReady      = false;
  bool _passiveListening = false;
  bool _passiveBlocked   = false;

  // Barge-in: let the user talk over Maya instead of only tapping to
  // interrupt. Shares the wake-word engine and its single-callback-pair
  // constraint, so it's dispatched through the same two handlers below.
  // Gated by the existing (previously unread) bargeInEnabled setting.
  bool _bargeInEnabled   = true;
  bool _bargeInListening = false;
  int  _speakStartToken  = 0;

  // Smoothed audio bands — updated by speech-level events
  double _smoothLevel  = 0;
  double _smoothBass   = 0;
  double _smoothMid    = 0;
  double _smoothTreble = 0;
  double _pulse        = 0;

  /// 0..1 overall audio energy that drives the visuals
  final ValueNotifier<double> level = ValueNotifier(0);

  OrbState get state         => _state;
  String   get transcript    => _transcript;
  String?  get lastError     => _lastError;
  bool     get systemOnline  => _systemOnline;
  bool     get geminiConfigured  => _gemini.isConfigured;
  bool     get wakeWordEnabled   => _wakeWordEnabled;
  bool     get wakeWordListening => _passiveListening;
  bool     get bargeInEnabled    => _bargeInEnabled;

  Future<void> init() async {
    if (_initialized) return;
    _initialized  = true;
    await refreshConfig();
    await _tts.init(onStart: _onSpeakStart, onDone: _onSpeakDone);
    notifyListeners();
  }

  /// Re-checks provider keys and the wake-word preference. Called at boot
  /// and every time Settings or the GOD-MODE dashboard is closed, so a key
  /// or toggle saved there takes effect immediately instead of only after
  /// the next app restart.
  Future<void> refreshConfig() async {
    final geminiKey = await _gemini.resolveApiKey(refresh: true);
    _systemOnline = geminiKey.isNotEmpty || _gemini.isConfigured;
    if (!_systemOnline) {
      final providers = await SecureConfigManager().getAvailableBackends();
      _systemOnline = providers.entries.any(
        (entry) => entry.key != 'telegram' && entry.value,
      );
    }
    final wakeWordEnabled = await _settings.get('wakeWordEnabled', true);
    _wakeWordEnabled = wakeWordEnabled;
    if (!_wakeWordEnabled) _passiveListening = false;
    _bargeInEnabled = await _settings.get('bargeInEnabled', true);
    notifyListeners();
    if (_wakeWordEnabled) {
      _passiveBlocked = false;
      unawaited(_schedulePassiveListen());
    }
    if (await _settings.get('backgroundTasks', true)) {
      unawaited(_automations.runForegroundChecks());
    }
  }

  Future<void> toggle() async {
    HapticFeedback.mediumImpact();
    switch (_state) {
      case OrbState.idle:
      case OrbState.error:
        await _startListening();
      case OrbState.listening:
        await _speech.stop();
      case OrbState.speaking:
        await _tts.stop();
        await _startListening();
      case OrbState.thinking:
        break;
    }
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechReady) return true;
    _speechReady = await _speech.init(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
    );
    return _speechReady;
  }

  // speech_to_text only keeps the FIRST onStatus/onError pair ever
  // registered (re-calling init() with new closures is a no-op once ready),
  // so passive listening, barge-in listening and active listening all share
  // these two dispatchers instead of each wiring up their own.
  void _onSpeechStatus(String status) {
    if (status != 'done' && status != 'notListening') return;
    if (_passiveListening) {
      _passiveListening = false;
      unawaited(_schedulePassiveListen());
    } else if (_bargeInListening) {
      _bargeInListening = false;
      // Still speaking and nothing was heard yet — keep listening for an
      // interruption. If she's since finished on her own, there's nothing
      // to resume; the idle transition already arms wake-word listening.
      if (_state == OrbState.speaking) {
        unawaited(_scheduleBargeInListen(_speakStartToken));
      }
    } else if (_state == OrbState.listening) {
      _finishListening();
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    if (_passiveListening) {
      _passiveListening = false;
      // Silence/no-match is the normal case for always-on listening — just
      // keep going. A harder error (mic taken by another app, engine
      // unavailable) backs off instead of retry-storming.
      if (error.errorMsg == 'error_no_match' ||
          error.errorMsg == 'error_speech_timeout') {
        unawaited(_schedulePassiveListen());
      } else {
        _passiveBlocked = true;
      }
      return;
    }
    if (_bargeInListening) {
      _bargeInListening = false;
      if (error.errorMsg == 'error_no_match' ||
          error.errorMsg == 'error_speech_timeout') {
        if (_state == OrbState.speaking) {
          unawaited(_scheduleBargeInListen(_speakStartToken));
        }
      } else {
        _passiveBlocked = true;
      }
      return;
    }
    if (_state == OrbState.listening) {
      _fail(error.errorMsg == 'error_no_match'
          ? null : 'Mic error: ${error.errorMsg}');
    }
  }

  /// Say "Maya" while idle to start talking hands-free, without tapping the
  /// orb. Only runs while the app is open and the screen is on — it listens
  /// in short bursts and quietly restarts itself; it never shows an error
  /// to the user for ordinary silence. Turn off from MAYA GOD-MODE → Talk &
  /// control → "Wake and sleep phrases" if you'd rather tap-only.
  ///
  /// Uses a long listenFor (55s, vs. the 30s default used for active
  /// listening) deliberately: every restart re-opens the native Android
  /// recognizer, which is the most likely source of a start/stop sound some
  /// phones play on every listen() call — the speech_to_text package has no
  /// flag to suppress that OS-level tone, so the real lever available here
  /// is restarting less often while idle, not eliminating the sound outright.
  Future<void> _schedulePassiveListen() async {
    if (!_wakeWordEnabled || _passiveBlocked) return;
    if (_state != OrbState.idle || _passiveListening) return;
    final ready = await _ensureSpeechReady();
    if (!ready) {
      _passiveBlocked = true;
      return;
    }
    // State may have moved on while we were awaiting init.
    if (!_wakeWordEnabled || _state != OrbState.idle || _passiveListening) {
      return;
    }
    _passiveListening = true;
    await _speech.listen(
      listenFor: const Duration(seconds: 55),
      onResult: (words, isFinal) {
        if (!_passiveListening) return;
        if (words.toLowerCase().contains('maya')) {
          _passiveListening = false;
          unawaited(_handOffFromWakeWord());
        }
      },
      onLevel: (_) {},
    );
  }

  Future<void> _handOffFromWakeWord() async {
    await _speech.stop();
    if (_state == OrbState.idle) {
      HapticFeedback.selectionClick();
      await _startListening();
    }
  }

  /// Lets the user talk over Maya instead of only tapping the orb to
  /// interrupt her. Starts shortly after she begins speaking (not
  /// immediately — avoids catching the attack transient of her own voice
  /// starting) and only while still speaking. Best-effort: without a device
  /// to test on, this can't be verified against echo pickup of Maya's own
  /// TTS output on every phone's mic/speaker combination, so it requires a
  /// couple of real words, not a single syllable, before treating it as a
  /// genuine interruption rather than her own voice bleeding into the mic.
  Future<void> _scheduleBargeInListen(int token) async {
    if (!_bargeInEnabled || _passiveBlocked) return;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (token != _speakStartToken || _state != OrbState.speaking) return;
    if (_bargeInListening) return;
    final ready = await _ensureSpeechReady();
    if (!ready) return;
    if (token != _speakStartToken || _state != OrbState.speaking) return;
    _bargeInListening = true;
    await _speech.listen(
      onResult: (words, isFinal) {
        if (!_bargeInListening) return;
        final meaningful = words.trim().split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty).length;
        if (meaningful >= 2) {
          _bargeInListening = false;
          unawaited(_handOffFromBargeIn());
        }
      },
      onLevel: (_) {},
    );
  }

  Future<void> _handOffFromBargeIn() async {
    await _speech.stop();
    await _tts.stop();
    if (_state == OrbState.speaking || _state == OrbState.idle) {
      HapticFeedback.mediumImpact();
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    _passiveListening = false;
    _bargeInListening = false;
    await _speech.stop();
    final ok = await _ensureSpeechReady();
    if (!ok) {
      _fail('Microphone permission denied or STT unavailable.');
      return;
    }
    _transcript = '';
    _lastError  = null;
    _setState(OrbState.listening);
    await _speech.listen(
      onResult: (words, isFinal) {
        _transcript = words;
        notifyListeners();
        if (isFinal) _finishListening();
      },
      onLevel: _onLevel,
    );
  }

  void _onLevel(double raw) {
    // Smooth overall level
    _smoothLevel = _smoothLevel * 0.55 + raw * 0.45;
    // Derive simulated frequency bands
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    _smoothBass   = (_smoothBass   * 0.7 + (raw * (0.6 + math.sin(t * 2.1)  * 0.3)) * 0.3).clamp(0, 1);
    _smoothMid    = (_smoothMid    * 0.6 + (raw * (0.5 + math.sin(t * 5.7)  * 0.4)) * 0.4).clamp(0, 1);
    _smoothTreble = (_smoothTreble * 0.5 + (raw * (0.4 + math.sin(t * 11.3) * 0.5)) * 0.5).clamp(0, 1);
    // Beat/pulse detection: spike when level jumps
    final delta = raw - _smoothLevel;
    _pulse = (_pulse * 0.8 + (delta > 0.15 ? delta : 0) * 1.5).clamp(0, 1);
    level.value = _smoothLevel;
    notifyListeners();
  }

  bool _handlingFinal = false;

  Future<void> _finishListening() async {
    if (_handlingFinal || _state != OrbState.listening) return;
    _handlingFinal = true;
    _smoothLevel = _smoothBass = _smoothMid = _smoothTreble = _pulse = 0;
    level.value  = 0;

    final text = _transcript.trim();
    if (text.isEmpty) {
      _handlingFinal = false;
      _setState(OrbState.idle);
      return;
    }

    _setState(OrbState.thinking);
    _addTurn(ChatTurn(fromUser: true, text: text));

    try {
      final persona = MayaPersonaService.byId(
        await _settings.get('selectedPersona', 'maya'),
      );
      final extraContext = await _buildExtraContext(text, persona);
      final reply = await _gemini.reply(_history, extraContext: extraContext);
      _systemOnline = true;
      // Exactly one of these five handles a leading [ACTION:...] tag, in
      // priority order — memory, persona, automation and vision tags are
      // narrower and must be checked before DeviceControlService, whose tag
      // regex is broad enough to also match theirs and would otherwise
      // silently swallow them as an "unknown action". A plain reply with no
      // tag falls through all five unchanged.
      var spoken = (await _memory.tryHandleActionTag(reply)) ??
          (await MayaPersonaService.tryHandleActionTag(reply, _settings)) ??
          (await _automations.tryHandleActionTag(reply)) ??
          (await _omegaVision.tryHandleActionTag(reply)) ??
          await DeviceControlService.parseAndExecute(reply);
      if (spoken.trim().isEmpty) spoken = 'Done.';
      _addTurn(ChatTurn(fromUser: false, text: spoken));
      _setState(OrbState.speaking);
      // Re-read the persona rather than reusing the one above: if this very
      // reply just switched it, the confirmation should speak in the new
      // voice, not the one that was active when the turn started.
      final spokenAs = MayaPersonaService.byId(
        await _settings.get('selectedPersona', 'maya'),
      );
      await _tts.speak(spoken, persona: spokenAs);
    } on GeminiException catch (e) {
      _systemOnline = false;
      _history.removeLast();
      _fail(e.message);
      if (!_gemini.isConfigured) {
        await _tts.speak('My AI is not connected yet. Add an API key in Settings.');
      }
    } catch (_) {
      _systemOnline = false;
      if (_history.isNotEmpty) _history.removeLast();
      _fail('Network error. Check your connection.');
    } finally {
      _handlingFinal = false;
    }
  }

  /// Relevant remembered facts, the language the user just used, and the
  /// active persona's tone — assembled fresh every turn since all three can
  /// change between turns (memory grows, the speaker can switch languages
  /// mid-conversation, a persona switch takes effect immediately).
  Future<String?> _buildExtraContext(String userText, MayaPersona persona) async {
    final parts = <String>[];

    final memoryEnabled = await _settings.get('memoryEnabled', true);
    if (memoryEnabled) {
      // Pass the user's actual message so retrieval is relevant to this
      // turn instead of injecting the same top memories into every prompt.
      final memoryContext = await _memory.promptContext(query: userText);
      if (memoryContext.isNotEmpty) parts.add(memoryContext);
    }

    final language = MayaLanguageIntelligenceService.detectLocal(userText);
    if (language.language != 'unknown' && language.confidence >= 0.4) {
      parts.add(
        'The user just spoke in ${language.language} (${language.script} script). '
        'Mirror that language in your reply unless they clearly ask to switch.',
      );
    }

    parts.add(persona.toneInstruction);

    return parts.isEmpty ? null : parts.join('\n\n');
  }

  void _onSpeakStart() {
    if (_state != OrbState.speaking) _setState(OrbState.speaking);
    _speakPulse?.cancel();
    final rnd = math.Random();
    var t = 0.0;
    _speakPulse = Timer.periodic(const Duration(milliseconds: 50), (_) {
      t += 0.4;
      final syllable = (math.sin(t) * 0.5 + 0.5) * 0.65 + rnd.nextDouble() * 0.35;
      _onLevel(level.value * 0.45 + syllable * 0.55);
    });
    final token = ++_speakStartToken;
    unawaited(_scheduleBargeInListen(token));
  }

  void _onSpeakDone() {
    _speakPulse?.cancel();
    _smoothLevel = _smoothBass = _smoothMid = _smoothTreble = _pulse = 0;
    level.value  = 0;
    _speakStartToken++;
    if (_bargeInListening) {
      _bargeInListening = false;
      unawaited(_speech.stop());
    }
    if (_state == OrbState.speaking) _setState(OrbState.idle);
  }

  void _addTurn(ChatTurn turn) {
    _history.add(turn);
    if (_history.length > _maxTurns) {
      _history.removeRange(0, _history.length - _maxTurns);
    }
  }

  void _fail(String? message) {
    _smoothLevel = _smoothBass = _smoothMid = _smoothTreble = _pulse = 0;
    level.value  = 0;
    _lastError   = message;
    _setState(message == null ? OrbState.idle : OrbState.error);
  }

  void _setState(OrbState next) {
    _state = next;
    notifyListeners();
    if (next == OrbState.idle) unawaited(_schedulePassiveListen());
  }

  @override
  void dispose() {
    _speakPulse?.cancel();
    _passiveListening = false;
    _speech.cancel();
    _tts.stop();
    _gemini.dispose();
    level.dispose();
    super.dispose();
  }
}
