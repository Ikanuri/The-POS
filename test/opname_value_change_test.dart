import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Riwayat opname dulu cuma menampilkan QTY selisih — padahal yang dipakai
/// untuk pertanggungjawaban adalah NILAI RUPIAH-nya ("modal yang menguap
/// berapa"). Nilai dihitung dari HPP (`price_tiers.cost_price` tier
/// `min_qty = 1`), pola sama `getInventoryRows`.
Future<void> _seedProduct(
  AppDatabase db, {
  required String pid,
  required String uid,
  required String name,
  required double stock,
  int? costPrice,
}) async {
  await db.into(db.products).insert(ProductsCompanion.insert(id: pid, name: name));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: uid,
        productId: pid,
        isBaseUnit: const Value(true),
      ));
  if (costPrice != null) {
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'pt-$uid',
          productUnitId: uid,
          price: costPrice * 2,
          minQty: const Value(1),
          costPrice: Value(costPrice),
        ));
  }
  await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
        id: 'sl-$uid',
        productUnitId: uid,
        type: 'opening',
        qtyChange: stock,
        stockAfter: stock,
        createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
      ));
}

String _note() => AppDatabase.buildOpnameNote(DateTime.now());

void main() {
  test(
      'selisih MINUS (fisik < catatan) -> valueChange negatif sebesar '
      'qty x HPP', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db,
        pid: 'p1', uid: 'u1', name: 'Beras', stock: 10, costPrice: 12000);

    // Stok sistem 10, hitung fisik 7 -> selisih -3 x 12.000 = -36.000.
    await db.commitOpname(
      entries: [(productUnitId: 'u1', newQty: 7.0)],
      note: _note(),
      kasirId: 'K1',
    );

    final sessions = await db.getOpnameSessions();
    expect(sessions, hasLength(1));
    expect(sessions.single.valueChange, -36000,
        reason: 'susut 3 unit x HPP 12.000');

    final detail = await db.getOpnameSessionDetail(
        createdAt: sessions.single.createdAt, note: sessions.single.note);
    expect(detail, hasLength(1));
    expect(detail.single.costPrice, 12000);
    expect(detail.single.valueChange, -36000);
  });

  test('selisih PLUS (fisik > catatan) -> valueChange positif', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db,
        pid: 'p1', uid: 'u1', name: 'Gula', stock: 5, costPrice: 15000);

    await db.commitOpname(
      entries: [(productUnitId: 'u1', newQty: 8.0)],
      note: _note(),
      kasirId: 'K1',
    );

    final sessions = await db.getOpnameSessions();
    expect(sessions.single.valueChange, 45000);
  });

  test('beberapa produk dalam satu sesi -> valueChange sesi = jumlah semua, '
      'susut & lebih saling mengurangi', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db,
        pid: 'p1', uid: 'u1', name: 'Beras', stock: 10, costPrice: 10000);
    await _seedProduct(db,
        pid: 'p2', uid: 'u2', name: 'Gula', stock: 4, costPrice: 5000);

    await db.commitOpname(
      entries: [
        (productUnitId: 'u1', newQty: 8.0), // -2 x 10rb = -20rb
        (productUnitId: 'u2', newQty: 7.0), // +3 x 5rb  = +15rb
      ],
      note: _note(),
      kasirId: 'K1',
    );

    final sessions = await db.getOpnameSessions();
    expect(sessions.single.itemCount, 2);
    expect(sessions.single.valueChange, -5000,
        reason: '-20.000 + 15.000 = -5.000');
  });

  test(
      'produk tanpa tier harga (HPP belum diisi) -> valueChange 0, opname '
      'TETAP tercatat (bukan error)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedProduct(db,
        pid: 'p9', uid: 'u9', name: 'Tanpa HPP', stock: 10);

    await db.commitOpname(
      entries: [(productUnitId: 'u9', newQty: 4.0)],
      note: _note(),
      kasirId: 'K1',
    );

    final sessions = await db.getOpnameSessions();
    expect(sessions, hasLength(1),
        reason: 'sesinya tetap ada walau HPP tidak diketahui');
    expect(sessions.single.valueChange, 0);

    final detail = await db.getOpnameSessionDetail(
        createdAt: sessions.single.createdAt, note: sessions.single.note);
    expect(detail.single.qtyChange, -6,
        reason: 'qty selisih tetap benar, cuma nilai rupiahnya yang 0');
  });
}
