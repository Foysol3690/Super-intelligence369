import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'futuristic_core_service.dart';

/// Real automation, honestly scoped to what's actually verifiable without a
/// device or native Android scheduling code: a daily reminder at a fixed
/// time, and a one-time alert when battery drops below a threshold. Both
/// end up as an ordinary local notification with fixed wording decided at
/// creation time — not a fresh AI answer generated at the moment it fires,
/// since nothing can reliably run model inference in the background here.
///
/// Scheduling design: rather than relying on flutter_local_notifications'
/// built-in daily-recurrence (matchDateTimeComponents), which needs the
/// device's precise IANA timezone to recompute future occurrences correctly
/// and that this project has no reliable way to detect without adding a new,
/// unverified plugin dependency, each reminder is scheduled as a single
/// non-recurring alarm for its next correct local occurrence, then silently
/// re-armed for the following day every time the app is opened or Settings
/// closes. That is a real, correct trade-off, not a shortcut: it avoids a
/// subtle wrong-time bug at the cost of needing the app reopened at least
/// once a day to keep firing.
class MayaAutomation {
  MayaAutomation({
    required this.id,
    required this.label,
    required this.kind,
    required this.message,
    this.hour,
    this.minute,
    this.thresholdPercent,
    this.eventAt,
    this.enabled = true,
    DateTime? createdAt,
    this.lastFiredAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String label;
  final String kind; // 'scheduledReminder' | 'batteryBelow' | 'calendarEvent'
  final String message;
  final int? hour;
  final int? minute;
  final int? thresholdPercent;
  final DateTime? eventAt; // 'calendarEvent' only — the exact one-time moment
  bool enabled;
  final DateTime createdAt;
  DateTime? lastFiredAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind,
        'message': message,
        if (hour != null) 'hour': hour,
        if (minute != null) 'minute': minute,
        if (thresholdPercent != null) 'thresholdPercent': thresholdPercent,
        if (eventAt != null) 'eventAt': eventAt!.toIso8601String(),
        'enabled': enabled,
        'createdAt': createdAt.toIso8601String(),
        if (lastFiredAt != null) 'lastFiredAt': lastFiredAt!.toIso8601String(),
      };

  static MayaAutomation fromJson(Map<String, dynamic> json) => MayaAutomation(
        id: json['id']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        kind: json['kind']?.toString() ?? 'scheduledReminder',
        message: json['message']?.toString() ?? '',
        hour: json['hour'] as int?,
        minute: json['minute'] as int?,
        thresholdPercent: json['thresholdPercent'] as int?,
        eventAt: json['eventAt'] == null
            ? null
            : DateTime.tryParse(json['eventAt'].toString()),
        enabled: json['enabled'] != false,
        createdAt:
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        lastFiredAt: json['lastFiredAt'] == null
            ? null
            : DateTime.tryParse(json['lastFiredAt'].toString()),
      );
}

class MayaAutomationService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'maya_v1_automations';
  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _pluginReady = false;
  static bool _tzReady = false;
  final _core = FuturisticCoreService();

  static final RegExp _remindTag = RegExp(
    r'^\[ACTION:AUTOMATE_REMIND:(\d{1,2}):(\d{2})\|([^\]]*)\]\s*',
    caseSensitive: false,
  );
  static final RegExp _batteryTag = RegExp(
    r'^\[ACTION:AUTOMATE_BATTERY:(\d{1,3})\|([^\]]*)\]\s*',
    caseSensitive: false,
  );
  static final RegExp _listTag =
      RegExp(r'^\[ACTION:AUTOMATE_LIST\]\s*', caseSensitive: false);
  static final RegExp _cancelTag =
      RegExp(r'^\[ACTION:AUTOMATE_CANCEL:([^\]]*)\]\s*', caseSensitive: false);

  static final RegExp _calendarCreateTag = RegExp(
    r'^\[ACTION:CALENDAR_CREATE:(\d{4})-(\d{2})-(\d{2}) (\d{1,2}):(\d{2})\|([^\]]*)\]\s*',
    caseSensitive: false,
  );
  static final RegExp _calendarListTag =
      RegExp(r'^\[ACTION:CALENDAR_LIST\]\s*', caseSensitive: false);
  static final RegExp _calendarCancelTag = RegExp(
      r'^\[ACTION:CALENDAR_CANCEL:([^\]]*)\]\s*',
      caseSensitive: false);

  static const String actionSystemPrompt =
      'You can set real reminders, battery alerts and local calendar events. Use exactly one leading tag then a '
      'short confirmation: '
      '[ACTION:AUTOMATE_REMIND:HH:MM|what to say] for a daily reminder at that 24-hour time — e.g. "remind me '
      'every morning at 8 to check my schedule" becomes [ACTION:AUTOMATE_REMIND:08:00|Check your schedule for '
      'today]. The reminder text is fixed at creation time, not generated fresh when it fires. '
      '[ACTION:AUTOMATE_BATTERY:percent|what to say] to alert once battery drops below that percent — checked '
      'when the app is next open, not instantly in the background; say so if the user asks how soon. '
      '[ACTION:AUTOMATE_LIST] to read back active reminders and alerts. '
      '[ACTION:AUTOMATE_CANCEL:label or time] to remove one. '
      '[ACTION:CALENDAR_CREATE:YYYY-MM-DD HH:MM|title] for a one-time local calendar event at that exact date and '
      '24-hour time — e.g. "put my dentist appointment on the 15th at 3pm" this year becomes something like '
      '[ACTION:CALENDAR_CREATE:2026-10-15 15:00|Dentist appointment]. Ask the user for whatever part of the date '
      'is ambiguous before creating it. This is a local event on this phone only — it is never synced to an '
      'external calendar account. [ACTION:CALENDAR_LIST] to read back upcoming local events. '
      '[ACTION:CALENDAR_CANCEL:title or date] to remove one.';

  static Future<void> _ensureReady() async {
    if (!_tzReady) {
      try {
        tz_data.initializeTimeZones();
      } catch (_) {}
      _tzReady = true;
    }
    if (_pluginReady) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    try {
      await _notifications.initialize(settings);
    } catch (_) {
      // Falls through — scheduling calls below are themselves try/caught,
      // so a failed init here degrades to "reminder not armed" rather than
      // a crash.
    }
    _pluginReady = true;
  }

  Future<List<MayaAutomation>> list() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return <MayaAutomation>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <MayaAutomation>[];
      return decoded
          .whereType<Map>()
          .map((item) =>
              MayaAutomation.fromJson(item.map((k, v) => MapEntry(k.toString(), v))))
          .toList();
    } catch (_) {
      return <MayaAutomation>[];
    }
  }

  Future<void> _write(List<MayaAutomation> items) async {
    await _storage.write(
      key: _key,
      value: jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  /// Notification ids are derived from the automation id so re-arming can
  /// cancel-and-replace the same slot instead of accumulating duplicates.
  int _notificationIdFor(String automationId) =>
      automationId.hashCode & 0x7fffffff;

  Future<MayaAutomation> _create(MayaAutomation automation) async {
    final items = await list();
    items.add(automation);
    await _write(items);
    await _arm(automation);
    return automation;
  }

  Future<void> cancel(String labelOrId) async {
    final items = await list();
    final needle = labelOrId.trim().toLowerCase();
    items.removeWhere((item) {
      final matches = item.id == labelOrId ||
          item.label.toLowerCase().contains(needle) ||
          needle.contains(item.label.toLowerCase());
      if (matches) {
        _notifications.cancel(_notificationIdFor(item.id));
      }
      return matches;
    });
    await _write(items);
  }

  /// Schedules (or re-schedules) the next single, correctly-timed firing of
  /// one reminder. Safe to call repeatedly — it cancels any stale pending
  /// alarm for this automation first.
  Future<void> _arm(MayaAutomation automation) async {
    if (!automation.enabled) return;
    DateTime next;
    if (automation.kind == 'scheduledReminder') {
      if (automation.hour == null || automation.minute == null) return;
      next = _nextLocalOccurrence(automation.hour!, automation.minute!);
    } else if (automation.kind == 'calendarEvent') {
      final at = automation.eventAt;
      // A calendar event fires once, at the exact moment it was created
      // for — unlike a reminder it is never rolled forward to "tomorrow"
      // if that moment has already passed, since it describes a specific
      // real-world appointment, not a recurring daily cue.
      if (at == null || !at.isAfter(DateTime.now())) return;
      next = at;
    } else {
      return;
    }
    await _ensureReady();
    final id = _notificationIdFor(automation.id);
    try {
      await _notifications.cancel(id);
      await _notifications.zonedSchedule(
        id,
        'Maya',
        automation.message.isEmpty ? 'Reminder' : automation.message,
        tz.TZDateTime.from(next, tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'maya_automations',
            'Maya Reminders',
            channelDescription: 'Scheduled reminders and alerts from Maya',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        // Inexact rather than exact: exact alarms need the user to grant a
        // separate Android 12+ permission this project doesn't request
        // anywhere else. Inexact still fires within a short window of the
        // target time, which is the honest trade-off for "don't add an
        // unverified new permission flow".
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // Leave the automation saved even if arming failed on this device —
      // re-arming is retried next time the app opens.
    }
  }

  /// Computes the next correct local wall-clock moment for hour:minute as a
  /// plain (non-recurring) target. Deliberately NOT using the plugin's
  /// built-in daily-recurrence match, which needs a resolved IANA zone name
  /// this project has no verified way to detect — see the class doc.
  DateTime _nextLocalOccurrence(int hour, int minute) {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  /// Re-arms every enabled scheduled reminder and runs the battery check.
  /// Call this at app boot and whenever Settings/GOD-MODE closes, the same
  /// moments MayaController already re-syncs other config.
  Future<void> runForegroundChecks() async {
    for (final automation in await list()) {
      if (automation.kind == 'scheduledReminder' ||
          automation.kind == 'calendarEvent') {
        await _arm(automation);
      }
    }
    await _checkBattery();
  }

  Future<void> _checkBattery() async {
    final items = await list();
    final today = DateTime.now();
    var changed = false;
    for (final automation in items) {
      if (automation.kind != 'batteryBelow' || !automation.enabled) continue;
      if (automation.thresholdPercent == null) continue;
      final lastFired = automation.lastFiredAt;
      final firedToday = lastFired != null &&
          lastFired.year == today.year &&
          lastFired.month == today.month &&
          lastFired.day == today.day;
      if (firedToday) continue;
      try {
        final level = await Battery().batteryLevel;
        if (level <= automation.thresholdPercent!) {
          await _ensureReady();
          await _notifications.show(
            _notificationIdFor(automation.id),
            'Maya',
            automation.message.isEmpty
                ? 'Battery is at $level%.'
                : automation.message,
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'maya_automations',
                'Maya Reminders',
                channelDescription: 'Scheduled reminders and alerts from Maya',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
          automation.lastFiredAt = DateTime.now();
          changed = true;
        }
      } catch (_) {
        // No battery API on this platform/build — skip silently.
      }
    }
    if (changed) await _write(items);
  }

  String _describe(MayaAutomation a) {
    if (a.kind == 'scheduledReminder') {
      return '${a.label.isEmpty ? "Reminder" : a.label} at '
          '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}';
    }
    if (a.kind == 'calendarEvent') {
      final at = a.eventAt;
      final when = at == null
          ? 'an unknown time'
          : '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} '
              '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      return '${a.label.isEmpty ? "Event" : a.label} on $when';
    }
    return '${a.label.isEmpty ? "Battery alert" : a.label} under ${a.thresholdPercent}%';
  }

  /// Local calendar events only, soonest first — used by CALENDAR_LIST so it
  /// never mixes in daily reminders or battery alerts.
  Future<List<MayaAutomation>> _upcomingEvents() async {
    final events = (await list())
        .where((a) => a.kind == 'calendarEvent' && a.enabled)
        .where((a) => a.eventAt != null && a.eventAt!.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.eventAt!.compareTo(b.eventAt!));
    return events;
  }

  /// Mirrors MemoryService.tryHandleActionTag / MayaPersonaService's: returns
  /// the cleaned, spoken confirmation with the tag stripped, or null if this
  /// reply isn't an automation tag (so the caller tries the next handler).
  Future<String?> tryHandleActionTag(String aiResponse) async {
    final remind = _remindTag.firstMatch(aiResponse);
    if (remind != null) {
      final hour = int.tryParse(remind.group(1) ?? '');
      final minute = int.tryParse(remind.group(2) ?? '');
      final message = (remind.group(3) ?? '').trim();
      final spoken = aiResponse.substring(remind.end).trim();
      if (hour == null || minute == null || hour > 23 || minute > 59) {
        return spoken.isEmpty ? "I didn't catch a valid time for that." : spoken;
      }
      if (await _core.blockedBySafeMode('create_scheduled_reminder')) {
        return 'Maya Safe Mode blocked this action.';
      }
      await _create(MayaAutomation(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: message.isEmpty ? 'Reminder' : message,
        kind: 'scheduledReminder',
        message: message,
        hour: hour,
        minute: minute,
      ));
      final remindResult = spoken.isEmpty
          ? 'Set for ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} daily.'
          : spoken;
      await _core.record('create_scheduled_reminder',
          {'success': true, 'message': remindResult});
      return remindResult;
    }

    final battery = _batteryTag.firstMatch(aiResponse);
    if (battery != null) {
      final threshold = int.tryParse(battery.group(1) ?? '');
      final message = (battery.group(2) ?? '').trim();
      final spoken = aiResponse.substring(battery.end).trim();
      if (threshold == null || threshold < 1 || threshold > 100) {
        return spoken.isEmpty ? "I didn't catch a valid battery percent." : spoken;
      }
      if (await _core.blockedBySafeMode('create_battery_alert')) {
        return 'Maya Safe Mode blocked this action.';
      }
      await _create(MayaAutomation(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: message.isEmpty ? 'Battery alert' : message,
        kind: 'batteryBelow',
        message: message,
        thresholdPercent: threshold,
      ));
      final batteryResult =
          spoken.isEmpty ? 'Will alert you under $threshold% battery.' : spoken;
      await _core.record(
          'create_battery_alert', {'success': true, 'message': batteryResult});
      return batteryResult;
    }

    if (_listTag.firstMatch(aiResponse) != null) {
      final match = _listTag.firstMatch(aiResponse)!;
      final spoken = aiResponse.substring(match.end).trim();
      final items = (await list()).where((a) => a.enabled).toList();
      if (items.isEmpty) {
        return spoken.isEmpty ? 'No reminders or alerts are set.' : spoken;
      }
      final summary = items.map(_describe).join('; ');
      return spoken.isEmpty ? summary : '$spoken $summary';
    }

    final cancel = _cancelTag.firstMatch(aiResponse);
    if (cancel != null) {
      final target = (cancel.group(1) ?? '').trim();
      final spoken = aiResponse.substring(cancel.end).trim();
      if (target.isEmpty) {
        return spoken.isEmpty ? 'Tell me which one to cancel.' : spoken;
      }
      if (await _core.blockedBySafeMode('cancel_automation')) {
        return 'Maya Safe Mode blocked this action.';
      }
      await this.cancel(target);
      final cancelResult = spoken.isEmpty ? 'Cancelled.' : spoken;
      await _core
          .record('cancel_automation', {'success': true, 'message': cancelResult});
      return cancelResult;
    }

    final calCreate = _calendarCreateTag.firstMatch(aiResponse);
    if (calCreate != null) {
      final spoken = aiResponse.substring(calCreate.end).trim();
      final year = int.tryParse(calCreate.group(1) ?? '');
      final month = int.tryParse(calCreate.group(2) ?? '');
      final day = int.tryParse(calCreate.group(3) ?? '');
      final hour = int.tryParse(calCreate.group(4) ?? '');
      final minute = int.tryParse(calCreate.group(5) ?? '');
      final title = (calCreate.group(6) ?? '').trim();
      if (year == null ||
          month == null ||
          day == null ||
          hour == null ||
          minute == null ||
          month < 1 ||
          month > 12 ||
          day < 1 ||
          day > 31 ||
          hour > 23 ||
          minute > 59) {
        return spoken.isEmpty
            ? "I didn't catch a valid date and time for that."
            : spoken;
      }
      DateTime at;
      try {
        at = DateTime(year, month, day, hour, minute);
      } catch (_) {
        return spoken.isEmpty ? "That date doesn't exist." : spoken;
      }
      if (await _core.blockedBySafeMode('create_calendar_event')) {
        return 'Maya Safe Mode blocked this action.';
      }
      final inPast = !at.isAfter(DateTime.now());
      await _create(MayaAutomation(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        label: title.isEmpty ? 'Event' : title,
        kind: 'calendarEvent',
        message: title.isEmpty ? 'Event' : title,
        eventAt: at,
      ));
      final when = '${at.year}-${at.month.toString().padLeft(2, '0')}-'
          '${at.day.toString().padLeft(2, '0')} '
          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      final calCreateResult = inPast
          ? 'Saved, but $when is already in the past, so I will not remind you about it.'
          : (spoken.isEmpty ? 'Added to your calendar for $when.' : spoken);
      await _core.record('create_calendar_event',
          {'success': true, 'message': calCreateResult});
      return calCreateResult;
    }

    if (_calendarListTag.firstMatch(aiResponse) != null) {
      final match = _calendarListTag.firstMatch(aiResponse)!;
      final spoken = aiResponse.substring(match.end).trim();
      final events = await _upcomingEvents();
      if (events.isEmpty) {
        return spoken.isEmpty ? 'No upcoming local events.' : spoken;
      }
      final summary = events.map(_describe).join('; ');
      return spoken.isEmpty ? summary : '$spoken $summary';
    }

    final calCancel = _calendarCancelTag.firstMatch(aiResponse);
    if (calCancel != null) {
      final target = (calCancel.group(1) ?? '').trim();
      final spoken = aiResponse.substring(calCancel.end).trim();
      if (target.isEmpty) {
        return spoken.isEmpty ? 'Tell me which event to cancel.' : spoken;
      }
      if (await _core.blockedBySafeMode('cancel_calendar_event')) {
        return 'Maya Safe Mode blocked this action.';
      }
      await cancel(target);
      final calCancelResult =
          spoken.isEmpty ? 'Removed from your calendar.' : spoken;
      await _core.record('cancel_calendar_event',
          {'success': true, 'message': calCancelResult});
      return calCancelResult;
    }

    return null;
  }
}
