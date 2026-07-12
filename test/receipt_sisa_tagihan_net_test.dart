import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: "Sisa Tagihan" di struk understated (Rp 16.800,
/// seharusnya Rp 18.100) saat kembalian yang sudah pernah diberikan
/// (Rp 1.300) dipakai ulang sebagai pembayaran item tambahan. Lihat
/// test/net_remaining_owed_test.dart untuk pembuktian di lapisan DB.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'struk tampilkan Sisa Tagihan Rp 18.100 (BUKAN Rp 16.800) saat '
      'kembalian lama dipakai ulang sbg pembayaran item tambahan',
      (tester) async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 38700,
          paid: 40000,
          changeAmount: 1300,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 38700,
        originalPrice: 38700,
        subtotal: 38700));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 40000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 7, 12, 6, 33)),
            changeGiven: const Value(1300)));

    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
            id: 'i1',
            transactionId: txId,
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 19400,
            originalPrice: 19400,
            subtotal: 19400),
      ],
      stockItems: const [],
      payment: TransactionPaymentsCompanion.insert(
        id: 'pay2',
        transactionId: txId,
        amount: 1300,
        method: 'tunai',
        paidAt: Value(DateTime(2026, 7, 12, 6, 34)),
      ),
      kasirId: 'K1',
    );

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Sisa Tagihan'), findsOneWidget);
    expect(find.text(formatRupiah(18100)), findsOneWidget);
    expect(find.text(formatRupiah(16800)), findsNothing);
  });
}
