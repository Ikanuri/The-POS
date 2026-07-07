import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Widget test yang benar-benar merender [ReceiptScreen] & mensimulasikan
/// tap tombol "Retur" — membuktikan redesign retur-nota-belum-lunas (Opsi A)
/// TAMPIL sesuai yang dimaksud, bukan cuma lolos test logika DB.
Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required String status,
    required int total,
    required int paid}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: status,
        total: total,
        paid: paid,
        changeAmount: 0,
        paymentMethod: status == 'tempo' ? 'tempo' : 'tunai',
      ));
}

Future<void> _insertItem(AppDatabase db,
    {required String id,
    required String transactionId,
    required int priceAtSale,
    double qty = 1}) async {
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: id,
        transactionId: transactionId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: qty,
        priceAtSale: priceAtSale,
        originalPrice: priceAtSale,
        subtotal: (priceAtSale * qty).round(),
      ));
}

void main() {
  testWidgets(
      'nota BELUM LUNAS: sheet retur menampilkan banner "mengurangi hutang", '
      'TANPA pilihan metode refund', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db,
        id: 'tx1', localId: 'K1-1', status: 'tempo', total: 15000, paid: 0);
    await _insertItem(db, id: 'ti1', transactionId: 'tx1', priceAtSale: 15000);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Retur'), findsOneWidget,
        reason: 'tombol Retur harus tampil untuk nota yang belum void');
    await tester.tap(find.text('Retur'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'Nota ini belum lunas — retur akan mengurangi hutang, bukan uang tunai kembali.'),
      findsOneWidget,
      reason: 'banner penjelasan wajib tampil untuk nota tempo/kurang_bayar',
    );
    expect(find.text('Kembalikan via'), findsNothing,
        reason:
            'nota belum lunas tidak boleh menawarkan pilihan refund tunai');
    expect(find.text('Total Dikurangi dari Hutang'), findsOneWidget);

    await db.close();
  });

  testWidgets(
      'nota SUDAH LUNAS: sheet retur menampilkan pilihan metode refund, '
      'TANPA banner hutang', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db,
        id: 'tx1', localId: 'K1-1', status: 'lunas', total: 15000, paid: 15000);
    await _insertItem(db, id: 'ti1', transactionId: 'tx1', priceAtSale: 15000);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    await tester.tap(find.text('Retur'));
    await tester.pumpAndSettle();

    expect(find.text('Kembalikan via'), findsOneWidget,
        reason: 'nota lunas tetap menawarkan pilihan metode refund (uang sudah berpindah)');
    expect(
      find.text(
          'Nota ini belum lunas — retur akan mengurangi hutang, bukan uang tunai kembali.'),
      findsNothing,
    );
    expect(find.text('Total Refund'), findsOneWidget);

    await db.close();
  });
}
