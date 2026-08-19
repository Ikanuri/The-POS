import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug ditemukan lewat audit tab Ringkasan: `AppDatabase._paymentBucket`
/// dulu mencocokkan string 'transfer' — yang TIDAK PERNAH ada di data
/// nyata, karena `transactions.paymentMethod` untuk transfer bank
/// menyimpan 'bank' (lihat dropdown `payment_methods_screen.dart`).
/// Akibatnya SETIAP transaksi Transfer Bank jatuh ke bucket "lainnya" dan
/// `pembayaranTransfer` di `daily_summaries` selalu 0.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertTx(String id, String method, int total) => db
      .into(db.transactions)
      .insert(TransactionsCompanion.insert(
        id: id,
        localId: id,
        status: 'lunas',
        total: total,
        paid: total,
        changeAmount: 0,
        paymentMethod: method,
        createdAt: Value(DateTime(2026, 8, 18)),
      ));

  test(
      'transaksi bank masuk bucket pembayaranTransfer, BUKAN pembayaranLainnya',
      () async {
    await insertTx('tx1', 'bank', 50000);
    await insertTx('tx2', 'tunai', 20000);
    await insertTx('tx3', 'qris', 10000);
    await insertTx('tx4', 'ewallet', 5000);
    await insertTx('tx5', 'tempo', 7000);

    await db.rebuildStaleSummariesInRange(
        DateTime(2026, 8, 18), DateTime(2026, 8, 18));
    final summaries =
        await db.getDailySummaries(DateTime(2026, 8, 18), DateTime(2026, 8, 18));

    expect(summaries, hasLength(1));
    final s = summaries.single;
    expect(s.pembayaranTunai, 20000);
    expect(s.pembayaranQris, 10000);
    expect(s.pembayaranTransfer, 50000,
        reason: 'metode bank harus masuk bucket Transfer, bukan 0');
    expect(s.pembayaranLainnya, 12000,
        reason: 'ewallet (5000) + tempo (7000) = 12000, sesuai desain '
            '4-bucket (lihat dok DailySummaries)');
  });
}
