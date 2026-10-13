import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Deterministic local semantic-style index.
///
/// This is intentionally not presented as an embedding model. It provides
/// offline token-vector retrieval now and can later be replaced by a real
/// embedding adapter without changing MemoryService callers.
class MayaOmegaVectorMemoryService {
  MayaOmegaVectorMemoryService._();

  static final MayaOmegaVectorMemoryService instance =
      MayaOmegaVectorMemoryService._();
  Database? _database;
  static const _dimensions = 64;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    final directory = await getApplicationDocumentsDirectory();
    _database = await openDatabase(
      path.join(directory.path, 'maya_vector_memory_v1.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE vectors (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            category TEXT NOT NULL,
            vector_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }

  Future<void> index({
    required String id,
    required String text,
    String category = 'general',
  }) async {
    final db = await database;
    await db.insert(
      'vectors',
      {
        'id': id,
        'text': text,
        'category': category,
        'vector_json': jsonEncode(_vectorize(text)),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> search(
    String query, {
    String? category,
    int limit = 20,
  }) async {
    final db = await database;
    final rows = await db.query(
      'vectors',
      where: category == null ? null : 'category = ?',
      whereArgs: category == null ? null : [category],
    );
    final queryVector = _vectorize(query);
    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['vector_json']?.toString() ?? '[]';
      List<double> vector;
      try {
        vector = (jsonDecode(raw) as List)
            .map((value) => (value as num).toDouble())
            .toList();
      } catch (_) {
        vector = const <double>[];
      }
      if (vector.length != _dimensions) continue;
      results.add({
        'id': row['id'],
        'text': row['text'],
        'category': row['category'],
        'similarity': _cosine(queryVector, vector),
        'updatedAt': row['updated_at'],
      });
    }
    results.sort(
      (a, b) =>
          (b['similarity'] as double).compareTo(a['similarity'] as double),
    );
    return results.take(limit.clamp(1, 100).toInt()).toList();
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('vectors', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete('vectors');
  }

  static List<double> _vectorize(String text) {
    final vector = List<double>.filled(_dimensions, 0);
    final tokens = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length > 1);
    for (final token in tokens) {
      var hash = 17;
      for (final unit in token.codeUnits) {
        hash = (hash * 31 + unit) & 0x7fffffff;
      }
      final index = hash % _dimensions;
      vector[index] += 1;
      vector[(index + 13) % _dimensions] += 0.25;
    }
    final norm = vector.fold<double>(0, (sum, value) => sum + value * value);
    if (norm == 0) return vector;
    final length = norm.isFinite ? math.sqrt(norm) : 1;
    return vector.map((value) => value / length).toList();
  }

  static double _cosine(List<double> left, List<double> right) {
    if (left.length != right.length) return 0;
    var value = 0.0;
    for (var index = 0; index < left.length; index++) {
      value += left[index] * right[index];
    }
    return value;
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
