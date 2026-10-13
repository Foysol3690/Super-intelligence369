import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_core/services/language_intelligence_service.dart';
import 'package:jarvis_core/services/safe_log.dart';

void main() {
  group('local multilingual script detection', () {
    test('detects Bangla', () {
      final result = MayaLanguageIntelligenceService.detectLocal(
        'আমি বাংলায় কথা বলি',
      );
      expect(result.language, 'Bangla');
      expect(result.locale, 'bn-BD');
      expect(result.confidence, greaterThan(0.8));
    });

    test('detects Devanagari as a Hindi hypothesis with ambiguity', () {
      final result = MayaLanguageIntelligenceService.detectLocal(
        'मैं हिंदी में बात करता हूँ',
      );
      expect(result.language, 'Hindi');
      expect(result.locale, 'hi-IN');
      expect(result.evidence, contains('exact language'));
    });

    test('distinguishes Urdu-specific letters from general Arabic script', () {
      final result = MayaLanguageIntelligenceService.detectLocal(
        'میں اردو میں بات کرتا ہوں',
      );
      expect(result.language, 'Urdu');
      expect(result.locale, 'ur-PK');
    });

    test('detects Japanese, Korean and Cyrillic scripts', () {
      expect(
        MayaLanguageIntelligenceService.detectLocal('こんにちは').locale,
        'ja-JP',
      );
      expect(
        MayaLanguageIntelligenceService.detectLocal('안녕하세요').locale,
        'ko-KR',
      );
      expect(
        MayaLanguageIntelligenceService.detectLocal('Привет мир').locale,
        'ru-RU',
      );
    });

    test('does not overclaim exact Latin-script language', () {
      final result = MayaLanguageIntelligenceService.detectLocal(
        'Hola, ¿cómo estás?',
      );
      expect(result.script, 'Latin');
      expect(result.evidence, contains('exact language requires'));
      expect(result.confidence, lessThan(0.7));
    });

    test('maps user language preferences to Android TTS locales', () {
      expect(
        MayaLanguageIntelligenceService.localeForPreference('Bangla'),
        'bn-BD',
      );
      expect(
        MayaLanguageIntelligenceService.localeForPreference('ur_PK'),
        'ur-PK',
      );
      expect(
        MayaLanguageIntelligenceService.localeForPreference('auto'),
        'auto',
      );
    });
  });

  group('secret redaction', () {
    test('redacts key-bearing URLs and bearer credentials', () {
      final output = MayaSafeLog.redact(
        'failed https://example.test/ws?key=AIzaABCDEFGHIJKLMNOPQRSTUV '
        'Authorization: Bearer secret-token-value',
      );
      expect(output, isNot(contains('AIzaABCDEFGHIJKLMNOPQRSTUV')));
      expect(output, isNot(contains('secret-token-value')));
      expect(output, contains('[REDACTED]'));
    });

    test('redacts common provider and Telegram token shapes', () {
      final output = MayaSafeLog.redact(
        'sk-proj-abcdefghijklmnopqrstuvwxyz 123456789:ABCDEFGHIJKLMNOPQRSTUV',
      );
      expect(output, isNot(contains('abcdefghijklmnopqrstuvwxyz')));
      expect(output, isNot(contains('ABCDEFGHIJKLMNOPQRSTUV')));
    });
  });
}
