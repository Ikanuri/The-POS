import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: "Catatan di Struk" (setelan `receipt_note` di
/// Informasi Toko) DISIMPAN tapi TIDAK PERNAH dibaca — struk share selalu
/// menampilkan "Terima kasih!" hardcode, mengabaikan setelan user sama
/// sekali.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx() async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 20000,
        originalPrice: 20000,
        subtotal: 20000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 20000, method: 'tunai'));
  }

  testWidgets(
      '"Catatan di Struk" custom tampil di struk share, MENGGANTIKAN '
      '"Terima kasih!" default', (tester) async {
    await seedTx();
    await db.setSetting('receipt_note', 'Barang tidak bisa ditukar');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(find.text('Barang tidak bisa ditukar'), findsOneWidget,
        reason: 'setelan Catatan di Struk harus benar-benar tampil');
    expect(find.text('Terima kasih!'), findsNothing,
        reason: 'default lama tidak boleh tampil kalau user sudah isi '
            'catatan custom');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tanpa "Catatan di Struk" (belum diisi user) → tetap fallback ke '
      '"Terima kasih!"', (tester) async {
    await seedTx();
    // receipt_note SENGAJA tidak diisi.

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(find.text('Terima kasih!'), findsOneWidget,
        reason: 'fallback default harus tetap ada bila setelan kosong');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
