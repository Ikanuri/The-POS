import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Revisi user — jumlah qty + satuan di baris item struk in-app dibuat bold
/// juga, TAPI tidak lebih tebal dari nama produk (nama = w700, qty+satuan =
/// w600). Bagian "x harga" tetap berat normal.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('qty+satuan bold (w600), tapi lebih tipis dari nama produk (w700)',
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

    // Baris qty = Text.rich → RichText yang plain-text-nya mengandung ' × '.
    final qtyRich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((rt) => rt.text.toPlainText().contains(' × '));

    // Telusuri pohon span, cari leaf yang teksnya diawali qty ('2').
    TextSpan? qtySpan;
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text != null && span.text!.trimLeft().startsWith('2')) {
          qtySpan ??= span;
        }
        span.children?.forEach(walk);
      }
    }

    walk(qtyRich.text);
    expect(qtySpan, isNotNull, reason: 'span qty+satuan harus ada');
    expect(qtySpan!.style?.fontWeight, FontWeight.w600,
        reason: 'qty+satuan bold w600');

    // Nama produk (fallback ke productId 'P1') tetap w700 — qty+satuan HARUS
    // lebih tipis (tidak lebih bold dari nama). Baris nama sekarang
    // `Text.rich` (Item 52 redesain, biar penanda Laci Meja/pre-order bisa
    // disambung rapat) — cari RichText yg plain-text-nya persis 'P1'.
    // `Text.rich` membungkus TextSpan yg diberikan sbg CHILD dari TextSpan
    // luar (gaya default) — style yg kita set ada di children.first.
    final nameRich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((rt) => rt.text.toPlainText() == 'P1');
    final ourNameSpan = (nameRich.text as TextSpan).children!.first as TextSpan;
    final nameWeight = ourNameSpan.style?.fontWeight ?? FontWeight.normal;
    expect(nameWeight, FontWeight.w700);
    expect(FontWeight.w600.index, lessThan(nameWeight.index),
        reason: 'qty+satuan tidak boleh lebih bold dari nama produk');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
