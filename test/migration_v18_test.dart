import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';

/// Membuktikan migrasi schemaVersion 17 -> 18 benar-benar membuat tabel
/// `sync_upload_queue` (Item 17 Fase 2 — antrian approval sync sisi host
/// dipindah dari in-memory ke DB, biar tidak hilang kalau app di-restart
/// sebelum owner sempat approve) saat DB lama (belum punya tabel itu sama
/// sekali) dibuka — bukan sekadar compile.
void main() {
  test('migrasi v17 -> v18: tabel sync_upload_queue dibuat, bisa langsung '
      'dipakai', () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig18_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();

    // ── 1. Bangun DB "v17" mentah: sync_upload_queue SAMA SEKALI belum ada
    // (tabel baru, bukan addColumn — jadi tidak perlu stub tabel lain).
    final v17 = raw.sqlite3.open(path);
    v17.execute('PRAGMA user_version = 17;');
    final tables = v17
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'] as String)
        .toSet();
    expect(tables, isNot(contains('sync_upload_queue')),
        reason: 'prakondisi: DB v17 belum punya tabel sync_upload_queue');
    // product_groups diperlukan agar migrasi v19 (addColumn sort_order) tak gagal.
    v17.execute('CREATE TABLE product_groups(id INTEGER PRIMARY KEY, name TEXT);');
    v17.dispose();

    // ── 2. Buka via AppDatabase (schemaVersion 18) → onUpgrade(17,18) jalan.
    final db = AppDatabase(NativeDatabase(file), readOnly: true);

    final tablesAfter = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    final namesAfter =
        tablesAfter.map((r) => r.data['name'] as String).toSet();
    expect(namesAfter, contains('sync_upload_queue'),
        reason: 'migrasi harus membuat tabel sync_upload_queue');

    // Tabel baru langsung bisa dipakai lewat API Drift bertipe (bukan cuma
    // ada secara fisik di SQLite) — buktikan insert+select sungguhan.
    await db.into(db.syncUploadQueue).insert(SyncUploadQueueCompanion.insert(
          id: 'q1',
          fromIp: '192.168.1.5',
          tablesJson: '{"transactions":[]}',
          since: DateTime(2026, 1, 1),
          tablesSummary: '1 transaksi',
        ));
    final rows = await db.select(db.syncUploadQueue).get();
    expect(rows, hasLength(1));
    expect(rows.single.fromIp, '192.168.1.5');

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 19);

    await db.close();
    if (file.existsSync()) file.deleteSync();
  });
}
