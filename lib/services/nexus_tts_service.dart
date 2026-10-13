import 'package:flutter_tts/flutter_tts.dart';

import 'language_intelligence_service.dart';
import 'maya_persona_service.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();

  Future<void> init({
    required void Function() onStart,
    required void Function() onDone,
  }) async {
    await _tts.awaitSpeakCompletion(false);
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.05);
    await _tts.setVolume(1.0);
    _tts.setStartHandler(onStart);
    _tts.setCompletionHandler(onDone);
    _tts.setCancelHandler(onDone);
    _tts.setErrorHandler((_) => onDone());
  }

  Future<void> speak(String text, {MayaPersona? persona}) async {
    // Shares MayaLanguageIntelligenceService's 9-script detector (Bangla,
    // Hindi, Urdu, Arabic, Chinese, Japanese, Korean, Russian, Latin)
    // instead of a separate 2-language regex, so there's one source of
    // truth for "what language is this text" across the app.
    final profile = MayaLanguageIntelligenceService.detectLocal(text);
    try {
      await _tts.setLanguage(profile.locale);
    } catch (_) {
      // Voice pack for that locale isn't installed on this device — fall
      // back rather than leaving TTS silently stuck.
      await _tts.setLanguage('en-US');
    }

    // Small, deliberately subtle pitch shift per persona (flutter_tts
    // accepts 0.5-2.0) so "Three personalities" is a distinct voice, not
    // only different wording. Default matches the original fixed pitch.
    final pitch = switch (persona?.id) {
      'professional' => 1.0,
      'venom' => 0.9,
      'gf' => 1.1,
      _ => 1.05,
    };
    await _tts.setPitch(pitch);

    final calm = text.length > 220;
    await _tts.setSpeechRate(calm ? 0.46 : 0.5);
    await _tts.speak(text);
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
