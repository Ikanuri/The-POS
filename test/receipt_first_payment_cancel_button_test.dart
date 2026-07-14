import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Regresi: nota tunai lunas SEKETIKA (satu pembayaran, paidAt == createdAt
/// persis) sebelumnya menyembunyikan card "Riwayat Pembayaran" sepenuhnya —
/// akibatnya tombol "Batalkan Pembayaran" TIDAK PERNAH bisa dijangkau untuk
/// kasus paling umum (pelunasan pertama kali), padahal itu justru skenario
/// paling sering butuh dibatalkan (mis. kasir salah pencet nominal).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'nota lunas SEKETIKA (1 pembayaran, waktu sama dgn nota dibuat) tetap '
      'menampilkan Riwayat Pembayaran + tombol Batalkan Pembayaran',
      (tester) async {
    final now = DateTime(2026, 7, 13, 12, 0, 0);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(now),
        ));
    await db.into(db.transactionItems).insert(
        TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 20000,
            originalPrice: 20000,
            subtotal: 20000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 20000,
            method: 'tunai',
            paidAt: Value(now)));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Riwayat Pembayaran'), findsOneWidget);
    expect(find.byTooltip('Batalkan Pembayaran'), findsOneWidget);
  });
}
