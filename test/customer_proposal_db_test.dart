import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Susulan (permintaan user): "buat opsi usulan juga ketika disync (entah
/// itu ubah data atau tambah baru)" utk pelanggan — pola SAMA PERSIS dgn
/// usulan produk (Item 40)/Laci Meja (Item 52): `customers.locally_modified`
/// + `dumpLocalCustomerProposals`/`applyCustomerProposals`. Test DB murni
/// (level 1, tanpa widget) — mirip `laci_meja_db_test.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedCustomer(String id, String name,
      {bool locallyModified = false}) async {
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: id,
          name: name,
          locallyModified: Value(locallyModified),
        ));
  }

  test('dumpLocalCustomerProposals hanya ambil baris locally_modified = 1',
      () async {
    await seedCustomer('c1', 'Budi', locallyModified: true);
    await seedCustomer('c2', 'Ani', locallyModified: false);

    final dump = await db.dumpLocalCustomerProposals();
    expect(dump, hasLength(1));
    expect(dump.single['id'], 'c1');
  });

  test(
      'applyCustomerProposals menulis hanya id yang di-approve, '
      'locallyModified dipaksa false, updated_at dicap ulang', () async {
    await seedCustomer('c1', 'Budi', locallyModified: true);
    await seedCustomer('c2', 'Ani', locallyModified: true);

    final dump = await db.dumpLocalCustomerProposals();
    final count = await db.applyCustomerProposals(dump, {'c1'});
    expect(count, 1);

    final c1 =
        await (db.select(db.customers)..where((t) => t.id.equals('c1')))
            .getSingle();
    expect(c1.locallyModified, isFalse,
        reason: 'host adalah sumber kebenaran setelah disetujui');

    final c2 =
        await (db.select(db.customers)..where((t) => t.id.equals('c2')))
            .getSingle();
    expect(c2.locallyModified, isTrue,
        reason: 'yang TIDAK disetujui harus tetap menggantung sbg usulan');
  });

  test(
      'markCustomerLocallyModified menandai baris & cap ulang updated_at '
      '(supaya lolos watermark dumpSince berikutnya)', () async {
    await seedCustomer('c1', 'Budi');
    final before =
        await (db.select(db.customers)..where((t) => t.id.equals('c1')))
            .getSingle();
    expect(before.locallyModified, isFalse);

    await db.markCustomerLocallyModified('c1');
    final after =
        await (db.select(db.customers)..where((t) => t.id.equals('c1')))
            .getSingle();
    expect(after.locallyModified, isTrue);
    expect(after.updatedAt.isAfter(before.updatedAt) ||
            after.updatedAt.isAtSameMomentAs(before.updatedAt),
        isTrue);
  });

  test(
      'pelanggan BARU (bukan cuma edit) yg ditandai locally_modified juga '
      'ikut ke usulan (dumpLocalCustomerProposals membawa data lengkap, '
      'bukan cuma delta)', () async {
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c-baru',
          name: 'Pelanggan Baru',
          phone: const Value('08123'),
          locallyModified: const Value(true),
        ));

    final dump = await db.dumpLocalCustomerProposals();
    expect(dump, hasLength(1));
    expect(dump.single['name'], 'Pelanggan Baru');
    expect(dump.single['phone'], '08123');

    final count = await db.applyCustomerProposals(dump, {'c-baru'});
    expect(count, 1);
    final applied = await (db.select(db.customers)
          ..where((t) => t.id.equals('c-baru')))
        .getSingle();
    expect(applied.name, 'Pelanggan Baru');
    expect(applied.phone, '08123');
  });
}
