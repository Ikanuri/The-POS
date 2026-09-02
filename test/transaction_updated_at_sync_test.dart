import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 62 — bug finansial/administrasi serius: tabel `transactions` TIDAK
/// PUNYA kolom `updated_at`, dan `dumpSince` memperlakukannya sbg
/// append-only murni (filter `WHERE created_at >= since` saja, sama seperti
/// `mergeRows` yang SKIP baris `transactions` yang PK-nya sudah ada di sisi
/// penerima). Begitu satu nota SUDAH pernah tersinkron sekali, perubahan
/// APA PUN ke baris `transactions` itu sendiri sesudahnya (status void,
/// ganti pelanggan, poin) TIDAK PERNAH terkirim lagi ke device lain —
/// laporan/omzet di device lain terus menghitungnya sbg data lama/valid.
///
/// Field total/paid/changeAmount KEBETULAN "aman" krn direkonstruksi ulang
/// dari `transaction_items`/`transaction_payments` (yang punya timestamp
/// sendiri & memang ikut sync) lewat `reconcileTransactionsByIds` pasca-
/// merge — TAPI `status`, `customer_name`/`customer_id`, `points_earned`
/// TIDAK bisa direkonstruksi dari tabel lain sama sekali.
void main() {
  Future<AppDatabase> seedHostWithOneTransaction() async {
    final db = AppDatabase(NativeDatabase.memory());
    final createdAt = DateTime.now().subtract(const Duration(days: 3));
    await db.saveTransaction(
      tx: TransactionsCompanion.insert(
        id: 'tx1',
        localId: 'K1-1',
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(createdAt),
      ),
      items: [
        TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 10000,
          originalPrice: 10000,
          subtotal: 10000,
        ),
      ],
      payments: [
        TransactionPaymentsCompanion.insert(
          id: 'p1',
          transactionId: 'tx1',
          amount: 10000,
          method: 'tunai',
          paidAt: Value(createdAt),
        ),
      ],
      stockItems: const [],
      now: createdAt,
    );
    return db;
  }

  test(
      'void SETELAH sync pertama -> sync ulang -> device lain melihat '
      'status void', () async {
    final hostDb = await seedHostWithOneTransaction();
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Sync PERTAMA: klien terima nota apa adanya (status lunas).
    final firstDump = await hostDb.dumpSince(DateTime(2000));
    await clientDb.mergeRows('transactions', firstDump['transactions']!, true);
    var row = await (clientDb.select(clientDb.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(row.status, 'lunas');

    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Owner VOID nota di host — SETELAH nota ini sudah pernah tersinkron.
    await hostDb.voidTransaction('tx1', 'K1');
    final hostRow = await (hostDb.select(hostDb.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(hostRow.status, 'void');

    // Sync KEDUA: klien minta data sejak watermark (setelah sync pertama,
    // sebelum void barusan).
    final secondDump = await hostDb.dumpSince(clientWatermark);
    final txDump = secondDump['transactions'] ?? const [];
    expect(txDump.any((r) => r['id'] == 'tx1'), isTrue,
        reason: 'tanpa fix, nota yang di-void SETELAH sync pertama tidak '
            'pernah ikut dump kedua (created_at sudah lewat watermark, dan '
            'updated_at belum ada sama sekali sbg fallback filter)');
    await clientDb.mergeRows('transactions', txDump, true);

    row = await (clientDb.select(clientDb.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(row.status, 'void',
        reason: 'tanpa fix, mergeRows SKIP baris yang PK-nya sudah ada '
            '(append-only), jadi status void tidak pernah sampai walau '
            'baris itu berhasil ikut dump');
  });

  test(
      'ganti nama pelanggan SETELAH sync pertama -> sync ulang -> device '
      'lain melihat nama baru', () async {
    final hostDb = await seedHostWithOneTransaction();
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final firstDump = await hostDb.dumpSince(DateTime(2000));
    await clientDb.mergeRows('transactions', firstDump['transactions']!, true);

    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    await hostDb.changeTransactionCustomer(
      txId: 'tx1',
      newCustomerId: null,
      newCustomerName: 'Budi Baru',
    );

    final secondDump = await hostDb.dumpSince(clientWatermark);
    final txDump = secondDump['transactions'] ?? const [];
    expect(txDump.any((r) => r['id'] == 'tx1'), isTrue,
        reason: 'perubahan customer_name harus ikut dump kedua');
    await clientDb.mergeRows('transactions', txDump, true);

    final row = await (clientDb.select(clientDb.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(row.customerName, 'Budi Baru');
  });
}
