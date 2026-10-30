import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Satu ronde doorprize. [finishedAt] null = ronde masih aktif.
class Round {
  final int? id;
  final String nama;
  final int createdAt;
  final int? finishedAt;

  const Round({
    this.id,
    required this.nama,
    required this.createdAt,
    this.finishedAt,
  });

  bool get isActive => finishedAt == null;

  factory Round.fromMap(Map<String, Object?> m) => Round(
        id: m['id'] as int?,
        nama: m['nama'] as String,
        createdAt: (m['created_at'] as int?) ?? 0,
        finishedAt: m['finished_at'] as int?,
      );
}

/// Satu nomor doorprize (disimpan sebagai teks agar nol depan aman).
class DoorprizeNumber {
  final int? id;
  final int roundId;
  final String nomor;
  final int createdAt;

  const DoorprizeNumber({
    this.id,
    required this.roundId,
    required this.nomor,
    required this.createdAt,
  });

  factory DoorprizeNumber.fromMap(Map<String, Object?> m) => DoorprizeNumber(
        id: m['id'] as int?,
        roundId: (m['round_id'] as int?) ?? 0,
        nomor: m['nomor'] as String,
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

/// Database lokal: rounds + numbers + settings (key-value).
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String kTitle = 'title';
  static const String defaultTitle = 'NOMOR DOORPRIZE';

  Database? _db;

  /// Override path database (untuk test). Null = path normal dokumen.
  static String? debugDatabasePath;

  /// Tutup & reset koneksi (untuk test).
  Future<void> debugReset() async {
    await _db?.close();
    _db = null;
    debugDatabasePath = null;
  }

  Future<Database> get database async {
    final db = _db;
    if (db != null) return db;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final String path;
    if (debugDatabasePath != null) {
      path = debugDatabasePath!;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, 'doorprize_display.db');
    }
    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE rounds(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nama TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              finished_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE numbers(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              round_id INTEGER NOT NULL,
              nomor TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              UNIQUE(round_id, nomor)
            )
          ''');
          await db.execute('''
            CREATE TABLE settings(
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
        },
      ),
    );
  }

  // ---------- Ronde ----------

  /// Ronde aktif (belum selesai), atau null bila tidak ada.
  Future<Round?> getActiveRound() async {
    final db = await database;
    final rows = await db.query(
      'rounds',
      where: 'finished_at IS NULL',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Round.fromMap(rows.first);
  }

  /// Ambil ronde aktif, buat baru bila belum ada.
  Future<Round> getOrCreateActiveRound() async {
    final active = await getActiveRound();
    if (active != null) return active;
    return startRound();
  }

  /// Mulai ronde baru. Nama = "Ronde N" dari MAX(id)+1 (bukan COUNT+1,
  /// agar tidak duplikat/mendaur nomor bila ada ronde yang dihapus
  /// dari riwayat).
  Future<Round> startRound() async {
    final db = await database;
    final next =
        (await db.rawQuery('SELECT COALESCE(MAX(id), 0) + 1 AS n FROM rounds'))
            .first['n'] as int;
    final id = await db.insert('rounds', {
      'nama': 'Ronde $next',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'finished_at': null,
    });
    final rows =
        await db.query('rounds', where: 'id = ?', whereArgs: [id], limit: 1);
    return Round.fromMap(rows.first);
  }

  /// Selesaikan ronde (masuk riwayat).
  Future<void> finishRound(int id) async {
    final db = await database;
    await db.update(
      'rounds',
      {'finished_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Daftar ronde yang sudah selesai (terbaru dulu).
  Future<List<Round>> getFinishedRounds() async {
    final db = await database;
    final rows = await db.query(
      'rounds',
      where: 'finished_at IS NOT NULL',
      orderBy: 'id DESC',
    );
    return rows.map(Round.fromMap).toList();
  }

  /// Hapus ronde + semua nomornya (dari riwayat).
  Future<void> deleteRound(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('numbers', where: 'round_id = ?', whereArgs: [id]);
      await txn.delete('rounds', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------- Nomor ----------

  Future<List<DoorprizeNumber>> getNumbers(int roundId) async {
    final db = await database;
    final rows = await db.query(
      'numbers',
      where: 'round_id = ?',
      whereArgs: [roundId],
      orderBy: 'id ASC',
    );
    return rows.map(DoorprizeNumber.fromMap).toList();
  }

  /// Tambah nomor ke ronde. Melempar [DuplicateNumberException] bila
  /// nomor sudah ada di ronde yang sama.
  Future<void> addNumber(int roundId, String nomor) async {
    final db = await database;
    try {
      await db.insert('numbers', {
        'round_id': roundId,
        'nomor': nomor,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw DuplicateNumberException();
      rethrow;
    }
  }

  /// Ubah nomor. Melempar [DuplicateNumberException] bila bentrok
  /// dengan nomor lain di ronde yang sama.
  Future<void> updateNumber(int id, int roundId, String nomor) async {
    final db = await database;
    try {
      await db.update(
        'numbers',
        {'nomor': nomor},
        where: 'id = ? AND round_id = ?',
        whereArgs: [id, roundId],
      );
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) throw DuplicateNumberException();
      rethrow;
    }
  }

  Future<void> deleteNumber(int id) async {
    final db = await database;
    await db.delete('numbers', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- Settings ----------

  Future<String> getSetting(String key, String fallback) async {
    final db = await database;
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return fallback;
    return rows.first['value'] as String? ?? fallback;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class DuplicateNumberException implements Exception {}
