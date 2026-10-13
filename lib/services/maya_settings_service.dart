import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted user-controlled settings for Maya's capability center.
class MayaSettingsService {
  static final MayaSettingsService _instance = MayaSettingsService._internal();
  factory MayaSettingsService() => _instance;
  MayaSettingsService._internal();

  static const _storage = FlutterSecureStorage();
  static const _settingsKey = 'maya_v6_settings';

  Map<String, dynamic> _values = <String, dynamic>{};
  bool _loaded = false;

  static const Map<String, dynamic> defaults = {
    'language': 'auto',
    'ownerMode': true,
    'safeMode': false,
    'wakeWord': 'Hey Maya AI',
    'wakeWordEnabled': true,
    'sleepPhrase': 'Bye Maya AI',
    'memoryEnabled': true,
    'bargeInEnabled': true,
    'extendedThinkingVoice': false,
    'privacyShield': true,
    'actionLedger': true,
    'adaptiveConnection': true,
    'focusMode': 'adaptive',
    'voiceGuardianEnabled': false,
    'autoReplyEnabled': false,
    'readNotifications': false,
    'confirmSensitiveActions': true,
    'backgroundTasks': true,
    'newsRegion': 'BD',
    'researchCitations': true,
    'liveGameCommentary': false,
    'selectedPersona': 'maya',
    'systemOrbEnabled': true,
  };

  Future<void> load() async {
    if (_loaded) return;
    _values = Map<String, dynamic>.from(defaults);
    String? raw;
    try {
      raw = await _storage
          .read(key: _settingsKey)
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      raw = null;
    }
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _values.addAll(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<T> get<T>(String key, T fallback) async {
    await load();
    final value = _values[key];
    return value is T ? value : fallback;
  }

  Future<void> set(String key, dynamic value) async {
    await load();
    _values[key] = value;
    await _storage.write(key: _settingsKey, value: jsonEncode(_values));
  }

  Future<Map<String, dynamic>> snapshot() async {
    await load();
    return Map<String, dynamic>.unmodifiable(_values);
  }

  Future<void> reset() async {
    _values = Map<String, dynamic>.from(defaults);
    _loaded = true;
    await _storage.write(key: _settingsKey, value: jsonEncode(_values));
  }
}
