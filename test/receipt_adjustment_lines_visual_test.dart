import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Penyesuaian visual diminta user (14 Agt 2026, screenshot) untuk blok
/// rincian retur/edit di kartu "Riwayat Pembayaran" in-app:
/// 1. "Rp 0" di baris penanda retur/edit disembunyikan (nilainya selalu 0,
///    nilai sungguhan ada di header "(Retur) Rp X" di bawahnya).
/// 2. Nominal di header "(Retur) Rp X" BOLD, sisanya normal.
/// 3. Baris "qty satuan x harga = total" TIDAK bold (sebelumnya bold).
/// 4. Ada tanda "=" sebelum nominal total per baris produk.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'baris penanda retur: "Rp 0" disembunyikan, header bold, baris qty '
      'pakai "=" dan TIDAK bold', (tester) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 58200,
          paid: 635000,
          changeAmount: 576800,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'p1',
          productUnitId: 'u1',
          qty: 1,
          priceAtSale: 58200,
          originalPrice: 58200,
          subtotal: 58200,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: 'pay0',
          transactionId: 'tx1',
          amount: 635000,
          method: 'tunai',
          paidAt: Value(DateTime(2026, 8, 14, 10, 41)),
          changeGiven: const Value(576800),
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
          id: 'pay1',
          transactionId: 'tx1',
          amount: 0,
          method: 'retur',
          paidAt: Value(DateTime(2026, 8, 14, 10, 41)),
          note: const Value('Retur barang (nota belum lunas)'),
        ));
    await db.into(db.transactionAdjustmentLines).insert(
        TransactionAdjustmentLinesCompanion.insert(
          id: 'l1',
          paymentId: 'pay1',
          transactionId: 'tx1',
          productId: 'p1',
          productUnitId: 'u1',
          productName: '234 12',
          unitName: 'Slop',
          qty: 3,
          priceAtSale: 193000,
          subtotal: 579000,
        ));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    // "Rp 0" tidak ditampilkan sama sekali di kartu Riwayat Pembayaran.
    expect(find.text(formatRupiah(0)), findsNothing);

    // Baris qty pakai tanda "=" dan TIDAK bold.
    final qtyLineFinder =
        find.text('3 Slop x ${formatRupiah(193000)} = ${formatRupiah(579000)}');
    expect(qtyLineFinder, findsOneWidget);
    final qtyLineStyle = tester.widget<Text>(qtyLineFinder).style;
    expect(qtyLineStyle?.fontWeight, isNot(FontWeight.w700),
        reason: 'baris qty x harga = total TIDAK boleh bold');

    // Header "(Retur) Rp X" — nominalnya bold, dirender via Text.rich.
    final headerFinder = find.byWidgetPredicate((w) =>
        w is Text &&
        w.textSpan != null &&
        (w.textSpan!.toPlainText()).contains('(Retur) ${formatRupiah(579000)}'));
    expect(headerFinder, findsOneWidget);
    final headerSpan = tester.widget<Text>(headerFinder).textSpan as TextSpan;
    final amountSpan = headerSpan.children!.firstWhere(
        (s) => (s as TextSpan).text == formatRupiah(579000)) as TextSpan;
    expect(amountSpan.style?.fontWeight, FontWeight.w700,
        reason: 'nominal retur di header WAJIB bold');
  });
}
