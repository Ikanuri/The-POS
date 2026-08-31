import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug ditemukan saat review logika retur/kembalian (permintaan user),
/// skenario retur → tambah belanjaan → retur berkali-kali: kalau produk yang
/// sama tersebar di >1 baris nota (baris asli + baris "Tambahan" dari sesi
/// Tambah Belanjaan) dan sudah pernah ada retur sebagian, sheet Retur
/// sebelumnya mengurangi `alreadyReturned` dari qty MASING-MASING baris
/// secara independen — total yang bisa dipilih dalam SATU sesi buka-sheet
/// jadi lebih kecil dari sisa sebenarnya (mis. sisa asli 7, tapi UI cuma
/// izinkan 4). Sekarang harus jadi pool BERSAMA yang menyusut dinamis antar
/// baris saat qty baris lain dinaikkan.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  Finder inSheet(String text) =>
      find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 100000,
          paid: 100000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Galon Air'));
    // Baris ASLI: beli 5.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti-asli',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 5,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 50000));
    // Baris TAMBAHAN (dari sesi Tambah Belanjaan): beli 5 lagi, unit SAMA.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti-tambahan',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 5,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 50000,
        addedAt: Value(DateTime.now())));
    // Sudah pernah diretur 3 (baris retur lama, qty negatif) — sisa
    // sebenarnya = (5+5) - 3 = 7.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'ti-retur-lama',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: -3,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: -30000,
        returnedAt: Value(DateTime.now())));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: txId, amount: 100000, method: 'tunai'));
  });
  tearDown(() async => db.close());

  testWidgets(
      'sisa returnable adalah POOL BERSAMA (7) — bisa dipilih penuh lintas '
      '2 baris dalam SATU sesi sheet, bukan cuma 4 (2+2 independen)',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byIcon(Icons.assignment_return_outlined));
    await tester.pumpAndSettle();

    // Awal: kedua baris sama-sama tampil "Maks 5" (pool 7 diklem ke qty
    // baris masing-masing, 5), BUKAN "Maks 2" (bug lama: 5 - 3 per baris).
    expect(inSheet('Maks 5 · ${formatRupiah(10000)}'), findsNWidgets(2));

    final qtyFields = find.descendant(
        of: find.byType(BottomSheet), matching: find.byType(TextField));
    expect(qtyFields, findsNWidgets(2));

    // Isi baris pertama (asli) dgn 5 (maksimalnya).
    await tester.enterText(qtyFields.at(0), '5');
    await tester.pumpAndSettle();

    // Baris KEDUA (tambahan) harus menyusut ke "Maks 2" (pool 7 - 5 yang
    // sudah dipilih baris pertama) — INI bukti pool bersama bekerja, bukan
    // independen (kalau independen, tetap "Maks 5").
    expect(inSheet('Maks 2 · ${formatRupiah(10000)}'), findsOneWidget,
        reason: 'baris kedua harus ikut menyusut begitu baris pertama '
            'mengambil sebagian pool bersama');

    // Isi baris kedua dgn SISA penuhnya (2) — total 5+2=7, PERSIS sisa
    // sebenarnya (5+5-3), bukan cuma 4 spt bug lama.
    await tester.enterText(qtyFields.at(1), '2');
    await tester.pumpAndSettle();

    // Total refund = 7 x Rp 10.000 = Rp 70.000.
    expect(inSheet(formatRupiah(70000)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
