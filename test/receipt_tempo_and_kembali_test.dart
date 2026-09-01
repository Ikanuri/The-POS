import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
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
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'struk gambar (_ReceiptPaper) tampilkan Kembali DAN Sisa BERSAMAAN '
      'saat nota masih kurang_bayar tapi pembayaran sebelumnya sempat '
      'memberi kembalian', (tester) async {
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
    expect(latestChangeGiven(payments), 10000,
        reason: 'kembalian pembayaran pertama tetap ada di riwayat');
    expect(netRemainingOwed(tx, payments), 30000,
        reason: '80.000 - 60.000 dibayar + 10.000 kembalian = 30.000 sisa');

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    // KEDUA baris harus tampil bersamaan — ini bug-nya: sebelum fix, baris
    // "Sisa" hilang total krn if/else-if dgn baris "Kembali".
    expect(find.text('Kembali'), findsWidgets,
        reason: 'kembalian dari pembayaran sebelumnya tetap dilaporkan');
    expect(find.text('Sisa'), findsWidgets,
        reason: 'BUG: tempo/sisa yang masih nyata harus tetap tampil, '
            'bukan hilang gara-gara ada baris Kembali');
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
