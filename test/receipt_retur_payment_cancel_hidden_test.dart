import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug ditemukan saat review logika retur/kembalian (permintaan user):
/// tombol "Batalkan Pembayaran" sebelumnya muncul juga di baris refund retur
/// (amount negatif, uang & stok sudah permanen berubah lewat retur) dan
/// marker retur nota belum-lunas (method 'retur'/'edit') — membatalkannya
/// bikin kembalian HANTU (lihat dok `_isReturLinkedPayment`/
/// `AppDatabase.voidPayment`). Tombol itu HARUS tidak muncul utk baris-baris
/// itu, tapi TETAP muncul utk pembayaran normal.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'baris refund retur (amount negatif) & marker retur TIDAK punya '
      'tombol Batalkan Pembayaran, tapi pembayaran normal tetap punya',
      (tester) async {
    final now = DateTime(2026, 7, 13, 12, 0, 0);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(now),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 3,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 30000));
    // Pembayaran normal — HARUS tetap punya tombol batalkan.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 50000,
            method: 'tunai',
            paidAt: Value(now)));
    // Refund retur — TIDAK boleh punya tombol batalkan.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay2',
            transactionId: 'tx1',
            amount: -20000,
            method: 'tunai',
            paidAt: Value(now.add(const Duration(minutes: 1))),
            note: const Value('Refund retur (nota lunas)')));
    // Marker retur nota belum-lunas — TIDAK boleh punya tombol batalkan.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay3',
            transactionId: 'tx1',
            amount: 0,
            method: 'retur',
            paidAt: Value(now.add(const Duration(minutes: 2)))));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.byTooltip('Batalkan Pembayaran'), findsOneWidget,
        reason: 'cuma baris pembayaran normal (pay1) yang boleh punya '
            'tombol batalkan');
  });
}
