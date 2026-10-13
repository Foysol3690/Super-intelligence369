import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

import 'dart:convert';

import 'secure_config_manager.dart';
import 'services/safe_log.dart';

class UnifiedAIGateway {
  final _config = SecureConfigManager();
  static const _gatewayChannel = MethodChannel(
    'com.foysol.jarvis/offline_gateway',
  );

  void _logFailure(String provider, http.Response response) {
    // Try to surface the provider's actual error message (e.g. "invalid
    // API key", "model not found") instead of just a bare status code —
    // but only the terse error field, never the raw body, since that could
    // echo back prompt content into local debug logs.
    var reason = 'HTTP ${response.statusCode}';
    try {
      final data = jsonDecode(response.body);
      final error = data is Map ? data['error'] : null;
      final message = error is Map
          ? error['message'] as String?
          : error is String
              ? error
              : null;
      if (message != null && message.trim().isNotEmpty) {
        reason = '$reason: ${message.trim()}';
      }
    } catch (_) {
      // Not JSON, or not the shape we expected — stick with the bare code.
    }
    MayaSafeLog.debug('Gateway', '$provider failed with $reason.');
  }

  Future<String> query(String prompt, {String? systemPrompt}) async {
    final system =
        systemPrompt ??
        "You are Maya, a warm, calm, caring AI companion. Speak naturally and warmly, like someone who genuinely cares - not like a formal assistant or search engine. Keep replies concise and conversational. Always reply in the same language the user's message is written in.";

    final offlineResult = await _queryOfflineGateway(prompt);
    if (offlineResult.isNotEmpty) return offlineResult;

    final groqKey = await _config.getGroqKey();
    if (groqKey?.isNotEmpty ?? false) {
      final result = await _queryGroq(prompt, system, groqKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    final claudeKey = await _config.getClaudeKey();
    if (claudeKey?.isNotEmpty ?? false) {
      final result = await _queryClaude(prompt, system, claudeKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    final openaiKey = await _config.getOpenAIKey();
    if (openaiKey?.isNotEmpty ?? false) {
      final result = await _queryOpenAI(prompt, system, openaiKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    final geminiKey = await _config.getGeminiKey();
    if (geminiKey?.isNotEmpty ?? false) {
      final result = await _queryGemini(prompt, system, geminiKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    final openrouterKey = await _config.getOpenRouterKey();
    if (openrouterKey?.isNotEmpty ?? false) {
      final result = await _queryOpenRouter(prompt, system, openrouterKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    final mistralKey = await _config.getMistralKey();
    if (mistralKey?.isNotEmpty ?? false) {
      final result = await _queryMistral(prompt, system, mistralKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    final cerebasKey = await _config.getCerebrasKey();
    if (cerebasKey?.isNotEmpty ?? false) {
      final result = await _queryCerebras(prompt, system, cerebasKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    final naraKey = await _config.getNaraKey();
    if (naraKey?.isNotEmpty ?? false) {
      final result = await _queryNara(prompt, system, naraKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    final hfKey = await _config.getHuggingFaceKey();
    if (hfKey?.isNotEmpty ?? false) {
      final result = await _queryHuggingFace(prompt, system, hfKey!);
      if (result.isNotEmpty) {
        await _cacheOnline(prompt, result);
        return result;
      }
    }

    return "I'm offline and don't have anything for that.";
  }

  Future<String> _queryOfflineGateway(String prompt) async {
    try {
      final running =
          await _gatewayChannel.invokeMethod<bool>('isOfflineGatewayRunning') ??
          false;
      if (!running) return '';
      final response = await http
          .post(
            Uri.parse('http://127.0.0.1:8000/v1/chat/completions'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'Offline gateway error: $e');
    }
    return '';
  }

  Future<void> _cacheOnline(String prompt, String response) async {
    try {
      await http
          .post(
            Uri.parse('http://127.0.0.1:8000/v1/cache/store'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'prompt': prompt,
              'response': response,
              'source': 'cloud',
            }),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<String> _queryGroq(String prompt, String system, String apiKey) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'openai/gpt-oss-120b',
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
      _logFailure('Groq', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'Groq error: $e');
    }
    return '';
  }

  Future<String> _queryClaude(
    String prompt,
    String system,
    String apiKey,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'x-api-key': apiKey,
              'Content-Type': 'application/json',
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': 'claude-sonnet-4-20250514',
              'max_tokens': 1024,
              'system': system,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['content']?[0]?['text'] as String? ?? '';
      }
      _logFailure('Claude', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'Claude error: $e');
    }
    return '';
  }

  Future<String> _queryOpenAI(
    String prompt,
    String system,
    String apiKey,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
      _logFailure('OpenAI', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'OpenAI error: $e');
    }
    return '';
  }

  Future<String> _queryGemini(
    String prompt,
    String system,
    String apiKey,
  ) async {
    try {
      final response = await http
          .post(
            Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/gemini-2.5-flash:generateContent',
              {'key': apiKey},
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': '$system\n\nUser: $prompt'},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates']?[0]?['content']?['parts']?[0]?['text']
                as String? ??
            '';
      }
      _logFailure('Gemini', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'Gemini error: $e');
    }
    return '';
  }

  Future<String> _queryOpenRouter(
    String prompt,
    String system,
    String apiKey,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'anthropic/claude-sonnet-4',
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
      _logFailure('OpenRouter', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'OpenRouter error: $e');
    }
    return '';
  }

  Future<String> _queryMistral(
    String prompt,
    String system,
    String apiKey,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.mistral.ai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'mistral-small-latest',
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
      _logFailure('Mistral', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'Mistral error: $e');
    }
    return '';
  }

  Future<String> _queryCerebras(
    String prompt,
    String system,
    String apiKey,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.cerebras.ai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'gpt-oss-120b',
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
      _logFailure('Cerebras', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'Cerebras error: $e');
    }
    return '';
  }

  Future<String> _queryNara(String prompt, String system, String apiKey) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://router.naraya.ai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'deepseek-3.2',
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
      _logFailure('Nara', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'Nara error: $e');
    }
    return '';
  }

  Future<String> _queryHuggingFace(
    String prompt,
    String system,
    String apiKey,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://router.huggingface.co/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'mistralai/Mistral-7B-Instruct-v0.3',
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'] as String? ?? '';
      }
      _logFailure('HuggingFace', response);
    } catch (e) {
      MayaSafeLog.debug('Gateway', 'HuggingFace error: $e');
    }
    return '';
  }

  Future<Map<String, String>> runDiagnostics() async {
    final results = <String, String>{};
    final checks = <String, Future<String> Function(String)>{
      'Groq': (k) => _queryGroq('ping', 'test', k),
      'Claude': (k) => _queryClaude('ping', 'test', k),
      'OpenAI': (k) => _queryOpenAI('ping', 'test', k),
      'Gemini': (k) => _queryGemini('ping', 'test', k),
      'OpenRouter': (k) => _queryOpenRouter('ping', 'test', k),
      'Mistral': (k) => _queryMistral('ping', 'test', k),
      'Cerebras': (k) => _queryCerebras('ping', 'test', k),
      'Nara': (k) => _queryNara('ping', 'test', k),
      'HuggingFace': (k) => _queryHuggingFace('ping', 'test', k),
    };
    final keyGetters = <String, Future<String?> Function()>{
      'Groq': _config.getGroqKey,
      'Claude': _config.getClaudeKey,
      'OpenAI': _config.getOpenAIKey,
      'Gemini': _config.getGeminiKey,
      'OpenRouter': _config.getOpenRouterKey,
      'Mistral': _config.getMistralKey,
      'Cerebras': _config.getCerebrasKey,
      'Nara': _config.getNaraKey,
      'HuggingFace': _config.getHuggingFaceKey,
    };
    for (final name in checks.keys) {
      final key = await keyGetters[name]!();
      if (key == null || key.isEmpty) {
        results[name] = 'NO KEY SAVED';
        continue;
      }
      try {
        final result = await checks[name]!(key);
        results[name] = result.trim().isNotEmpty
            ? 'OK'
            : 'FAILED: empty response';
      } catch (e) {
        results[name] = 'EXCEPTION: ${MayaSafeLog.redact(e)}';
      }
    }
    return results;
  }
}
