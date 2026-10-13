import '../unified_ai_gateway.dart';

class MayaLanguageProfile {
  final String language;
  final String script;
  final String locale;
  final double confidence;
  final String evidence;

  const MayaLanguageProfile({
    required this.language,
    required this.script,
    required this.locale,
    required this.confidence,
    required this.evidence,
  });

  Map<String, dynamic> toJson() => {
        'language': language,
        'script': script,
        'locale': locale,
        'confidence': confidence,
        'evidence': evidence,
      };
}

/// Local script detection plus provider-backed translation/transliteration.
///
/// Local detection never claims to distinguish every language sharing a
/// script. Exact language identification and translation require a configured
/// provider and retain an explicit confidence/limitation field.
class MayaLanguageIntelligenceService {
  MayaLanguageIntelligenceService({UnifiedAIGateway? gateway})
      : gateway = gateway ?? UnifiedAIGateway();

  final UnifiedAIGateway gateway;

  static const supportedPriorityLanguages = <Map<String, String>>[
    {'language': 'Bangla', 'code': 'bn', 'locale': 'bn-BD'},
    {'language': 'English', 'code': 'en', 'locale': 'en-US'},
    {'language': 'Hindi', 'code': 'hi', 'locale': 'hi-IN'},
    {'language': 'Urdu', 'code': 'ur', 'locale': 'ur-PK'},
    {'language': 'Arabic', 'code': 'ar', 'locale': 'ar-SA'},
    {'language': 'Chinese', 'code': 'zh', 'locale': 'zh-CN'},
    {'language': 'Japanese', 'code': 'ja', 'locale': 'ja-JP'},
    {'language': 'Korean', 'code': 'ko', 'locale': 'ko-KR'},
    {'language': 'Russian', 'code': 'ru', 'locale': 'ru-RU'},
  ];

  static String localeForPreference(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('_', '-');
    const locales = {
      'bangla': 'bn-BD',
      'bengali': 'bn-BD',
      'bn': 'bn-BD',
      'bn-bd': 'bn-BD',
      'english': 'en-US',
      'en': 'en-US',
      'en-us': 'en-US',
      'hindi': 'hi-IN',
      'hi': 'hi-IN',
      'hi-in': 'hi-IN',
      'urdu': 'ur-PK',
      'ur': 'ur-PK',
      'ur-pk': 'ur-PK',
      'arabic': 'ar-SA',
      'ar': 'ar-SA',
      'ar-sa': 'ar-SA',
      'chinese': 'zh-CN',
      'zh': 'zh-CN',
      'zh-cn': 'zh-CN',
      'japanese': 'ja-JP',
      'ja': 'ja-JP',
      'ja-jp': 'ja-JP',
      'korean': 'ko-KR',
      'ko': 'ko-KR',
      'ko-kr': 'ko-KR',
      'russian': 'ru-RU',
      'ru': 'ru-RU',
      'ru-ru': 'ru-RU',
    };
    return locales[normalized] ?? 'auto';
  }

  static MayaLanguageProfile detectLocal(String text) {
    final value = text.trim();
    if (value.isEmpty) {
      return const MayaLanguageProfile(
        language: 'unknown',
        script: 'unknown',
        locale: 'en-US',
        confidence: 0,
        evidence: 'No text was provided.',
      );
    }

    final counts = <String, int>{
      'bangla': _count(value, 0x0980, 0x09FF),
      'devanagari': _count(value, 0x0900, 0x097F),
      'arabic': _count(value, 0x0600, 0x06FF) +
          _count(value, 0x0750, 0x077F) +
          _count(value, 0x08A0, 0x08FF),
      'cjk': _count(value, 0x4E00, 0x9FFF),
      'hiraganaKatakana':
          _count(value, 0x3040, 0x30FF) + _count(value, 0x31F0, 0x31FF),
      'hangul': _count(value, 0xAC00, 0xD7AF),
      'cyrillic': _count(value, 0x0400, 0x04FF),
      'latin': _count(value, 0x0041, 0x024F),
    };
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final winner = ranked.first;
    final scriptCharacters =
        counts.values.fold<int>(0, (sum, count) => sum + count);
    final confidence = scriptCharacters == 0
        ? 0.25
        : (winner.value / scriptCharacters).clamp(0.25, 0.99).toDouble();

    switch (winner.key) {
      case 'bangla':
        return MayaLanguageProfile(
          language: 'Bangla',
          script: 'Bengali',
          locale: 'bn-BD',
          confidence: confidence,
          evidence: '${winner.value} Bengali-script characters.',
        );
      case 'devanagari':
        return MayaLanguageProfile(
          language: 'Hindi',
          script: 'Devanagari',
          locale: 'hi-IN',
          confidence: confidence * 0.85,
          evidence:
              'Devanagari detected; exact language may also be Marathi, Nepali, Sanskrit, or another Devanagari language.',
        );
      case 'arabic':
        final urduMarkers = RegExp(r'[ٹڈڑںھہےۓ]').allMatches(value).length;
        return MayaLanguageProfile(
          language: urduMarkers > 0 ? 'Urdu' : 'Arabic',
          script: 'Arabic',
          locale: urduMarkers > 0 ? 'ur-PK' : 'ar-SA',
          confidence: confidence * (urduMarkers > 0 ? 0.9 : 0.7),
          evidence: urduMarkers > 0
              ? 'Arabic script with Urdu-specific letters.'
              : 'Arabic script detected; provider confirmation is needed for exact language.',
        );
      case 'hiraganaKatakana':
        return MayaLanguageProfile(
          language: 'Japanese',
          script: 'Japanese',
          locale: 'ja-JP',
          confidence: confidence,
          evidence: 'Hiragana or Katakana detected.',
        );
      case 'cjk':
        return MayaLanguageProfile(
          language: 'Chinese',
          script: 'Han',
          locale: 'zh-CN',
          confidence: confidence * 0.8,
          evidence:
              'Han characters detected; Japanese text containing only Kanji requires provider confirmation.',
        );
      case 'hangul':
        return MayaLanguageProfile(
          language: 'Korean',
          script: 'Hangul',
          locale: 'ko-KR',
          confidence: confidence,
          evidence: 'Hangul detected.',
        );
      case 'cyrillic':
        return MayaLanguageProfile(
          language: 'Russian',
          script: 'Cyrillic',
          locale: 'ru-RU',
          confidence: confidence * 0.7,
          evidence:
              'Cyrillic detected; exact language requires provider confirmation.',
        );
      case 'latin':
        return MayaLanguageProfile(
          language: 'English',
          script: 'Latin',
          locale: 'en-US',
          confidence: confidence * 0.55,
          evidence:
              'Latin script detected; exact language requires provider confirmation.',
        );
      default:
        return const MayaLanguageProfile(
          language: 'unknown',
          script: 'unknown',
          locale: 'en-US',
          confidence: 0.25,
          evidence: 'No supported script dominated the text.',
        );
    }
  }

  Future<Map<String, dynamic>> detect(String text) async {
    final local = detectLocal(text);
    return {
      'success': text.trim().isNotEmpty,
      'profile': local.toJson(),
      'method': 'local_unicode_script_detection',
      'limitation':
          'Languages sharing one script require provider-backed confirmation.',
    };
  }

  Future<Map<String, dynamic>> translate({
    required String text,
    required String targetLanguage,
    String sourceLanguage = 'auto',
    bool preserveFormatting = true,
  }) async {
    final value = text.trim();
    final target = targetLanguage.trim();
    if (value.isEmpty || target.isEmpty) {
      return {
        'success': false,
        'error': 'Text and target language are required.',
      };
    }
    if (value.length > 8000) {
      return {
        'success': false,
        'error': 'Translation text exceeds the 8,000-character limit.',
      };
    }
    final local = detectLocal(value);
    final source =
        sourceLanguage.trim().isEmpty || sourceLanguage.toLowerCase() == 'auto'
            ? '${local.language} (locally inferred from ${local.script} script)'
            : sourceLanguage.trim();
    final prompt = '''
Translate the text below from $source into $target.
Return only the translation. Do not answer or explain the text.
${preserveFormatting ? 'Preserve line breaks, lists, names, numbers, and formatting.' : 'Use natural target-language prose.'}
If an essential phrase is ambiguous, preserve it and append [uncertain] immediately after that phrase.

TEXT:
$value
''';
    final output = (await gateway.query(
      prompt,
      systemPrompt:
          'You are MAYA Translation Engine. Translate faithfully, preserve meaning and uncertainty, never add facts, and output only the requested translation.',
    ))
        .trim();
    if (output.isEmpty ||
        output.toLowerCase().startsWith("i'm offline") ||
        output.toLowerCase().startsWith('i am offline')) {
      return {
        'success': false,
        'providerRequired': true,
        'detected': local.toJson(),
        'error':
            'A configured online translation-capable AI provider is required.',
      };
    }
    return {
      'success': true,
      'sourceLanguage': source,
      'targetLanguage': target,
      'detected': local.toJson(),
      'translation': output,
      'method': 'configured_ai_provider',
      'confidence': 'provider_generated_unverified',
    };
  }

  Future<Map<String, dynamic>> transliterate({
    required String text,
    required String targetScript,
  }) async {
    final value = text.trim();
    final script = targetScript.trim();
    if (value.isEmpty || script.isEmpty) {
      return {
        'success': false,
        'error': 'Text and target script are required.',
      };
    }
    if (value.length > 4000) {
      return {
        'success': false,
        'error': 'Transliteration text exceeds the 4,000-character limit.',
      };
    }
    final output = (await gateway.query(
      'Transliterate the following text into $script. Preserve pronunciation, names, punctuation, numbers, and line breaks. Return only the transliteration.\\n\\n$value',
      systemPrompt:
          'You are MAYA Transliteration Engine. Transliterate characters and pronunciation only; do not translate, answer, or add facts.',
    ))
        .trim();
    if (output.isEmpty ||
        output.toLowerCase().startsWith("i'm offline") ||
        output.toLowerCase().startsWith('i am offline')) {
      return {
        'success': false,
        'providerRequired': true,
        'error':
            'A configured online transliteration-capable AI provider is required.',
      };
    }
    return {
      'success': true,
      'targetScript': script,
      'transliteration': output,
      'method': 'configured_ai_provider',
    };
  }

  Future<Map<String, dynamic>> status() async => {
        'success': true,
        'localDetection': true,
        'translation': 'configured_provider_required',
        'transliteration': 'configured_provider_required',
        'priorityLanguages': supportedPriorityLanguages,
        'offlineTranslationModel': false,
        'uiLocalization': false,
      };

  static int _count(String value, int start, int end) {
    var count = 0;
    for (final rune in value.runes) {
      if (rune >= start && rune <= end) count++;
    }
    return count;
  }
}
