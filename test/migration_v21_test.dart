import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 20 -> 21 benar-benar menambah kolom
/// `device_code` (nullable) ke tabel `sync_upload_queue` yang sudah ada —
/// bug nyata dilaporkan user: antrian sync dikunci per-IP mentah, dua
/// device berbeda yang kebetulan berbagi IP (hotspot HP) saling menimpa
/// antrian satu sama lain. Kolom ini dipakai sbg kunci slot pengganti.
void main() {
  test('migrasi v20 -> v21: kolom device_code (sync_upload_queue) '
      'ditambah, default null, data lama utuh', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig21_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v20" mentah: sync_upload_queue SUDAH ADA (dibuat di
    // migrasi v18) TANPA kolom device_code, berisi 1 baris data lama.
    final v20 = raw.sqlite3.open(path);
    v20.execute('PRAGMA user_version = 20;');
    v20.execute('CREATE TABLE product_groups(id INTEGER PRIMARY KEY, name TEXT);');
    // product_units diperlukan agar migrasi v22 (addColumn requires_deposit) tak gagal.
    v20.execute('CREATE TABLE product_units(id TEXT PRIMARY KEY);');
    // customers diperlukan agar migrasi v28 (addColumn locally_modified) tak gagal.
    v20.execute('CREATE TABLE customers(id TEXT PRIMARY KEY);');
    v20.execute('''
      CREATE TABLE sync_upload_queue (
        id TEXT NOT NULL PRIMARY KEY,
        from_ip TEXT NOT NULL,
        arrived_at INTEGER NOT NULL,
        tables_json TEXT NOT NULL,
        since INTEGER NOT NULL,
        tables_summary TEXT NOT NULL
      );
    ''');
    v20.execute('''
      INSERT INTO sync_upload_queue
        (id, from_ip, arrived_at, tables_json, since, tables_summary)
      VALUES
        ('q-lama', '192.168.1.9', 1700000000, '{}', 1700000000, '1 transaksi');
    ''');
    final preCols = v20
        .select("PRAGMA table_info('sync_upload_queue')")
        .map((r) => r['name'] as String)
        .toSet();
    expect(preCols, isNot(contains('device_code')),
        reason: 'prakondisi: DB v20 belum punya kolom device_code');
    v20.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 21) → onUpgrade(20,21) jalan.
    // readOnly:true — DB raw ini cuma berisi tabel yang relevan (sengaja),
    // jadi seed beforeOpen (yang menulis ke unit_types dkk.) harus dilewati.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final postCols = (await db.customSelect(
            "PRAGMA table_info('sync_upload_queue')")
        .get())
        .map((r) => r.data['name'] as String)
        .toSet();
    expect(postCols, contains('device_code'),
        reason: 'migrasi harus menambah kolom device_code');

    // Data lama tetap utuh, device_code default null (bukan hilang/error).
    final rows = await db.select(db.syncUploadQueue).get();
    expect(rows, hasLength(1));
    expect(rows.single.fromIp, '192.168.1.9');
    expect(rows.single.deviceCode, isNull);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 28); // schemaVersion terkini

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
