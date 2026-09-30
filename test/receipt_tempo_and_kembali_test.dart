import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/change_display.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user: "ketika ada tempo dan kembalian, maka jumlah tempo
/// tidak muncul di print struk" — baris "Kembali" & "Sisa" (tempo) di struk
/// gambar (`_ReceiptPaper`, dibuka lewat "Bagikan Struk") SEBELUMNYA
/// if/else-if (saling meniadakan). Skenario nyata: nota sempat dibayar
/// LEBIH dari cukup (menghasilkan kembalian pada pembayaran itu), TAPI
/// kemudian ada tambahan barang ("Tambah Belanjaan") yang menaikkan total
/// lagi — nota kembali berstatus kurang_bayar/tempo, TAPI kembalian dari
/// pembayaran sebelumnya tetap ada di riwayat & harus tetap dilaporkan.
/// Ringkasan on-screen (`isKurangBayar` + `_ChangeTakenRow`) sudah benar
/// pakai 2 kondisi independen sejak awal; struk gambar-lah yang menyimpang.
///
/// Item 88 (aturan "last state", permintaan user): nota yang masih kurang
/// cuma menampilkan Sisa. Kembalian lama yang BELUM diambil tidak hilang —
/// kasir menampilkannya lewat tombol "Gabungkan kembalian belum diambil",
/// lalu struk share memuat "Kembali (gabungan)" BERSAMA Sisa.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'nota kurang_bayar dgn kembalian lama belum diambil: default Sisa '
      'saja; tombol gabung -> Kembali (gabungan) DAN Sisa bersamaan',
      (tester) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'kurang_bayar',
          total: 50000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));

    // Bayar 60.000 utk nota 50.000 -> kembalian 10.000, nota jadi LUNAS.
    await db.addPaymentToTransaction(
        txId: txId, amount: 60000, method: 'tunai', kasirId: 'K1');

    var tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.status, 'lunas', reason: 'sanity check pembayaran awal');

    // Tambah belanjaan 30.000 (total jadi 80.000) TANPA pembayaran baru ->
    // nota kembali kurang_bayar, tapi kembalian dari pembayaran pertama
    // (10.000) tetap tercatat di riwayat.
    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
            id: 'i1',
            transactionId: txId,
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 30000,
            originalPrice: 30000,
            subtotal: 30000),
      ],
      stockItems: const [],
    );

    tx = await (db.select(db.transactions)..where((t) => t.id.equals(txId)))
        .getSingle();
    // Sanity check angka skenario sebelum verifikasi UI.
    expect(tx.total, 80000);
    expect(tx.status, 'kurang_bayar',
        reason: 'nota kembali menagih setelah total naik lagi');
    final payments = await db.getPaymentsForTx(txId);
    expect(lastStateChange(tx, payments), 0,
        reason: 'last state nota kurang: tanpa Kembali');
    expect(unclaimedChangeTotal(payments), 10000,
        reason: 'kembalian pembayaran pertama belum diambil');
    expect(hasExtraUnclaimedChange(tx, payments), isTrue);
    expect(netRemainingOwed(tx, payments), 30000,
        reason: '80.000 - 60.000 dibayar + 10.000 kembalian = 30.000 sisa');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    // Default (last state): Sisa saja.
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();
    expect(find.text('Kembali'), findsNothing);
    expect(find.text('Sisa'), findsWidgets);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Gabungkan kembalian belum diambil'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(find.text('Kembali (gabungan)'), findsOneWidget,
        reason: 'kembalian lama yg belum diambil tetap bisa dilaporkan');
    expect(find.text('Sisa'), findsWidgets,
        reason: 'tempo/sisa yang masih nyata harus tetap tampil');
    expect(find.text('Rp ${_fmt(30000)}'), findsWidgets,
        reason: 'nominal sisa tagihan yang benar');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}

String _fmt(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
