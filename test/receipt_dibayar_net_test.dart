import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug lanjutan dilaporkan user: "Sisa Tagihan" sudah benar (fix
/// sebelumnya), tapi "Dibayar" di Ringkasan masih mentah (Σamount kotor)
/// sehingga Total != Dibayar + Sisa Tagihan lagi begitu kembalian lama
/// dipakai ulang — aplikasi pembanding konsisten (Dibayar bersih).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'Ringkasan tampilkan Dibayar Rp 55.000 (bersih, BUKAN Rp 60.000 '
      'mentah) supaya Total = Dibayar + Sisa Tagihan konsisten',
      (tester) async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 55000,
          changeAmount: 5000,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 55000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 7, 12, 8, 31)),
            changeGiven: const Value(5000)));

    // Tambah item 10.000, bayar 5.000 (reuse kembalian pay1).
    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
            id: 'i1',
            transactionId: txId,
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 10000,
            originalPrice: 10000,
            subtotal: 10000),
      ],
      stockItems: const [],
      payment: TransactionPaymentsCompanion.insert(
        id: 'pay2',
        transactionId: txId,
        amount: 5000,
        method: 'tunai',
        paidAt: Value(DateTime(2026, 7, 12, 8, 31)),
      ),
      kasirId: 'K1',
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    // Baris "Dibayar" gabung label+nominal jadi 1 Text ("Tunai · Rp X") —
    // dicek persis supaya tidak bentrok dgn "Total" (juga Rp 60.000, tapi
    // itu MEMANG benar, jangan disamakan dgn Dibayar yang harus bersih).
    expect(find.text('Tunai · ${formatRupiah(55000)}'), findsOneWidget,
        reason: 'Dibayar bersih: 55.000+5.000 dibayar - 5.000 kembalian '
            'yang sudah pernah diberikan');
    expect(find.text('Tunai · ${formatRupiah(60000)}'), findsNothing,
        reason: 'BUKAN jumlah mentah 60.000');
    expect(find.text(formatRupiah(60000)), findsWidgets,
        reason: 'Total tetap 60.000 (item 50rb + 10rb) — ini yang benar');
    expect(find.text('Sisa Tagihan'), findsOneWidget);
    expect(find.text(formatRupiah(5000)), findsWidgets,
        reason: 'Sisa Tagihan tetap 5.000 (sudah benar dari fix sebelumnya)');
  });
}
