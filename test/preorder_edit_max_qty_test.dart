import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// PLAN.md Item 56 (keputusan user, 2 September 2026) — kasus nyata nota
/// `A1-20260902-0014`: entri pre-order diedit lewat sheet pensil dari qty 1
/// jadi qty 2, TANPA baris nota tertaut ikut naik jadi 2. Keputusan user:
/// "edit tidak melebihi item produk. Jika ada 2 produk, edit jaminan lock
/// max di 2. Untuk penambahan entri produk baru, harusnya lewat tambah
/// pesanan/barang." — jadi sheet edit pre-order WAJIB mengunci qty (dan
/// jaminan yang ikut qty itu) ke qty baris nota tertaut, KHUSUS entri yang
/// punya `transactionItemId`. Entri tanpa tautan (lama, atau titip wadah
/// tanpa beli) TIDAK terpengaruh — tidak ada apa pun utk dibandingkan.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  Future<void> seedTx({
    required double txItemQty,
    required double preorderQty,
    required double preorderDeposit,
    bool linked = true,
  }) async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'LPG 3kg'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1',
          productId: 'P1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: txItemQty,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'po1',
          productId: 'P1',
          productUnitId: 'U1',
          transactionId: const Value(txId),
          transactionItemId: linked ? const Value('i1') : const Value.absent(),
          customerName: 'Pak Budi',
          qtyOrdered: preorderQty,
          depositQty: Value(preorderDeposit),
        ));
  }

  tearDown(() async => db.close());

  Future<void> openEditSheet(WidgetTester tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));
    await tester.tap(find.byTooltip('Ubah'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'entri tertaut baris nota qty 1: qty 2 di sheet edit -> DITOLAK dgn '
      'pesan jelas, DB tidak berubah', (tester) async {
    await seedTx(txItemQty: 1, preorderQty: 1, preorderDeposit: 1);
    await openEditSheet(tester);

    expect(find.textContaining('Maks 1'), findsOneWidget,
        reason: 'helper text menjelaskan cap ke qty baris nota');

    final qtyField = find
        .byWidgetPredicate((w) => w is TextField && w.controller?.text == '1')
        .first;
    await tester.enterText(qtyField, '2');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(
        find.text('Tidak boleh melebihi qty di nota (1) — tambah lewat '
            'Tambah Belanjaan'),
        findsOneWidget);

    final p = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(p.qtyOrdered, 1,
        reason: 'ditolak & sheet tetap terbuka -> tidak tersimpan');

    // Tutup sheet dgn bersih (bukan biarkan modal route pending) sebelum
    // drain — sheet ditolak jadi tidak menutup dirinya sendiri. Unfocus
    // dulu (field qty masih fokus dari enterText) supaya overlay seleksi
    // teks tidak animasi keluar SETELAH controller-nya di-dispose.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'entri tertaut baris nota qty 1: qty 0.5 (masih <= 1) DITERIMA',
      (tester) async {
    await seedTx(txItemQty: 1, preorderQty: 1, preorderDeposit: 0);
    await openEditSheet(tester);

    final qtyField = find
        .byWidgetPredicate((w) => w is TextField && w.controller?.text == '1')
        .first;
    await tester.enterText(qtyField, '0.5');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final p = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(p.qtyOrdered, 0.5);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'jaminan ikut dikunci ke qty YANG BERLAKU: turunkan qty ke 1 lalu '
      'jaminan lama (2) DITOLAK', (tester) async {
    await seedTx(
        txItemQty: 2, preorderQty: 2, preorderDeposit: 2);
    await openEditSheet(tester);

    final qtyField = find
        .byWidgetPredicate((w) => w is TextField && w.controller?.text == '2')
        .first;
    await tester.enterText(qtyField, '1');
    // Field jaminan masih berisi nilai lama '2' (belum diubah user).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tidak boleh melebihi jumlah'), findsOneWidget);

    final p = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(p.qtyOrdered, 2, reason: 'ditolak -> tidak tersimpan sama sekali');

    // Perbaiki jaminan ke 1 -> baru diterima.
    final depositField = find
        .byWidgetPredicate((w) => w is TextField && w.controller?.text == '2')
        .last;
    await tester.enterText(depositField, '1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final p2 = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(p2.qtyOrdered, 1);
    expect(p2.depositQty, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'entri TANPA transactionItemId: qty bebas diedit melebihi qty baris '
      'nota (regresi negatif — cap TIDAK berlaku)', (tester) async {
    await seedTx(
        txItemQty: 1, preorderQty: 1, preorderDeposit: 1, linked: false);
    await openEditSheet(tester);

    expect(find.textContaining('Maks'), findsNothing,
        reason: 'entri tanpa tautan tidak punya apa pun utk dibandingkan');

    final qtyField = find
        .byWidgetPredicate((w) => w is TextField && w.controller?.text == '1')
        .first;
    await tester.enterText(qtyField, '5');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final p = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(p.qtyOrdered, 5, reason: 'tidak kena cap -> bebas spt sebelumnya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
