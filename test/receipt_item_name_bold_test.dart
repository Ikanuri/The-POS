import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: teks nama produk di baris item struk in-app dibuat bold.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('nama produk di baris item struk tampil BOLD (w700)',
      (tester) async {
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
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 30000, method: 'tunai'));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    // Tanpa produk di-seed ke tabel `products`, nama jatuh ke fallback
    // productId ('P1') — cukup utk menguji style, tidak perlu nama asli.
    // Baris nama sekarang `Text.rich` (bisa disambung penanda Laci Meja/
    // pre-order di span berikutnya) — cari RichText yg plain-text-nya 'P1'
    // lalu baca style span akar (nama tidak override style, ikut akar).
    // `Text.rich` selalu membungkus TextSpan yg diberikan sbg CHILD dari
    // TextSpan luar (gaya default) — style yg kita set ada di children.first,
    // bukan di .text.style langsung punya RichText.
    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((rt) => rt.text.toPlainText() == 'P1');
    final ourSpan = (richText.text as TextSpan).children!.first as TextSpan;
    expect(ourSpan.style?.fontWeight, FontWeight.w700,
        reason: 'nama produk di baris item harus bold');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
