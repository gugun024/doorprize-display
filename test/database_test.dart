import 'package:doorprize_display/core/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseHelper.debugDatabasePath = inMemoryDatabasePath;
  });

  tearDown(() async {
    await DatabaseHelper.instance.debugReset();
  });

  test('ronde aktif dibuat otomatis (Ronde 1, 2, ...)', () async {
    final db = DatabaseHelper.instance;
    final r1 = await db.getOrCreateActiveRound();
    expect(r1.nama, 'Ronde 1');
    expect(r1.isActive, isTrue);
    // Panggil lagi -> ronde yang sama, bukan dobel.
    final r1b = await db.getOrCreateActiveRound();
    expect(r1b.id, r1.id);
  });

  test('tambah + baca nomor urut id dalam ronde', () async {
    final db = DatabaseHelper.instance;
    final r = await db.getOrCreateActiveRound();
    await db.addNumber(r.id!, '012345');
    await db.addNumber(r.id!, '078901');
    final list = await db.getNumbers(r.id!);
    expect(list.map((e) => e.nomor), ['012345', '078901']);
  });

  test('nol depan tidak hilang (disimpan sebagai teks)', () async {
    final db = DatabaseHelper.instance;
    final r = await db.getOrCreateActiveRound();
    await db.addNumber(r.id!, '00123');
    final list = await db.getNumbers(r.id!);
    expect(list.single.nomor, '00123');
  });

  test('nomor duplikat dalam ronde yang sama ditolak', () async {
    final db = DatabaseHelper.instance;
    final r = await db.getOrCreateActiveRound();
    await db.addNumber(r.id!, '111');
    expect(() => db.addNumber(r.id!, '111'),
        throwsA(isA<DuplicateNumberException>()));
    expect((await db.getNumbers(r.id!)).length, 1);
  });

  test('nomor sama di ronde berbeda boleh', () async {
    final db = DatabaseHelper.instance;
    final r1 = await db.getOrCreateActiveRound();
    await db.addNumber(r1.id!, '111');
    await db.finishRound(r1.id!);
    final r2 = await db.getOrCreateActiveRound();
    expect(r2.nama, 'Ronde 2');
    await db.addNumber(r2.id!, '111'); // tidak melempar
    expect((await db.getNumbers(r2.id!)).single.nomor, '111');
  });

  test('edit nomor + tolak duplikat saat edit', () async {
    final db = DatabaseHelper.instance;
    final r = await db.getOrCreateActiveRound();
    await db.addNumber(r.id!, '111');
    await db.addNumber(r.id!, '222');
    final list = await db.getNumbers(r.id!);
    await db.updateNumber(list.first.id!, r.id!, '333');
    expect((await db.getNumbers(r.id!)).map((e) => e.nomor),
        ['333', '222']);
    expect(
        () => db.updateNumber(list.last.id!, r.id!, '333'),
        throwsA(isA<DuplicateNumberException>()));
  });

  test('hapus nomor', () async {
    final db = DatabaseHelper.instance;
    final r = await db.getOrCreateActiveRound();
    await db.addNumber(r.id!, '111');
    await db.addNumber(r.id!, '222');
    final id = (await db.getNumbers(r.id!)).first.id!;
    await db.deleteNumber(id);
    expect((await db.getNumbers(r.id!)).map((e) => e.nomor), ['222']);
  });

  test('selesai -> masuk riwayat, ronde baru kosong', () async {
    final db = DatabaseHelper.instance;
    final r1 = await db.getOrCreateActiveRound();
    await db.addNumber(r1.id!, '111');
    await db.addNumber(r1.id!, '222');
    await db.finishRound(r1.id!);

    final history = await db.getFinishedRounds();
    expect(history.length, 1);
    expect(history.single.nama, 'Ronde 1');
    expect(history.single.isActive, isFalse);

    final r2 = await db.getOrCreateActiveRound();
    expect(r2.nama, 'Ronde 2');
    expect(await db.getNumbers(r2.id!), isEmpty);
    // Nomor ronde lama tetap tersimpan.
    expect((await db.getNumbers(r1.id!)).map((e) => e.nomor), ['111', '222']);
  });

  test('hapus ronde dari riwayat ikut hapus nomornya', () async {
    final db = DatabaseHelper.instance;
    final r1 = await db.getOrCreateActiveRound();
    await db.addNumber(r1.id!, '111');
    await db.finishRound(r1.id!);
    await db.deleteRound(r1.id!);
    expect(await db.getFinishedRounds(), isEmpty);
    expect(await db.getNumbers(r1.id!), isEmpty);
  });

  test('settings: judul default & simpan', () async {
    final db = DatabaseHelper.instance;
    expect(
        await db.getSetting(
            DatabaseHelper.kTitle, DatabaseHelper.defaultTitle),
        DatabaseHelper.defaultTitle);
    await db.setSetting(DatabaseHelper.kTitle, 'DOORPRIZE RT 05');
    expect(await db.getSetting(DatabaseHelper.kTitle, 'x'),
        'DOORPRIZE RT 05');
  });
}
