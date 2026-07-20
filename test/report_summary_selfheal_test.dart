import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug dilaporkan user: transaksi asisten sudah ter-merge & SAMA di kedua HP,
/// tapi Laporan Ringkasan owner (filter 19 Jun) hanya menampilkan 2jt padahal
/// asisten (data identik) menampilkan 8jt. Sebab: Ringkasan membaca cache
/// `daily_summaries` (tidak disinkron, dihitung ulang lokal). Bila transaksi
/// masuk lewat merge tapi cache tak ikut ter-rebuild, angka jadi basi.
/// Fix: `rebuildStaleSummariesInRange` mendeteksi & membangun ulang entri basi
/// sebelum laporan dibaca.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final d19 = DateTime(2026, 6, 19);

  Future<void> insertTx(String id, int total) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id.toUpperCase(),
          status: 'lunas',
          total: total,
          paid: total,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(2026, 6, 19, 10, 0)),
        ));
  }

  test(
      'ringkasan basi setelah merge → rebuildStaleSummariesInRange '
      'memperbaikinya jadi total sebenarnya', () async {
    // Owner mula-mula punya 1 transaksi 19 Jun (2jt) + ringkasan yg benar.
    await insertTx('o1', 2000000);
    await db.rebuildSummariesForTxIds({'o1'});
    expect((await db.getDailySummaries(d19, d19)).single.omzet, 2000000,
        reason: 'prasyarat: ringkasan awal owner 2jt');

    // Transaksi asisten (6jt) MASUK via merge TAPI cache ringkasan TIDAK
    // ter-rebuild (simulasi jalur merge yg terlewat / build lama).
    await insertTx('a1', 6000000);

    // Gejala: Ringkasan masih basi (2jt), bukan 8jt — walau transaksi sudah ada.
    final stale = await db.getDailySummaries(d19, d19);
    expect(stale.single.omzet, 2000000,
        reason: 'membuktikan cache basi: transaksi 8jt tapi ringkasan 2jt');
    expect(stale.single.jumlahTransaksi, 1);

    // Fix: perbaiki-sendiri untuk rentang yang dilihat laporan.
    await db.rebuildStaleSummariesInRange(d19, d19);

    final healed = await db.getDailySummaries(d19, d19);
    expect(healed.single.omzet, 8000000,
        reason: 'ringkasan harus jadi 8jt (2jt owner + 6jt asisten)');
    expect(healed.single.jumlahTransaksi, 2);
  });

  test('tanggal di luar rentang tidak ikut dibangun ulang', () async {
    await insertTx('o1', 2000000);
    await db.rebuildSummariesForTxIds({'o1'});
    // Rentang berbeda (18 Jun) — tidak menyentuh 19 Jun.
    await db.rebuildStaleSummariesInRange(
        DateTime(2026, 6, 18), DateTime(2026, 6, 18));
    expect((await db.getDailySummaries(d19, d19)).single.omzet, 2000000);
  });
}
