import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

import '../core/maya_state.dart';
import '../secure_config_manager.dart';
import '../unified_ai_gateway.dart';
import 'device_control_service.dart';
import 'maya_automation_service.dart';
import 'maya_omega_voice_bridge.dart';
import 'maya_persona_service.dart';
import 'memory_service.dart';

class GeminiException implements Exception {
  GeminiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GeminiService {
  GeminiService({http.Client? client}) : _client = client ?? http.Client();

  static const envApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const model = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-2.5-flash',
  );

  static const _systemPrompt = '''
You are MAYA, a voice-first AI assistant on the user's Android phone.
You are an AI and you say so honestly if asked. You never pretend to be a human.
Your replies are spoken aloud by text-to-speech, so:
- Keep answers short and natural: usually 1 to 3 sentences.
- Never use markdown, bullet points, code blocks, emoji or URLs.
- Reply in the same language the user spoke (English, Bengali, Banglish, Hindi, and so on).
- If the user sounds frustrated, be calmer and give one clear next step.
- If the request is unclear, ask one short clarifying question.
- For risky actions (payments, deleting data, sending messages), ask for confirmation first.

$_actionProtocol
''';

  // One shared [ACTION:...] tag protocol, composed from each subsystem's own
  // prompt fragment, so device control, memory, persona switching,
  // automations and screen vision all reuse the same mechanism instead of
  // five different ones. Each fragment is owned and documented by the class
  // that implements it.
  static const _actionProtocol =
      '${DeviceControlService.actionSystemPrompt}\n\n'
      '${MemoryService.actionSystemPrompt}\n\n'
      '${MayaPersonaService.actionSystemPrompt}\n\n'
      '${MayaAutomationService.actionSystemPrompt}\n\n'
      '${MayaOmegaVoiceBridge.actionSystemPrompt}';

  final http.Client _client;
  String? _runtimeKey;

  bool get isConfigured =>
      envApiKey.isNotEmpty ||
      (_runtimeKey != null && _runtimeKey!.isNotEmpty);

  Future<String> resolveApiKey({bool refresh = false}) async {
    if (refresh) _runtimeKey = null;
    if (envApiKey.isNotEmpty) return envApiKey;
    if (_runtimeKey != null && _runtimeKey!.isNotEmpty) return _runtimeKey!;
    final stored = await SecureConfigManager().getGeminiKey();
    if (stored != null && stored.trim().isNotEmpty) {
      _runtimeKey = stored.trim();
      return _runtimeKey!;
    }
    return '';
  }

  /// [extraContext] carries per-turn material that can't be a compile-time
  /// constant — relevant remembered facts, the language the user just used,
  /// the active persona's tone — appended after the fixed [_systemPrompt].
  Future<String> reply(List<ChatTurn> history, {String? extraContext}) async {
    final activeKey = await resolveApiKey();
    final systemInstruction = (extraContext == null || extraContext.trim().isEmpty)
        ? _systemPrompt
        : '$_systemPrompt\n\n${extraContext.trim()}';

    if (activeKey.isEmpty) {
      // Fallback to UnifiedAIGateway if another provider is configured
      final lastUserMessage = history
          .lastWhere(
            (t) => t.fromUser,
            orElse: () => ChatTurn(fromUser: true, text: ''),
          )
          .text;
      if (lastUserMessage.isNotEmpty) {
        try {
          final gateway = UnifiedAIGateway();
          final replyText = await gateway.query(
            lastUserMessage,
            systemPrompt: systemInstruction,
          );
          if (replyText.isNotEmpty) return replyText;
        } catch (_) {}
      }
      throw GeminiException('Gemini API key is missing.');
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction},
        ],
      },
      'contents': [
        for (final turn in history)
          {
            'role': turn.fromUser ? 'user' : 'model',
            'parts': [
              {'text': turn.text},
            ],
          },
      ],
      'generationConfig': {
        'temperature': 0.8,
        'maxOutputTokens': 1024,
      },
    });

    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': activeKey,
          },
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw GeminiException(_describeError(response));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    final parts = (candidates?.firstOrNull as Map<String, dynamic>?)?['content']
        ?['parts'] as List<dynamic>?;

    final text = parts
            ?.whereType<Map<String, dynamic>>()
            .where((p) => p['thought'] != true)
            .map((p) => p['text'] as String? ?? '')
            .join()
            .trim() ??
        '';

    if (text.isEmpty) {
      throw GeminiException('Gemini returned an empty reply.');
    }
    return text;
  }

  /// Turns a failed Gemini HTTP response into a message that actually says
  /// why it failed (e.g. "API key not valid", "model not found for API
  /// version"), instead of just a bare status code nobody can act on.
  String _describeError(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      final error = data is Map ? data['error'] : null;
      final message = error is Map ? error['message'] as String? : null;
      if (message != null && message.trim().isNotEmpty) {
        return 'Gemini error ${response.statusCode}: ${message.trim()}';
      }
    } catch (_) {
      // Response body wasn't the JSON shape we expected — fall through.
    }
    return 'Gemini error ${response.statusCode}';
  }

  void dispose() => _client.close();
}
