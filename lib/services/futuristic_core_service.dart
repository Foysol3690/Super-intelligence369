import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'maya_settings_service.dart';

enum MayaRisk { low, medium, high }

class MayaActionRecord {
  final String tool;
  final String summary;
  final bool success;
  final DateTime time;

  const MayaActionRecord(
      {required this.tool,
      required this.summary,
      required this.success,
      required this.time});

  Map<String, dynamic> toJson() => {
        'tool': tool,
        'summary': summary,
        'success': success,
        'time': time.toIso8601String()
      };
}

/// Privacy-first local intelligence used by every personality.
class FuturisticCoreService {
  static const _storage = FlutterSecureStorage();
  static const _ledgerKey = 'maya_v61_action_ledger';
  final MayaSettingsService settings = MayaSettingsService();

  // Audited October 2026: this used to list ~50 tool names, most of them
  // for an "agent tool registry" that was never built — nothing in the app
  // ever called riskFor() with those strings, so they neither blocked
  // anything under Safe Mode nor asked for confirmation; they just sat
  // here looking like coverage that did not exist. Trimmed to the tool
  // names real code actually passes in (verified by searching the whole
  // app for each string, not assumed), so every entry below does
  // something. A tool not listed here defaults to low risk, same as
  // before — that default is what covers the many ordinary device actions
  // (flashlight, brightness, volume, notify, and the rest) that were never
  // meant to need Safe Mode or confirmation in the first place.
  MayaRisk riskFor(String tool) {
    if (const {
      // The spoken command is itself the authorization for these two; see
      // requiresConfirmation() below.
      'answer_call',
      'reject_call',
      'lock_screen',
      'request_secure_unlock',
      'confirm_whatsapp_message',
      'confirm_whatsapp_call',
      'confirm_cellular_call',
      'confirm_whatsapp_gallery_share',
    }.contains(tool)) return MayaRisk.high;
    if (const {
      'open_app',
      'open_url',
      'click_text',
      'set_ringer_mode',
      'create_calendar_event',
      'cancel_calendar_event',
      'start_omega_vision_capture',
      'stop_omega_vision_capture',
      'time_warp_lookup',
      'ingest_scene_graph',
    }.contains(tool)) return MayaRisk.medium;
    return MayaRisk.low;
  }

  Future<bool> blockedBySafeMode(String tool) async {
    final safeMode = await settings.get<bool>('safeMode', false);
    return safeMode && riskFor(tool) != MayaRisk.low;
  }

  Future<bool> requiresConfirmation(String tool) async {
    // These high-risk tools enforce their own fresh, expiring, explicit-confirmation token.
    if (const {
      // The spoken command itself is explicit authorization for an incoming
      // answer/reject action; it must not trigger a fingerprint prompt.
      'answer_call',
      'reject_call',
      'confirm_whatsapp_message',
      'confirm_whatsapp_call',
      'confirm_cellular_call',
      'confirm_whatsapp_gallery_share',
    }.contains(tool)) return false;
    final enabled = await settings.get<bool>('confirmSensitiveActions', true);
    final privacyShield = await settings.get<bool>('privacyShield', true);
    return riskFor(tool) == MayaRisk.high && (enabled || privacyShield);
  }

  Future<void> record(String tool, Map<String, dynamic> result) async {
    if (!await settings.get<bool>('actionLedger', true)) return;
    final current = await recentRaw();
    current.insert(
        0,
        MayaActionRecord(
          tool: tool,
          summary:
              (result['error'] ?? result['message'] ?? 'Completed').toString(),
          success: result['success'] == true,
          time: DateTime.now().toUtc(),
        ).toJson());
    if (current.length > 500) current.removeRange(500, current.length);
    await _storage.write(key: _ledgerKey, value: jsonEncode(current));
  }

  Future<List<Map<String, dynamic>>> recentRaw() async {
    final raw = await _storage.read(key: _ledgerKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> clearLedger() => _storage.delete(key: _ledgerKey);

  Future<String> contextCapsule() async {
    final mode = await settings.get<String>('focusMode', 'adaptive');
    final privacy = await settings.get<bool>('privacyShield', true);
    return 'Maya runtime: focus=$mode; privacyShield=$privacy; local time=${DateTime.now().toIso8601String()}. '
        'Never invent device state, current news, prices, sent messages, completed actions, or sources.';
  }
}
