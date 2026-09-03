import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

import 'helpers/pump_app.dart';

/// Item 55 — bug filter produk di Riwayat Transaksi punya akar PERSIS SAMA
/// dgn bug filter pelanggan (`4a331d1`): `findTxIdsWithProduct` dulu dipakai
/// MENYARING hasil SETELAH query SQL utama (`ORDER BY created_at DESC LIMIT
/// 1000/100`) sudah dipotong, bukan SEBELUM. Kalau bulan yg dipilih sendiri
/// sudah punya >1000 transaksi produk LAIN, transaksi yg mengandung produk
/// yg dicari (lebih "tua" di dalam bulan itu) tertimbun & tidak muncul.
///
/// Skenario ini persis meniru pola
/// `tx_history_busy_month_search_limit_test.dart` (yg membuktikan bug
/// filter pelanggan), tapi utk filter produk.
Future<String> _insertProduct(AppDatabase db, String name) async {
  final id = 'prod-$name';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: id,
        name: name,
      ));
  return id;
}

Future<void> _insertTxWithItem(
  AppDatabase db, {
  required String txId,
  required String localId,
  required DateTime createdAt,
  required String productId,
}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: txId,
        localId: localId,
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(createdAt),
      ));
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: '$txId-item',
        transactionId: txId,
        productId: productId,
        productUnitId: '$productId-unit',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000,
      ));
}

void main() {
  testWidgets(
      'bulan yg dipilih punya >1000 transaksi produk lain -> transaksi '
      'produk target di awal bulan tetap harus muncul', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    final targetProductId = await _insertProduct(db, 'Gula Pasir');
    final otherProductId = await _insertProduct(db, 'Beras');

    // Transaksi target: produk "Gula Pasir", paling AWAL di bulan Januari
    // 2024 (posisi "tertua" kalau diurutkan DESC di dalam bulan itu).
    final target = DateTime(2024, 1, 1, 8, 0);
    await _insertTxWithItem(db,
        txId: 'tx-gula',
        localId: 'K1-GULA',
        createdAt: target,
        productId: targetProductId);

    // >1000 transaksi lain DI DALAM BULAN YANG SAMA (produk lain), semua
    // lebih baru dari transaksi target.
    final base = DateTime(2024, 1, 2, 0, 0);
    for (var i = 0; i < 1200; i++) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx-other-$i',
            localId: 'K1-O$i',
            status: 'lunas',
            total: 5000,
            paid: 5000,
            changeAmount: 0,
            paymentMethod: 'tunai',
            createdAt: Value(base.add(Duration(minutes: i * 30))),
          ));
      await db.into(db.transactionItems).insert(
          TransactionItemsCompanion.insert(
            id: 'tx-other-$i-item',
            transactionId: 'tx-other-$i',
            productId: otherProductId,
            productUnitId: '$otherProductId-unit',
            qty: 1,
            priceAtSale: 5000,
            originalPrice: 5000,
            subtotal: 5000,
          ));
    }

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    // Buka filter tanggal, pilih rentang Januari 2024 (bulan yg sendiri
    // sudah >1000 transaksi produk lain).
    await tester.ensureVisible(find.text('Semua Tanggal'));
    await tester.tap(find.text('Semua Tanggal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Start Date', skipOffstage: false),
        '1/1/2024');
    await tester.enterText(
        find.widgetWithText(TextField, 'End Date', skipOffstage: false),
        '1/31/2024');
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Ketik nama produk di kotak "Filter produk…" (debounce 400ms).
    await tester.enterText(
        find.widgetWithText(TextField, 'Filter produk…'), 'Gula');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('K1-GULA'), findsOneWidget,
        reason: 'transaksi produk target harus tetap muncul walau bulan '
            'itu sendiri punya >1000 transaksi produk lain yang lebih baru');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
