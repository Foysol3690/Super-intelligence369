import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../secure_config_manager.dart';
import 'language_intelligence_service.dart';
import 'maya_settings_service.dart';
import 'safe_log.dart';

/// Gemini is preferred; Android native TTS is a local fallback.
class TtsService {
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _nativeTts = FlutterTts();
  final SecureConfigManager _config = SecureConfigManager();
  final MayaSettingsService _settings = MayaSettingsService();

  bool isSpeaking = false;
  String? lastError;

  static const String _model = 'gemini-2.5-flash-preview-tts';
  static const String _defaultVoiceName = 'Laomedeia';

  Future<void> init() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
    } catch (e) {
      print('[TTS] player init warning: $e');
    }
    try {
      await _nativeTts.awaitSpeakCompletion(true);
      await _nativeTts.setLanguage('en-US');
      await _nativeTts.setSpeechRate(0.48);
      await _nativeTts.setVolume(1.0);
      await _nativeTts.setPitch(1.0);
    } catch (e) {
      print('[TTS] native init warning: $e');
    }
  }

  Future<void> speak(
    String text, {
    String voiceName = _defaultVoiceName,
    double rate = 0.48,
    double pitch = 1.0,
    String locale = 'auto',
  }) async {
    final phrase = text.trim();
    if (phrase.isEmpty) return;
    if (isSpeaking) await stop();
    isSpeaking = true;
    lastError = null;
    try {
      final key = (await _config.getGeminiKey())?.trim();
      var cloudWorked = false;
      if (key != null && key.isNotEmpty) {
        cloudWorked = await _speakGemini(phrase, key, voiceName);
      }
      if (!cloudWorked) {
        final preferredLanguage =
            await _settings.get<String>('language', 'auto');
        final preferredLocale =
            MayaLanguageIntelligenceService.localeForPreference(
          preferredLanguage,
        );
        final selectedLocale = locale.toLowerCase() != 'auto'
            ? locale
            : preferredLocale != 'auto'
                ? preferredLocale
                : MayaLanguageIntelligenceService.detectLocal(phrase).locale;
        await _speakNative(
          phrase,
          rate: rate,
          pitch: pitch,
          locale: selectedLocale,
        );
        lastError = null;
      }
    } catch (e) {
      lastError = 'Speech output failed: ${_shortError(e)}';
      MayaSafeLog.debug('TTS', lastError);
    } finally {
      isSpeaking = false;
    }
  }

  Future<bool> _speakGemini(String text, String key, String voiceName) async {
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$_model:generateContent',
      {'key': key},
    );
    try {
      var response = await _request(uri, text, voiceName);
      if (response.statusCode == 429) {
        await Future.delayed(const Duration(seconds: 3));
        response = await _request(uri, text, voiceName);
      }
      if (response.statusCode != 200) {
        lastError =
            'Gemini TTS HTTP ${response.statusCode}: ${_shortError(response.body)}';
        MayaSafeLog.debug('TTS', lastError);
        return false;
      }
      final audio = _findAudio(jsonDecode(response.body));
      if (audio == null || audio.isEmpty) {
        lastError = 'Gemini TTS returned no audio data';
        MayaSafeLog.debug('TTS', lastError);
        return false;
      }
      final pcm = base64Decode(audio);
      final file = File(
        '${(await getTemporaryDirectory()).path}/maya_speech_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      try {
        await file.writeAsBytes(_pcmToWav(pcm), flush: true);
        final completed = _player.onPlayerComplete.first;
        await _player.play(DeviceFileSource(file.path));
        await completed.timeout(const Duration(seconds: 90));
        return true;
      } finally {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    } on TimeoutException {
      lastError = 'Gemini TTS timed out';
      return false;
    } on FormatException catch (e) {
      lastError = 'Gemini TTS invalid audio: ${e.message}';
      return false;
    } catch (e) {
      lastError = 'Gemini TTS exception: ${_shortError(e)}';
      MayaSafeLog.debug('TTS', lastError);
      return false;
    }
  }

  Future<http.Response> _request(Uri uri, String text, String voiceName) => http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': text}
              ]
            }
          ],
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': voiceName}
              }
            }
          }
        }),
      )
      .timeout(const Duration(seconds: 20));

  Future<void> _speakNative(
    String text, {
    required double rate,
    required double pitch,
    required String locale,
  }) async {
    try {
      await _player.stop();
      await _nativeTts.stop();
      final available = await _nativeTts.isLanguageAvailable(locale);
      await _nativeTts.setLanguage(
        available == true || available == 1 ? locale : 'en-US',
      );
      await _nativeTts.setSpeechRate(rate.clamp(0.25, 0.75).toDouble());
      await _nativeTts.setPitch(pitch.clamp(0.5, 1.5).toDouble());
      await _nativeTts.setVolume(1.0);
      await _nativeTts.speak(text);
    } catch (e) {
      lastError = 'Native speech failed: ${_shortError(e)}';
      rethrow;
    }
  }

  String? _findAudio(Object? decoded) {
    if (decoded is! Map || decoded['candidates'] is! List) return null;
    for (final candidate in decoded['candidates'] as List) {
      if (candidate is! Map || candidate['content'] is! Map) continue;
      final parts = candidate['content']['parts'];
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is! Map) continue;
        final inline = part['inlineData'] ?? part['inline_data'];
        if (inline is Map && inline['data'] is String)
          return inline['data'] as String;
      }
    }
    return null;
  }

  Uint8List _pcmToWav(Uint8List pcm) {
    const sampleRate = 24000;
    const channels = 1;
    const bits = 16;
    final byteRate = sampleRate * channels * bits ~/ 8;
    final align = channels * bits ~/ 8;
    final header = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add(_bytes(36 + pcm.length, 4))
      ..add(ascii.encode('WAVEfmt '))
      ..add(_bytes(16, 4))
      ..add(_bytes(1, 2))
      ..add(_bytes(channels, 2))
      ..add(_bytes(sampleRate, 4))
      ..add(_bytes(byteRate, 4))
      ..add(_bytes(align, 2))
      ..add(_bytes(bits, 2))
      ..add(ascii.encode('data'))
      ..add(_bytes(pcm.length, 4))
      ..add(pcm);
    return header.toBytes();
  }

  Uint8List _bytes(int value, int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) out[i] = (value >> (8 * i)) & 0xff;
    return out;
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _nativeTts.stop();
    } catch (_) {}
    isSpeaking = false;
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player.dispose();
    } catch (_) {}
  }

  static String _shortError(Object error, [int max = 240]) {
    final text = MayaSafeLog.redact(error, max: max);
    return text.length <= max ? text : '${text.substring(0, max)}…';
  }
}
