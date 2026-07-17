import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 36 — Stock Opname: commitOpname() menulis satu baris stock_ledger
/// per produk memakai timestamp+note yang SAMA PERSIS dalam satu sesi (agar
/// getOpnameSessions() bisa mengelompokkannya kembali jadi satu sesi
/// riwayat), dan getOpnameSessionDetail() mengembalikan rincian per produk.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> addProduct(String name, {double initialStock = 0}) async {
    final id = 'p-$name';
    final unitId = '$id-u';
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
        ));
    if (initialStock != 0) {
      await db.adjustStock(productUnitId: unitId, newQty: initialStock);
    }
    return unitId;
  }

  // stock_ledger.created_at dipotong ke presisi detik (epoch integer) — jeda
  // ini menjamin baris "stok awal" (dari addProduct) & baris opname yang
  // diuji tidak jatuh di detik yang sama, supaya tie-break ORDER BY id DESC
  // (yg tidak berkorelasi kronologis utk UUID acak) tidak memutar hasil test.
  Future<void> settle() =>
      Future.delayed(const Duration(seconds: 1, milliseconds: 50));

  test('commitOpname menulis stock_after = hasil hitung fisik persis', () async {
    final u = await addProduct('Beras', initialStock: 10);
    await settle();

    await db.commitOpname(
      entries: [(productUnitId: u, newQty: 7)],
      note: 'Opname 17 Jul 2026 (Seluruh)',
    );

    expect(await db.currentStock(u), 7);
  });

  test('satu sesi opname (banyak produk) tercatat dgn timestamp+note SAMA '
      'PERSIS, sehingga getOpnameSessions() mengelompokkannya jadi 1 sesi',
      () async {
    final u1 = await addProduct('Gula', initialStock: 5);
    final u2 = await addProduct('Kopi', initialStock: 3);
    final u3 = await addProduct('Teh', initialStock: 8);
    await settle();

    await db.commitOpname(
      entries: [
        (productUnitId: u1, newQty: 4), // selisih -1
        (productUnitId: u2, newQty: 3), // tidak berubah -- tapi tetap ikut
        (productUnitId: u3, newQty: 10), // selisih +2
      ],
      note: 'Opname 17 Jul 2026 (Seluruh)',
    );

    final sessions = await db.getOpnameSessions();
    expect(sessions.length, 1);
    expect(sessions.first.itemCount, 3);
    expect(sessions.first.note, 'Opname 17 Jul 2026 (Seluruh)');
  });

  test('dua sesi opname berbeda TIDAK tercampur jadi satu', () async {
    final u1 = await addProduct('Minyak', initialStock: 10);
    await settle();

    await db.commitOpname(
      entries: [(productUnitId: u1, newQty: 9)],
      note: 'Opname 17 Jul 2026 (Seluruh)',
    );
    await settle();
    await db.commitOpname(
      entries: [(productUnitId: u1, newQty: 8)],
      note: 'Opname 18 Jul 2026 (Seluruh)',
    );

    final sessions = await db.getOpnameSessions();
    expect(sessions.length, 2);
    // Terbaru dulu.
    expect(sessions.first.note, 'Opname 18 Jul 2026 (Seluruh)');
  });

  test('getOpnameSessionDetail mengembalikan nama produk + selisih benar',
      () async {
    final u1 = await addProduct('Sabun', initialStock: 20);
    final u2 = await addProduct('Shampo', initialStock: 15);
    await settle();

    await db.commitOpname(
      entries: [
        (productUnitId: u1, newQty: 18),
        (productUnitId: u2, newQty: 15),
      ],
      note: 'Opname 17 Jul 2026 (Seluruh)',
    );

    final sessions = await db.getOpnameSessions();
    final detail = await db.getOpnameSessionDetail(
        createdAt: sessions.first.createdAt, note: sessions.first.note);

    expect(detail.length, 2);
    final sabun = detail.firstWhere((d) => d.productName == 'Sabun');
    expect(sabun.qtyChange, -2);
    expect(sabun.stockAfter, 18);
    final shampo = detail.firstWhere((d) => d.productName == 'Shampo');
    expect(shampo.qtyChange, 0);
    expect(shampo.stockAfter, 15);
  });

  test('penyesuaian stok manual biasa ("Penyesuaian manual") TIDAK ikut '
      'terhitung sbg sesi opname (filter note harus benar)', () async {
    final u = await addProduct('Garam', initialStock: 5);
    await db.adjustStock(
        productUnitId: u, newQty: 3, note: 'Penyesuaian manual');

    final sessions = await db.getOpnameSessions();
    expect(sessions, isEmpty);
  });

  test('buildOpnameNote membedakan Seluruh vs Kategori', () {
    final at = DateTime(2026, 7, 17);
    expect(AppDatabase.buildOpnameNote(at), 'Opname 17 Jul 2026 (Seluruh)');
    expect(AppDatabase.buildOpnameNote(at, categoryLabel: 'Sembako'),
        'Opname 17 Jul 2026 (Kategori: Sembako)');
  });
}
