import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 49g — struk in-app nota LUNAS yang pernah diretur: item ASLI tetap
/// tampil (tidak dihapus), separator "Retur HH:MM" muncul sebelum baris
/// retur, dan footer ringkasan ganti jadi breakdown "Total awal/Retur/
/// Total akhir/Refund" (bukan 3-baris biasa).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'nota lunas yang pernah diretur: item asli tetap ada, separator '
      '"Retur" muncul, footer breakdown Total awal/Retur/Total akhir/Refund',
      (tester) async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 406000,
          paid: 406000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-12',
        transactionId: txId,
        productId: 'P12',
        productUnitId: 'U-Slop',
        qty: 1,
        priceAtSale: 193000,
        originalPrice: 193000,
        subtotal: 193000));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-refil',
        transactionId: txId,
        productId: 'PRefil',
        productUnitId: 'U-Slop-Refil',
        qty: 1,
        priceAtSale: 213000,
        originalPrice: 213000,
        subtotal: 213000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: txId, amount: 406000, method: 'tunai'));

    await db.returnPaidTransactionItems(
      txId: txId,
      returns: const [(transactionItemId: 'i-refil', qty: 1)],
      kasirId: 'K1',
      refundMethod: 'tunai',
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    // Item ASLI (i-refil) TETAP ADA (bukan dihapus) — muncul 2x: baris asli
    // (qty 1) DAN baris retur baru (qty -1), sama-sama produk "PRefil".
    expect(find.text('PRefil'), findsNWidgets(2));
    // Separator "Retur HH:MM" muncul.
    expect(find.textContaining('Retur '), findsOneWidget);

    // Footer breakdown — cek label + nilai (amount bisa juga muncul di
    // timeline pembayaran mentah in-app, jadi cukup findsWidgets utk nilai,
    // tidak perlu exact count).
    expect(find.text('Total awal'), findsOneWidget);
    expect(find.text(formatRupiah(406000)), findsWidgets);
    // "Retur" juga label tombol aksi "Retur Barang" (Icons.assignment_
    // return_outlined) — 2 match wajar (tombol + baris ringkasan), bukan
    // ambigu/bug.
    expect(find.text('Retur'), findsNWidgets(2));
    expect(find.textContaining('- ${formatRupiah(213000)}'), findsOneWidget);
    expect(find.text('Total akhir'), findsOneWidget);
    expect(find.text(formatRupiah(193000)), findsWidgets);
    expect(find.textContaining('Refund'), findsOneWidget);

    // Pola 3-baris biasa (Item 49b) TIDAK dipakai di sini.
    expect(find.text('Total'), findsNothing,
        reason: 'label "Total" polos diganti "Total awal"/"Total akhir"');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
