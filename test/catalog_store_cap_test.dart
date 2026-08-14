import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/catalog/catalog_models.dart';
import 'package:the_pos/features/produk/catalog/catalog_store.dart';

/// Audit efisiensi storage — `saved_catalogs` (blob JSON di AppSettings)
/// sebelumnya tidak punya batas jumlah sama sekali. Cap ke yang TERBARU saja
/// supaya blob tidak bisa tumbuh tanpa batas kalau asumsi "katalog biasanya
/// sedikit" meleset di pemakaian nyata.
void main() {
  SavedCatalog fake(String id, int createdAtMs) => SavedCatalog(
        id: id,
        title: 'Katalog $id',
        createdAtMs: createdAtMs,
        lines: const [],
      );

  test('add() melebihi batas -> yang PALING LAMA dibuang, jumlah tetap '
      'di batas', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final store = CatalogStore(db);

    for (var i = 0; i < 35; i++) {
      await store.add(fake('c$i', i));
    }

    expect(store.state.length, 30);
    // Terbaru (createdAtMs terbesar, ditambah terakhir) harus tetap ada.
    expect(store.state.map((c) => c.id), contains('c34'));
    // Yang paling lama (ditambah pertama) harus sudah terbuang.
    expect(store.state.map((c) => c.id), isNot(contains('c0')));
    expect(store.state.map((c) => c.id), isNot(contains('c4')));

    // Persist ke DB juga ikut ter-cap, bukan cuma state di memori.
    final raw = await db.getSetting('saved_catalogs');
    final decoded = raw == null ? const [] : (jsonDecode(raw) as List);
    expect(decoded, hasLength(30));
    await db.close();
  });

  test('di bawah batas -> semua tersimpan, tidak ada yang terbuang',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final store = CatalogStore(db);
    await store.add(fake('a', 1));
    await store.add(fake('b', 2));
    expect(store.state.length, 2);
    await db.close();
  });
}
