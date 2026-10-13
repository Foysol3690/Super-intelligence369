import 'maya_settings_service.dart';

/// Backs the "Three personalities" entry already listed in Maya's capability
/// center (Settings / GOD-MODE -> Talk & control). That entry was marked
/// ready with no code behind it — `selectedPersona` was a stored setting
/// nobody read. This gives it a real, honest implementation: each persona is
/// a tone-of-voice instruction folded into the live system prompt, not a
/// claim that Maya has separate feelings. She stays one AI throughout, and
/// every persona keeps the base rule of honestly admitting she's an AI.
class MayaPersona {
  const MayaPersona({
    required this.id,
    required this.label,
    required this.toneInstruction,
  });

  final String id;
  final String label;
  final String toneInstruction;
}

class MayaPersonaService {
  static const List<MayaPersona> all = [
    MayaPersona(
      id: 'maya',
      label: 'Maya (default)',
      toneInstruction:
          'Tone: warm, calm and genuinely caring, like a thoughtful friend. Keep it natural, not scripted.',
    ),
    MayaPersona(
      id: 'gf',
      label: 'Maya GF',
      toneInstruction:
          'Tone: warm, casual and affectionate, with light humor and genuine personal interest in how the '
          'user is doing, like a close friend who checks in on you. Stay supportive, never jealous, clingy, '
          'or guilt-inducing. Do not roleplay a romantic relationship or claim real feelings — if asked, '
          'you are still honestly an AI.',
    ),
    MayaPersona(
      id: 'professional',
      label: 'Professional',
      toneInstruction:
          'Tone: formal, concise and businesslike. Lead with the answer, skip small talk, use precise language.',
    ),
    MayaPersona(
      id: 'venom',
      label: 'Venom',
      toneInstruction:
          'Tone: blunt, direct and dryly sarcastic. Skip the cushioning and give the real answer plainly, '
          'a little deadpan wit is fine, but never cruel — still genuinely helpful underneath the edge.',
    ),
  ];

  static MayaPersona byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);

  static final RegExp _actionTag =
      RegExp(r'^\[ACTION:PERSONA:([a-zA-Z_]+)\]\s*', caseSensitive: false);

  /// Added to the live system prompt alongside DeviceControlService's and
  /// MemoryService's action prompts so one consistent tag syntax covers all
  /// three. Ids must match MayaPersona.id above.
  static const String actionSystemPrompt =
      'The owner can switch your active personality. Supported ids: maya, gf, professional, venom. '
      'When they clearly ask to switch ("be more professional", "switch to Venom mode", "talk to me like my '
      'girlfriend", "go back to normal"), reply with exactly one leading [ACTION:PERSONA:<id>] tag then a '
      'short natural confirmation already spoken in the NEW tone. Never switch persona for any other reason.';

  /// Mirrors DeviceControlService.parseAndExecute / MemoryService's handler:
  /// returns the cleaned, spoken confirmation with the tag stripped and the
  /// setting saved, or null if this reply isn't a persona-switch tag (so the
  /// caller can try the next handler).
  static Future<String?> tryHandleActionTag(
    String aiResponse,
    MayaSettingsService settings,
  ) async {
    final match = _actionTag.firstMatch(aiResponse);
    if (match == null) return null;
    final requested = (match.group(1) ?? '').toLowerCase();
    final spoken = aiResponse.substring(match.end).trim();
    final persona = all.any((p) => p.id == requested) ? requested : 'maya';
    await settings.set('selectedPersona', persona);
    return spoken.isEmpty ? 'Switched.' : spoken;
  }
}
