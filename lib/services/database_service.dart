import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/match_model.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, 'pickleball.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE matches (
            id        TEXT PRIMARY KEY,
            played_at TEXT NOT NULL,
            sets_json TEXT NOT NULL,
            winner    INTEGER NOT NULL,
            sets_p1   INTEGER NOT NULL,
            sets_p2   INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> saveMatch(MatchRecord match) async {
    final database = await db;
    await database.insert(
      'matches',
      {
        'id':        match.id,
        'played_at': match.playedAt.toIso8601String(),
        'sets_json': jsonEncode(match.sets.map((s) => s.toMap()).toList()),
        'winner':    match.winner,
        'sets_p1':   match.setsP1,
        'sets_p2':   match.setsP2,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MatchRecord>> loadMatches() async {
    final database = await db;
    final rows = await database.query(
      'matches',
      orderBy: 'played_at DESC',
      limit: 50,
    );
    return rows.map((row) {
      final setsRaw = jsonDecode(row['sets_json'] as String) as List;
      return MatchRecord(
        id:       row['id']     as String,
        playedAt: DateTime.parse(row['played_at'] as String),
        sets:     setsRaw.map((s) => SetResult.fromMap(s as Map<String, dynamic>)).toList(),
        winner:   row['winner'] as int,
        setsP1:   row['sets_p1'] as int,
        setsP2:   row['sets_p2'] as int,
      );
    }).toList();
  }

  Future<void> deleteMatch(String id) async {
    final database = await db;
    await database.delete('matches', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final database = await db;
    await database.delete('matches');
  }
}
