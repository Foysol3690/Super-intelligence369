import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'memory_database.dart';
import 'omega_vector_memory_service.dart';

class MayaMemory {
  final String id;
  final String text;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String source;
  final double importance;
  final List<String> tags;
  final DateTime? expiresAt;

  const MayaMemory({
    required this.id,
    required this.text,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.importance,
    required this.tags,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'source': source,
        'importance': importance,
        'tags': tags,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };

  static MayaMemory fromJson(Map<String, dynamic> json) => MayaMemory(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        category: json['category']?.toString() ?? 'general',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
            DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        source: json['source']?.toString() ?? 'owner',
        importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
        tags: (json['tags'] is List)
            ? (json['tags'] as List).map((tag) => tag.toString()).toList()
            : const <String>[],
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      );
}

/// Small encrypted long-term memory store. The user can inspect and erase it.
class MemoryService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'maya_v6_memories';
  final MayaMemoryDatabase _database = MayaMemoryDatabase.instance;
  final MayaOmegaVectorMemoryService _vectors =
      MayaOmegaVectorMemoryService.instance;

  static final RegExp _actionTag =
      RegExp(r'^\[ACTION:(REMEMBER|FORGET)(?::([^\]]*))?\]\s*', caseSensitive: false);

  /// Added to the live system prompt (alongside DeviceControlService's)
  /// so the same one-leading-tag protocol also covers memory, instead of
  /// inventing a second mechanism for the model to follow.
  static const String actionSystemPrompt =
      'You can keep a small private memory of approved facts about the owner across conversations. '
      'When the owner clearly asks you to remember something ("remember that...", "don\'t forget..."), reply '
      'with exactly one leading [ACTION:REMEMBER:<the fact, written plainly>] tag then a short natural '
      'confirmation. When they ask you to forget something, use [ACTION:FORGET:<the fact or topic to drop>] '
      'then confirm. Never store passwords, card or account numbers, or government IDs even if asked — '
      'decline that politely instead. Only store what the owner explicitly tells you to keep.';

  /// Mirrors DeviceControlService.parseAndExecute: returns the cleaned,
  /// spoken confirmation with the tag stripped and the memory applied, or
  /// null if this reply isn't a memory tag (so the caller can try the next
  /// handler, e.g. a device action, instead).
  Future<String?> tryHandleActionTag(String aiResponse) async {
    final match = _actionTag.firstMatch(aiResponse);
    if (match == null) return null;
    final action = match.group(1)?.toUpperCase() ?? '';
    final arg = (match.group(2) ?? '').trim();
    final spoken = aiResponse.substring(match.end).trim();
    switch (action) {
      case 'REMEMBER':
        if (arg.isEmpty) return spoken.isEmpty ? 'There is nothing to remember yet.' : spoken;
        await remember(arg, source: 'owner');
        return spoken.isEmpty ? "Got it, I'll remember that." : spoken;
      case 'FORGET':
        if (arg.isEmpty) return spoken.isEmpty ? 'Tell me what to forget.' : spoken;
        final matches = await search(arg, limit: 5);
        for (final item in matches) {
          final haystack = item.text.toLowerCase();
          final needle = arg.toLowerCase();
          if (haystack.contains(needle) || needle.contains(haystack)) {
            await forget(item.id);
          }
        }
        return spoken.isEmpty ? "Done, I've forgotten that." : spoken;
      default:
        return null;
    }
  }

  Future<List<MayaMemory>> list() async {
    try {
      final rows = await _database.list();
      if (rows.isNotEmpty) {
        return rows.map(_fromDatabaseRow).toList();
      }
    } catch (_) {
      // Fall back to the pre-SQLite store if the platform database is
      // temporarily unavailable.
    }

    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return <MayaMemory>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <MayaMemory>[];
      final migrated = decoded
          .whereType<Map>()
          .map((item) => MayaMemory.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .toList();
      if (migrated.isNotEmpty) {
        try {
          await _database.replaceAll(
            migrated.map((item) => item.toJson()).toList(),
          );
          for (final item in migrated) {
            await _vectors.index(
              id: item.id,
              text: item.text,
              category: item.category,
            );
          }
        } catch (_) {}
      }
      return migrated;
    } catch (_) {
      return <MayaMemory>[];
    }
  }

  Future<void> remember(
    String text, {
    String category = 'general',
    String source = 'owner',
    double importance = 0.5,
    List<String> tags = const <String>[],
    Duration? ttl,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final items = await list();
    items.removeWhere((item) => item.text.toLowerCase() == clean.toLowerCase());
    final now = DateTime.now();
    items.insert(
      0,
      MayaMemory(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: clean,
        category: category,
        createdAt: now,
        updatedAt: now,
        source: source,
        importance: importance.clamp(0, 1).toDouble(),
        tags: tags
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList(),
        expiresAt: ttl == null ? null : now.add(ttl),
      ),
    );
    if (items.length > 200) items.removeRange(200, items.length);
    await _write(items);
    try {
      await _vectors.index(
        id: items.first.id,
        text: items.first.text,
        category: items.first.category,
      );
    } catch (_) {}
  }

  /// Small local retrieval layer for working, preference, project, and
  /// procedure memory without pretending that a vector index exists.
  Future<List<MayaMemory>> search(
    String query, {
    String? category,
    int limit = 20,
  }) async {
    final cleanQuery = query.trim().toLowerCase();
    final now = DateTime.now();
    final tokens = cleanQuery
        .split(RegExp(r'\s+'))
        .where((token) => token.length > 1)
        .toSet();
    final scored = <MapEntry<MayaMemory, int>>[];
    for (final item in await list()) {
      if (item.expiresAt != null && item.expiresAt!.isBefore(now)) continue;
      if (category != null && item.category != category) continue;
      final haystack =
          '${item.text} ${item.category} ${item.tags.join(' ')}'.toLowerCase();
      var score = 0;
      if (cleanQuery.isNotEmpty && haystack.contains(cleanQuery)) score += 4;
      score += tokens.where((token) => haystack.contains(token)).length;
      if (cleanQuery.isEmpty || score > 0) {
        score += (item.importance * 2).round();
        scored.add(MapEntry(item, score));
      }
    }
    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      return byScore != 0
          ? byScore
          : b.key.updatedAt.compareTo(a.key.updatedAt);
    });
    return scored
        .take(limit.clamp(1, 100).toInt())
        .map((entry) => entry.key)
        .toList();
  }

  Future<List<Map<String, dynamic>>> semanticSearch(
    String query, {
    String? category,
    int limit = 20,
  }) =>
      _vectors.search(query, category: category, limit: limit);

  /// Builds the memory block injected into the system prompt. [query] should
  /// be the user's current utterance: without it, this had been injecting
  /// the same top-N memories by importance/recency into every single turn
  /// regardless of what was actually being discussed — exactly what the
  /// spec this app follows warns against ("avoid injecting irrelevant
  /// memories into every prompt"). With a query, it instead retrieves what's
  /// actually relevant: keyword search (exact/substring term matches)
  /// blended with the local vector index (catches paraphrases keyword
  /// search misses — see MayaOmegaVectorMemoryService's own doc comment on
  /// what kind of "semantic" it actually is, and is not). That vector index
  /// was already being populated by every `remember()` call but, until
  /// this, had no caller reading it back — a real hybrid retrieval path
  /// now actually runs, instead of existing only as unused code.
  Future<String> promptContext({String query = '', int limit = 20}) async {
    final clean = query.trim();
    // No current utterance to anchor on (e.g. the very first turn) — fall
    // back to the most important/recent memories rather than nothing.
    if (clean.isEmpty) {
      final items = await search('', limit: limit);
      if (items.isEmpty) return '';
      return 'Private user-approved memories:\n${items.map((item) => '- ${item.text}').join('\n')}';
    }

    final keyword = await search(clean, limit: limit);
    final texts = <String>[];
    final seenIds = <String>{};
    for (final item in keyword) {
      if (seenIds.add(item.id)) texts.add(item.text);
    }
    try {
      final semantic = await semanticSearch(clean, limit: limit);
      for (final row in semantic) {
        // A weak cosine match against a hashed bag-of-words vector is noise,
        // not a relevant memory — only take matches it's actually confident
        // about. (Tunable; not calibrated against real usage data.)
        final similarity = (row['similarity'] as num?)?.toDouble() ?? 0;
        if (similarity < 0.22) continue;
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty || !seenIds.add(id)) continue;
        final text = row['text']?.toString() ?? '';
        if (text.isNotEmpty) texts.add(text);
      }
    } catch (_) {
      // Vector index unavailable (e.g. platform database briefly down) —
      // the keyword results above are still a valid, if narrower, answer.
    }

    if (texts.isEmpty) return '';
    final capped = texts.take(limit.clamp(1, 100).toInt()).toList();
    return 'Private user-approved memories:\n${capped.map((text) => '- $text').join('\n')}';
  }

  Future<int> consolidate() async {
    final now = DateTime.now();
    final items = await list();
    final seen = <String>{};
    final retained = <MayaMemory>[];
    for (final item in items) {
      if (item.expiresAt != null && item.expiresAt!.isBefore(now)) continue;
      final key = '${item.category}:${item.text.trim().toLowerCase()}';
      if (seen.add(key)) retained.add(item);
    }
    await _write(retained.take(200).toList());
    return items.length - retained.length;
  }

  Future<void> forget(String id) async {
    final items = await list();
    items.removeWhere((item) => item.id == id);
    await _write(items);
    try {
      await _vectors.delete(id);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _database.clear();
    } catch (_) {}
    try {
      await _vectors.clear();
    } catch (_) {}
    await _storage.delete(key: _key);
  }

  Future<void> _write(List<MayaMemory> items) async {
    final rows = items.map((item) => item.toJson()).toList();
    try {
      await _database.replaceAll(rows);
    } catch (_) {
      await _storage.write(key: _key, value: jsonEncode(rows));
    }
  }

  static MayaMemory _fromDatabaseRow(Map<String, dynamic> row) {
    List<dynamic> tags = const <dynamic>[];
    final rawTags = row['tags_json']?.toString();
    if (rawTags != null && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) tags = decoded;
      } catch (_) {}
    }
    return MayaMemory.fromJson({
      'id': row['id'],
      'text': row['text'],
      'category': row['category'],
      'createdAt': row['created_at'],
      'updatedAt': row['updated_at'],
      'source': row['source'],
      'importance': row['importance'],
      'tags': tags,
      'expiresAt': row['expires_at'],
    });
  }
}
