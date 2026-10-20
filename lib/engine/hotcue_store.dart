import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Persists the main cue point and the hot cues of each track, keyed by file
/// path, so they survive unloading the deck and restarting the app.
///
/// Kept in its own database (not in the analysis cache) so a re-analysis or a
/// schema bump of the analysis table never wipes the DJ's cue points.
class HotCueStore {
  HotCueStore._();
  static final instance = HotCueStore._();

  static const slots = 4;
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'tetaldj_cues.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE cues (
          path TEXT NOT NULL,
          slot INTEGER NOT NULL,
          seconds REAL NOT NULL,
          PRIMARY KEY (path, slot)
        )
      '''),
    );
    return _db!;
  }

  /// Slot -1 is the main cue; slots 0..[slots]-1 are the hot cues.
  /// Returns a map slot -> seconds (only slots that are set).
  Future<Map<int, double>> load(String path) async {
    try {
      final db = await _open();
      final rows = await db.query(
        'cues',
        where: 'path = ?',
        whereArgs: [path],
      );
      return {
        for (final r in rows)
          (r['slot'] as num).toInt(): (r['seconds'] as num).toDouble(),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> set(String path, int slot, double seconds) async {
    try {
      final db = await _open();
      await db.insert('cues', {
        'path': path,
        'slot': slot,
        'seconds': seconds,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  Future<void> clear(String path, int slot) async {
    try {
      final db = await _open();
      await db.delete(
        'cues',
        where: 'path = ? AND slot = ?',
        whereArgs: [path, slot],
      );
    } catch (_) {}
  }
}
