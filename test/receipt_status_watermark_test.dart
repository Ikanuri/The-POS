import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/status_watermark_stamp.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 29 (PLAN.md) — redesign header struk: header status besar
/// "Transaksi Berhasil/Tempo" dihapus, diganti watermark stempel SAMAR di
/// belakang baris item (bukan elemen mengambang yg bisa menutupi nama/harga
/// produk). Desain final disepakati user lewat beberapa putaran mockup.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx({required String status, required int paid}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: status,
          total: 30000,
          paid: paid,
          changeAmount: 0,
          paymentMethod: status == 'tempo' ? 'tempo' : 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ));
    if (paid > 0) {
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1',
              transactionId: 'tx1',
              amount: paid,
              method: status == 'tempo' ? 'tempo' : 'tunai'));
    }
  }

  testWidgets(
      'transaksi LUNAS → watermark stempel hijau "LUNAS", header status '
      'lama tidak ada lagi', (tester) async {
    await seedTx(status: 'lunas', paid: 30000);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Transaksi Berhasil'), findsNothing,
        reason: 'header status besar lama harus sudah dihapus');

    final stamp =
        tester.widget<StatusWatermarkStamp>(find.byType(StatusWatermarkStamp));
    expect(stamp.label, 'LUNAS');
    expect(stamp.serial, 'K1-1');
    expect(stamp.color, AppTheme.payGreen);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'transaksi TEMPO → watermark stempel merah "TEMPO", header status '
      'lama tidak ada lagi', (tester) async {
    await seedTx(status: 'tempo', paid: 0);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Transaksi Tempo'), findsNothing,
        reason: 'header status besar lama harus sudah dihapus');

    final stamp =
        tester.widget<StatusWatermarkStamp>(find.byType(StatusWatermarkStamp));
    expect(stamp.label, 'TEMPO');
    expect(stamp.serial, 'K1-1');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
