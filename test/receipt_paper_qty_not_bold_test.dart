import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: di struk GAMBAR (_ReceiptPaper, tombol "Bagikan Struk"),
/// baris qty+satuan+harga TIDAK boleh bold — hanya nama produk yg tetap bold.
/// Sebelumnya baris ini pakai FontWeight.w600 (revisi lama, lihat
/// receipt_qty_unit_bold_test.dart utk versi in-app yg SENGAJA TIDAK
/// disentuh — user spesifik minta "struk share", bukan struk in-app).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'baris qty+satuan x harga di struk gambar TIDAK bold, nama produk '
      'tetap bold', (tester) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'Beras',
          productUnitId: 'U1',
          qty: 2,
          priceAtSale: 15000,
          originalPrice: 15000,
          subtotal: 30000,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 30000, method: 'tunai'));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    // Baris qty di struk gambar: "2 U1 x 15.000" — cari widget Text yang
    // mengandung ' x ' (bukan RichText lagi, sudah disederhanakan jadi Text
    // polos satu style).
    final qtyText = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => (t.data ?? '').contains(' x 15.000'));
    expect(qtyText.style?.fontWeight, isNot(FontWeight.w600),
        reason: 'qty+satuan+harga di struk share tidak boleh bold lagi');
    expect(qtyText.style?.fontWeight, isNot(FontWeight.w700));

    // Nama produk (di struk gambar, salinan .last) tetap bold w700.
    final nameText = tester.widget<Text>(find.text('Beras').last);
    expect(nameText.style?.fontWeight, FontWeight.w700,
        reason: 'nama produk tetap bold, tidak ikut berubah');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
