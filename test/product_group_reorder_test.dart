import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 54 — urutan chip kategori Kasir (`sortOrder`), reaktif terhadap
/// `reorderProductGroups` (drag-reorder) TANPA perlu tutup-buka stream baru.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(101), name: const Value('Minuman')));
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(102), name: const Value('Snack')));
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(103), name: const Value('Sembako')));
  });
  tearDown(() => db.close());

  test('default (belum pernah direorder) terurut alfabetis via tie-break nama',
      () async {
    final groups = await db.watchProductGroupsForKasir().first;
    expect(groups.map((g) => g.name), ['Minuman', 'Sembako', 'Snack']);
  });

  test('reorderProductGroups mengubah urutan sesuai list baru', () async {
    await db.reorderProductGroups([103, 101, 102]); // Sembako, Minuman, Snack

    final groups = await db.watchProductGroupsForKasir().first;
    expect(groups.map((g) => g.name), ['Sembako', 'Minuman', 'Snack']);
  });

  test('stream watchProductGroupsForKasir re-emit setelah reorder (reaktif, '
      'bukan snapshot statis)', () async {
    final stream = db.watchProductGroupsForKasir();
    final emissions = <List<String?>>[];
    final sub = stream.listen((groups) {
      emissions.add(groups.map((g) => g.name).toList());
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await db.reorderProductGroups([102, 103, 101]); // Snack, Sembako, Minuman
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(emissions.length, greaterThan(1),
        reason: 'stream harus re-emit sendiri setelah reorder');
    expect(emissions.last, ['Snack', 'Sembako', 'Minuman']);
    await sub.cancel();
  });

  test('kategori baru selalu ditaruh PALING AKHIR (bukan 0) setelah kategori '
      'lain pernah direorder', () async {
    await db.reorderProductGroups([103, 101, 102]); // Sembako, Minuman, Snack
    await db.addProductGroup('Rokok');

    final groups = await db.watchProductGroupsForKasir().first;
    expect(groups.map((g) => g.name).last, 'Rokok',
        reason: 'kategori baru tidak boleh melompat ke depan gara-gara '
            'default sortOrder 0');
  });
}
