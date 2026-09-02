import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Laporan user: kartu Pre-order di nota menampilkan event "Diubah" tapi
/// TIDAK menampilkan APA yang diubah (ringkasan perubahan tersimpan di
/// `note` event, mis. "jumlah 1 -> 2, jaminan 1 -> 2") maupun SIAPA/device
/// mana yang mengubah (`deviceCode`). Sekarang keduanya dirender di
/// `_laciMejaEntryBlock` utk semua jenis event.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'A1-1',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P0', name: 'Gas LPG 3kg'));
    await db
        .into(db.productUnits)
        .insert(ProductUnitsCompanion.insert(id: 'U0', productId: 'P0'));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 20000,
        originalPrice: 20000,
        subtotal: 20000));
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'P0',
        productUnitId: 'U0',
        customerName: 'Ari',
        qtyOrdered: 1,
        depositQty: 1,
        transactionId: txId,
        transactionItemId: 'i0');
  });
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'event "Diubah" menampilkan ringkasan perubahan (note) + kode device '
      'pelaku', (tester) async {
    await db.editPreorderEntry('p1',
        qtyOrdered: 2,
        depositQty: 2,
        changeSummary: 'jumlah 1 -> 2, jaminan 1 -> 2',
        deviceCode: 'A1',
        eventId: 'ev-edit');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Diubah · A1'), findsOneWidget,
        reason: 'kode device pelaku ikut label aksi');
    expect(find.text('jumlah 1 -> 2, jaminan 1 -> 2'), findsOneWidget,
        reason: 'rincian perubahan (note event) harus terlihat owner');

    await drain(tester);
  });

  testWidgets('event lain (Dipenuhi) juga menampilkan kode device',
      (tester) async {
    await db.fulfillPreorderQty('p1', 1, eventId: 'ev-full', deviceCode: 'O1');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Dipenuhi · O1'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('event tanpa deviceCode/note (data lama) -> label polos, tidak ada '
      'baris kosong', (tester) async {
    await db.fulfillPreorderQty('p1', 1, eventId: 'ev-old');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    expect(find.text('Dipenuhi'), findsOneWidget);
    expect(find.textContaining('Dipenuhi ·'), findsNothing);

    await drain(tester);
  });
}
