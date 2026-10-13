import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../secure_config_manager.dart';

class MayaVisionResult {
  final String text;
  final String provider;

  const MayaVisionResult({required this.text, required this.provider});
}

/// Privacy-conscious still-frame vision with provider fallback.
/// Frames exist only for the active visible camera session and are never
/// written to Maya's long-term memory by this service.
class MayaVisionService {
  final SecureConfigManager _config = SecureConfigManager();

  static const String visionSystemPrompt =
      'You are MAYA OMEGA visual intelligence. Analyze only the supplied camera frame. '
      'State visible facts and clearly label uncertainty. Use the available 1080p detail for spatial description, OCR, documents, code, electronics, object inspection, visible damage, repair guidance, lighting, composition, and practical next-step assistance. '
      'Do not identify a person, guess age, ethnicity, religion, sexuality, disability, or other sensitive traits. '
      'Do not diagnose health, claim emotion as fact, or act as a lie detector. You may say someone appears tired or happy only as an uncertain visual cue. '
      'Do not repeat passwords, OTPs, card numbers, private messages, or authentication data visible in the image. Warn that sensitive content is visible instead. '
      'Be concise, useful, natural, and address the user as Foysol. Never claim you can see beyond this single frame.';

  Future<MayaVisionResult> analyze(
    Uint8List jpegBytes, {
    String question = 'What can you see, and what useful help can you offer?',
  }) async {
    if (jpegBytes.isEmpty)
      throw StateError('The camera returned an empty image.');
    if (jpegBytes.length > 6 * 1024 * 1024) {
      throw StateError(
          'Camera frame is too large. Lower the camera resolution and retry.');
    }
    final encoded = base64Encode(jpegBytes);
    final failures = <String>[];

    final gemini = (await _config.getGeminiKey())?.trim();
    if (gemini != null && gemini.isNotEmpty) {
      final result = await _gemini(encoded, question, gemini, failures);
      if (result != null)
        return MayaVisionResult(text: result, provider: 'Gemini Vision');
    }

    final openAI = (await _config.getOpenAIKey())?.trim();
    if (openAI != null && openAI.isNotEmpty) {
      final result = await _openAI(encoded, question, openAI, failures);
      if (result != null)
        return MayaVisionResult(text: result, provider: 'OpenAI Vision');
    }

    final claude = (await _config.getClaudeKey())?.trim();
    if (claude != null && claude.isNotEmpty) {
      final result = await _claude(encoded, question, claude, failures);
      if (result != null)
        return MayaVisionResult(text: result, provider: 'Claude Vision');
    }

    final openRouter = (await _config.getOpenRouterKey())?.trim();
    if (openRouter != null && openRouter.isNotEmpty) {
      final result = await _openRouter(encoded, question, openRouter, failures);
      if (result != null)
        return MayaVisionResult(text: result, provider: 'OpenRouter Vision');
    }

    if (failures.isEmpty) {
      throw StateError(
          'Add a Gemini, OpenAI, Claude, or OpenRouter key in GOD-MODE Providers for camera vision.');
    }
    throw StateError('Vision providers failed: ${failures.join(' • ')}');
  }

  Future<String?> _gemini(
    String image,
    String question,
    String key,
    List<String> failures,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=' +
                    Uri.encodeQueryComponent(key)),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': '$visionSystemPrompt\n\nFoysol asks: $question'},
                    {
                      'inlineData': {'mimeType': 'image/jpeg', 'data': image}
                    },
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.22,
                'maxOutputTokens': 1000
              },
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final parts = data['candidates']?[0]?['content']?['parts'];
        if (parts is List) {
          return parts
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .join('\n')
              .trim();
        }
      }
      failures.add('Gemini ${response.statusCode}');
    } catch (error) {
      failures.add('Gemini ${_short(error)}');
    }
    return null;
  }

  Future<String?> _openAI(
    String image,
    String question,
    String key,
    List<String> failures,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.openai.com/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'model': 'gpt-4o-mini',
              'max_tokens': 1000,
              'messages': [
                {'role': 'system', 'content': visionSystemPrompt},
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': question},
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/jpeg;base64,$image',
                        'detail': 'high'
                      }
                    }
                  ]
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content']?.toString().trim();
      }
      failures.add('OpenAI ${response.statusCode}');
    } catch (error) {
      failures.add('OpenAI ${_short(error)}');
    }
    return null;
  }

  Future<String?> _claude(
    String image,
    String question,
    String key,
    List<String> failures,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'claude-sonnet-4-5',
              'max_tokens': 1000,
              'system': visionSystemPrompt,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': 'image/jpeg',
                        'data': image
                      }
                    },
                    {'type': 'text', 'text': question}
                  ]
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content'];
        if (content is List) {
          return content
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .join('\n')
              .trim();
        }
      }
      failures.add('Claude ${response.statusCode}');
    } catch (error) {
      failures.add('Claude ${_short(error)}');
    }
    return null;
  }

  Future<String?> _openRouter(
    String image,
    String question,
    String key,
    List<String> failures,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'model': 'google/gemini-2.5-flash',
              'max_tokens': 1000,
              'messages': [
                {'role': 'system', 'content': visionSystemPrompt},
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': question},
                    {
                      'type': 'image_url',
                      'image_url': {'url': 'data:image/jpeg;base64,$image'}
                    }
                  ]
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content']?.toString().trim();
      }
      failures.add('OpenRouter ${response.statusCode}');
    } catch (error) {
      failures.add('OpenRouter ${_short(error)}');
    }
    return null;
  }

  static String _short(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }
}
