import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug ditemukan user (lihat percakapan): "Sisa Tagihan" understated saat
/// kembalian yang sudah pernah diberikan dipakai ulang sebagai pembayaran
/// baru — uang yang sama ke-hitung dobel di `paid` (masuk lagi sbg
/// pembayaran baru) tanpa pernah dikurangi saat keluar sbg kembalian
/// sebelumnya. Fix: status ('kurang_bayar'/'lunas') dihitung dari `paid`
/// dikurangi TOTAL kembalian yang pernah tercatat, bukan `paid` mentah.
/// `paid`/`changeAmount` yang TERSIMPAN sengaja dibiarkan mentah (dipakai
/// struk cetak "Bayar../Kembali" apa adanya).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test(
      'addItemsToTransaction: status TETAP kurang_bayar (bukan lunas) saat '
      'kembalian lama dipakai ulang sbg pembayaran item tambahan — kasus '
      'persis dari laporan user (total 38.700 -> bayar 40.000 -> kembalian '
      '1.300 -> tambah item 19.400 -> bayar lagi 1.300 dari kembalian tadi)',
      () async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'lunas',
          total: 38700,
          paid: 40000,
          changeAmount: 1300,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 38700,
        originalPrice: 38700,
        subtotal: 38700));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 40000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 7, 12, 6, 33)),
            changeGiven: const Value(1300)));

    // Tambah item 19.400 + bayar 1.300 (reuse kembalian pay1).
    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
            id: 'i1',
            transactionId: txId,
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 19400,
            originalPrice: 19400,
            subtotal: 19400),
      ],
      stockItems: const [],
      payment: TransactionPaymentsCompanion.insert(
        id: 'pay2',
        transactionId: txId,
        amount: 1300,
        method: 'tunai',
        paidAt: Value(DateTime(2026, 7, 12, 6, 34)),
      ),
      kasirId: 'K1',
    );

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.total, 58100);
    expect(tx.paid, 41300, reason: 'paid mentah tetap Σamount (utk struk)');
    expect(tx.status, 'kurang_bayar',
        reason: 'net paid (41300-1300=40000) < total (58100)');

    final payments = await db.getPaymentsForTx(txId);
    final sumChangeGiven =
        payments.fold<int>(0, (s, p) => s + p.changeGiven);
    final netRemaining = tx.total - tx.paid + sumChangeGiven;
    expect(netRemaining, 18100,
        reason: 'sama persis dengan aplikasi pembanding di laporan user');
  });

  test(
      'addItemsToTransaction: status TETAP kurang_bayar (bukan salah jadi '
      'lunas) saat paid mentah >= total padahal net paid masih kurang — '
      'membedakan dari kasus lain di mana gross & net kebetulan sama-sama '
      'kurang_bayar', () async {
    const txId = 'tx3';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'lunas',
          total: 10000,
          paid: 11000,
          changeAmount: 1000,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 11000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 7, 12, 6, 33)),
            changeGiven: const Value(1000)));

    // Tambah item 1000 (total jadi 11000), bayar cuma 999 (reuse kembalian
    // tapi kurang 1). Paid mentah: 11000+999=11999 >= total(11000) ->
    // KELIHATAN lunas kalau dihitung mentah. Net: 11999-1000=10999 <
    // 11000 -> HARUS tetap kurang_bayar.
    await db.addItemsToTransaction(
      txId: txId,
      items: [
        TransactionItemsCompanion.insert(
            id: 'i1',
            transactionId: txId,
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 1000,
            originalPrice: 1000,
            subtotal: 1000),
      ],
      stockItems: const [],
      payment: TransactionPaymentsCompanion.insert(
        id: 'pay2',
        transactionId: txId,
        amount: 999,
        method: 'tunai',
        paidAt: Value(DateTime(2026, 7, 12, 6, 34)),
      ),
      kasirId: 'K1',
    );

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.paid, 11999, reason: 'paid mentah tetap Σamount (utk struk)');
    expect(tx.status, 'kurang_bayar',
        reason: 'net paid (10999) masih < total (11000), walau paid mentah '
            '(11999) sudah >= total');
  });

  test(
      'addPaymentToTransaction: status kurang_bayar TIDAK berubah jadi lunas '
      'keliru saat paid mentah >= total tapi net paid masih kurang '
      '(kembalian lama dipakai ulang sampai pas menutup persis paid mentah)',
      () async {
    // Nota lunas dgn kembalian 1300 belum diambil (paid 40000, total 38700).
    const txId = 'tx2';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'lunas',
          total: 38700,
          paid: 40000,
          changeAmount: 1300,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 40000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 7, 12, 6, 33)),
            changeGiven: const Value(1300)));
    // Total naik ke 40000 (tambahan 1300) tanpa lewat addItemsToTransaction
    // (simulasi manual reconcile total, fokus test di addPaymentToTransaction).
    await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
        .write(const TransactionsCompanion(total: Value(40000)));

    // Bayar lagi 1300 (reuse persis) — paid mentah jadi 41300 >= total 40000
    // (KELIHATAN lunas kalau dihitung mentah), tapi net = 41300-1300=40000
    // == total PERSIS (bukan lebih) -> harus tetap lunas (pas, bukan salah
    // klasifikasi). Uji kasus SEDIKIT KURANG supaya benar-benar membuktikan
    // klasifikasi net, bukan kebetulan pas:
    await db.addPaymentToTransaction(
      txId: txId,
      amount: 1299, // kurang 1 dari yang dibutuhkan utk netral
      method: 'tunai',
      kasirId: 'K1',
    );

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    // paid mentah = 40000+1299 = 41299, MASIH >= total(40000) -> kalau
    // dihitung mentah harusnya "lunas". Net = 41299-1300=39999 < 40000
    // -> HARUS tetap kurang_bayar.
    expect(tx.paid, 41299);
    expect(tx.status, 'kurang_bayar',
        reason: 'net paid (39999) masih < total (40000), walau paid mentah '
            '(41299) sudah >= total');
  });
}
