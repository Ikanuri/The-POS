import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 63 — bug finansial/administrasi serius, sama kelasnya dgn Item 62
/// tapi di level BARIS `transaction_items` (bukan header `transactions`):
/// koreksi post-insert ke `qty`/`price_at_sale`/`subtotal` (retur, edit
/// item, DP pre-order, dll) tidak pernah tersinkron ke device lain begitu
/// baris itu sudah pernah tersinkron sekali (`dumpSince` tidak filter
/// berdasarkan koreksi, `mergeRows` SKIP baris yg PK-nya sudah ada). Dampak
/// nyata: `reconcileTransactionsByIds` pasca-merge merekonstruksi `total`
/// dari copy STALE `transaction_items` milik klien, sementara `paid` sudah
/// benar (dari `transaction_payments` yang memang ikut sync) -> `paid >
/// total`, kembalian/"lebih bayar" hantu di device klien.
void main() {
  Future<AppDatabase> seedHostWithPreorderTx() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Tabung Gas'));
    // `created_at` sengaja dibuat LAMA (bukan "now") supaya klausa
    // `transaction_id IN (SELECT id FROM transactions WHERE created_at >=
    // ?)` di `dumpSince` (join lewat parent, bukan mekanisme yang sedang
    // diuji) TIDAK ikut membuat baris ini lolos dump kedua secara
    // kebetulan — kalau tidak, test ini bisa "lolos" walau fix `updated_at`
    // belum ada sama sekali (persis gotcha yang sama di
    // `transaction_updated_at_sync_test.dart`/Item 62).
    final createdAt = DateTime.now().subtract(const Duration(days: 3));
    // Nota "lunas" (item lain sudah bayar penuh) tapi item LPG dikunci Rp 0
    // (jaminan pre-order belum dibayar) — persis pola
    // `preorder_deposit_payment_test.dart`.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(createdAt),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti_lain',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti_lpg',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U2',
          qty: 2,
          priceAtSale: 0,
          originalPrice: 15000,
          subtotal: 0,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 30000, method: 'tunai'));
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U2',
        customerName: 'Umum',
        qtyOrdered: 2,
        transactionId: 'tx1',
        transactionItemId: 'ti_lpg');
    return db;
  }

  test(
      'DP pre-order dikumpulkan SETELAH sync pertama -> sync ulang -> '
      'device lain melihat harga terkoreksi & tidak ada kembalian hantu',
      () async {
    final hostDb = await seedHostWithPreorderTx();
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Sync PERTAMA: klien terima nota apa adanya (ti_lpg masih Rp0).
    final firstDump = await hostDb.dumpSince(DateTime(2000));
    await clientDb.mergeRows(
        'transactions', firstDump['transactions']!, true);
    await clientDb.mergeRows(
        'transaction_items', firstDump['transaction_items']!, true);
    await clientDb.mergeRows(
        'transaction_payments', firstDump['transaction_payments']!, true);
    await clientDb.reconcileTransactionsByIds({'tx1'});

    var clientItem = await (clientDb.select(clientDb.transactionItems)
          ..where((t) => t.id.equals('ti_lpg')))
        .getSingle();
    expect(clientItem.priceAtSale, 0,
        reason: 'prakondisi: klien masih punya copy Rp0 (stale)');

    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Owner kumpulkan DP di HOST — SETELAH baris ini sudah pernah
    // tersinkron sekali.
    final owed = await hostDb.collectPreorderDeposit(
        preorderEntryId: 'po1', amount: 30000, method: 'tunai', kasirId: 'K1');
    expect(owed, 30000);
    final hostItem = await (hostDb.select(hostDb.transactionItems)
          ..where((t) => t.id.equals('ti_lpg')))
        .getSingle();
    expect(hostItem.priceAtSale, 15000);
    expect(hostItem.subtotal, 30000);

    // Sync KEDUA: klien minta data sejak watermark (setelah sync pertama,
    // sebelum DP barusan dikumpulkan).
    final secondDump = await hostDb.dumpSince(clientWatermark);
    final itemsDump = secondDump['transaction_items'] ?? const [];
    expect(itemsDump.any((r) => r['id'] == 'ti_lpg'), isTrue,
        reason: 'tanpa fix (1): koreksi post-insert ti_lpg tidak pernah '
            'ikut dump kedua (parent created_at & added_at baris ini '
            'sudah lewat watermark, tidak ada updated_at sbg fallback)');

    // `transaction_payments` tidak terdampak bug ini (append-only murni,
    // baris DP baru punya paid_at baru) — mestinya sudah ikut apa adanya.
    final paymentsDump = secondDump['transaction_payments'] ?? const [];
    expect(paymentsDump.any((r) => r['transaction_id'] == 'tx1'), isTrue);

    await clientDb.mergeRows('transaction_items', itemsDump, true);
    await clientDb.mergeRows('transaction_payments', paymentsDump, true);

    clientItem = await (clientDb.select(clientDb.transactionItems)
          ..where((t) => t.id.equals('ti_lpg')))
        .getSingle();
    expect(clientItem.priceAtSale, 15000,
        reason: 'tanpa fix (2): mergeRows SKIP baris yang PK-nya sudah '
            'ada (append-only), jadi koreksi harga tidak pernah sampai '
            'walau baris itu berhasil ikut dump');
    expect(clientItem.subtotal, 30000);

    // Jalankan rekonsiliasi pasca-merge sungguhan, sama seperti pipeline
    // sync asli (`LanSyncService`/`app_database.dart`).
    await clientDb.reconcileTransactionsByIds({'tx1'});

    final clientTx = await (clientDb.select(clientDb.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(clientTx.paid <= clientTx.total, isTrue,
        reason: 'tanpa fix, klien merekonstruksi total dari copy STALE '
            'transaction_items (Rp0) sementara paid sudah benar dari '
            'transaction_payments yg tersinkron -> paid > total, '
            'kembalian/lebih-bayar hantu');
    expect(clientTx.total, 60000);
    expect(clientTx.paid, 60000);
  });
}
