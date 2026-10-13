import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// App-private SQLite persistence for user-approved MAYA memory.
///
/// This database stores memory records only. API keys and credentials remain
/// in FlutterSecureStorage. The service also supports a one-time migration
/// from the older secure-storage JSON list.
class MayaMemoryDatabase {
  MayaMemoryDatabase._();

  static final MayaMemoryDatabase instance = MayaMemoryDatabase._();
  static const _databaseName = 'maya_memory_v1.db';
  static const _databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    final directory = await getApplicationDocumentsDirectory();
    final databasePath = path.join(directory.path, _databaseName);
    _database = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE memories (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            category TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            source TEXT NOT NULL,
            importance REAL NOT NULL,
            tags_json TEXT NOT NULL,
            expires_at TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX memories_category_idx ON memories(category)',
        );
        await db.execute(
          'CREATE INDEX memories_updated_idx ON memories(updated_at)',
        );
      },
    );
    return _database!;
  }

  Future<List<Map<String, dynamic>>> list() async {
    final db = await database;
    return db.query(
      'memories',
      orderBy: 'importance DESC, updated_at DESC',
    );
  }

  Future<void> replaceAll(List<Map<String, dynamic>> rows) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('memories');
      for (final row in rows) {
        await txn.insert(
          'memories',
          _encodeRow(row),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> upsert(Map<String, dynamic> row) async {
    final db = await database;
    await db.insert(
      'memories',
      _encodeRow(row),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete('memories');
  }

  Future<int> purgeExpired() async {
    final db = await database;
    return db.delete(
      'memories',
      where: 'expires_at IS NOT NULL AND expires_at < ?',
      whereArgs: [DateTime.now().toUtc().toIso8601String()],
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }

  static Map<String, dynamic> _encodeRow(Map<String, dynamic> row) => {
        'id': row['id']?.toString() ?? '',
        'text': row['text']?.toString() ?? '',
        'category': row['category']?.toString() ?? 'general',
        'created_at': row['created_at']?.toString() ??
            row['createdAt']?.toString() ??
            DateTime.now().toUtc().toIso8601String(),
        'updated_at': row['updated_at']?.toString() ??
            row['updatedAt']?.toString() ??
            DateTime.now().toUtc().toIso8601String(),
        'source': row['source']?.toString() ?? 'owner',
        'importance': row['importance'] is num
            ? (row['importance'] as num).toDouble()
            : double.tryParse('${row['importance']}') ?? 0.5,
        'tags_json': row['tags_json'] is String
            ? row['tags_json']
            : jsonEncode(row['tags'] is List ? row['tags'] : const <String>[]),
        'expires_at':
            row['expires_at']?.toString() ?? row['expiresAt']?.toString(),
      };
}
