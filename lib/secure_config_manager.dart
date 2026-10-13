import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureConfigManager {
  static final SecureConfigManager _instance = SecureConfigManager._internal();
  factory SecureConfigManager() => _instance;
  SecureConfigManager._internal();

  final _storage = const FlutterSecureStorage();

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key).timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      final msg = e.message ?? '';
      if (msg.contains('NullPointerException') ||
          msg.contains('StorageCipher')) {
        await _storage.deleteAll();
        await _storage.write(key: key, value: value);
      } else {
        rethrow;
      }
    }
  }

  Future<void> setGroqKey(String key) => _safeWrite('groq_api_key', key);
  Future<void> setOpenRouterKey(String key) =>
      _safeWrite('openrouter_api_key', key);
  Future<void> setGeminiKey(String key) => _safeWrite('gemini_api_key', key);
  Future<void> setCerebrasKey(String key) =>
      _safeWrite('cerebras_api_key', key);
  Future<void> setMistralKey(String key) => _safeWrite('mistral_api_key', key);
  Future<void> setNaraKey(String key) => _safeWrite('nara_api_key', key);
  Future<void> setOpenAIKey(String key) => _safeWrite('openai_api_key', key);
  Future<void> setClaudeKey(String key) => _safeWrite('claude_api_key', key);
  Future<void> setHuggingFaceKey(String key) =>
      _safeWrite('huggingface_api_key', key);
  Future<void> setTelegramToken(String key) async {
    final old = await getTelegramToken();
    await _safeWrite('telegram_bot_token', key);
    if (old != key) await _storage.delete(key: 'telegram_update_offset');
  }

  Future<void> setTelegramChatId(String id) =>
      _safeWrite('telegram_chat_id', id);
  Future<void> setTelegramUpdateOffset(int offset) =>
      _safeWrite('telegram_update_offset', offset.toString());
  Future<void> markConfigured() => _safeWrite('is_configured', 'true');

  Future<String?> getGroqKey() => _safeRead('groq_api_key');
  Future<String?> getOpenRouterKey() => _safeRead('openrouter_api_key');
  Future<String?> getGeminiKey() => _safeRead('gemini_api_key');
  Future<String?> getCerebrasKey() => _safeRead('cerebras_api_key');
  Future<String?> getMistralKey() => _safeRead('mistral_api_key');
  Future<String?> getNaraKey() => _safeRead('nara_api_key');
  Future<String?> getOpenAIKey() => _safeRead('openai_api_key');
  Future<String?> getClaudeKey() => _safeRead('claude_api_key');
  Future<String?> getHuggingFaceKey() => _safeRead('huggingface_api_key');
  Future<String?> getTelegramToken() => _safeRead('telegram_bot_token');
  Future<String?> getTelegramChatId() => _safeRead('telegram_chat_id');
  Future<int> getTelegramUpdateOffset() async =>
      int.tryParse(await _safeRead('telegram_update_offset') ?? '') ?? 0;

  Future<bool> isConfigured() async {
    final val = await _safeRead('is_configured');
    return val == 'true';
  }

  Future<Map<String, bool>> getAvailableBackends() async {
    return {
      'groq': (await getGroqKey())?.isNotEmpty ?? false,
      'openrouter': (await getOpenRouterKey())?.isNotEmpty ?? false,
      'gemini': (await getGeminiKey())?.isNotEmpty ?? false,
      'cerebras': (await getCerebrasKey())?.isNotEmpty ?? false,
      'mistral': (await getMistralKey())?.isNotEmpty ?? false,
      'nara': (await getNaraKey())?.isNotEmpty ?? false,
      'openai': (await getOpenAIKey())?.isNotEmpty ?? false,
      'claude': (await getClaudeKey())?.isNotEmpty ?? false,
      'huggingface': (await getHuggingFaceKey())?.isNotEmpty ?? false,
      'telegram': (await getTelegramToken())?.isNotEmpty ?? false,
    };
  }
}
