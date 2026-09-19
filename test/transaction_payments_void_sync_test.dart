import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 81 — bug sync serius, sama kelasnya dgn Item 62/63 tapi di
/// `transaction_payments`: `voidPayment` ("Batalkan Pembayaran") meng-UPDATE
/// `voided` pada baris yang SUDAH ada setelah insert awal, TAPI tabel ini
/// sebelumnya diperlakukan append-only murni oleh `dumpSince` (filter
/// `WHERE paid_at >= ?`, TIDAK ada kolom timestamp lain) dan `mergeRows`
/// (skip total begitu PK sudah ada di sisi penerima). Dampak nyata:
/// pembayaran yang dibatalkan SETELAH baris itu tersinkron ke device lain
/// tidak pernah terkirim statusnya -- "Riwayat Pembayaran" di device lain
/// tetap menampilkan baris itu seolah masih aktif.
void main() {
  Future<AppDatabase> seedHostWithPaidTx() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Gula Pasir'));
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
    return db;
  }

  test(
      'pembayaran dibatalkan SETELAH baris itu tersinkron -> sync ulang -> '
      'device lain melihat voided=true, bukan baris hantu aktif selamanya',
      () async {
    final hostDb = await seedHostWithPaidTx();
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Sync PERTAMA: klien terima nota + pembayaran apa adanya (voided=false).
    final firstDump = await hostDb.dumpSince(DateTime(2000));
    await clientDb.mergeRows(
        'transactions', firstDump['transactions']!, true);
    await clientDb.mergeRows(
        'transaction_items', firstDump['transaction_items']!, true);
    await clientDb.mergeRows(
        'transaction_payments', firstDump['transaction_payments']!, true);

    var clientPay = await (clientDb.select(clientDb.transactionPayments)
          ..where((t) => t.id.equals('pay1')))
        .getSingle();
    expect(clientPay.voided, isFalse,
        reason: 'prakondisi: klien punya copy aktif (belum dibatalkan)');

    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Owner membatalkan pembayaran itu di HOST -- SETELAH baris ini sudah
    // pernah tersinkron sekali. `paid_at` baris ini TIDAK berubah.
    await hostDb.voidPayment('pay1');
    final hostPay = await (hostDb.select(hostDb.transactionPayments)
          ..where((t) => t.id.equals('pay1')))
        .getSingle();
    expect(hostPay.voided, isTrue);

    // Sync KEDUA: klien minta data sejak watermark (setelah sync pertama,
    // sebelum pembatalan barusan).
    final secondDump = await hostDb.dumpSince(clientWatermark);
    final paymentsDump = secondDump['transaction_payments'] ?? const [];
    expect(paymentsDump.any((r) => r['id'] == 'pay1'), isTrue,
        reason: 'tanpa fix (1): baris yang di-void tidak pernah ikut dump '
            'kedua (paid_at tidak berubah, sudah lewat watermark, tidak '
            'ada updated_at sbg fallback)');

    await clientDb.mergeRows('transaction_payments', paymentsDump, true);

    clientPay = await (clientDb.select(clientDb.transactionPayments)
          ..where((t) => t.id.equals('pay1')))
        .getSingle();
    expect(clientPay.voided, isTrue,
        reason: 'tanpa fix (2): mergeRows SKIP baris yang PK-nya sudah ada '
            '(append-only), jadi status voided tidak pernah sampai walau '
            'baris itu berhasil ikut dump');
  });
}
