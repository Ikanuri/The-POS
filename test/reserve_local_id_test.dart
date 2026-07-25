import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 55 — nomor nota di-reserve LEBIH AWAL (sejak keranjang mulai
/// diisi/ditahan), bukan cuma saat checkout — supaya nomor tampil stabil
/// di cart bar & kartu pesanan tertahan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('reserveLocalId menghasilkan nomor berurutan & tidak bentrok', () async {
    final at = DateTime(2026, 7, 23);
    final a = await db.reserveLocalId('K1', at);
    final b = await db.reserveLocalId('K1', at);
    expect(a, 'K1-20260723-0001');
    expect(b, 'K1-20260723-0002');
  });

  test('reserveLocalId menghindari nomor yang sudah jadi transaksi nyata',
      () async {
    final at = DateTime(2026, 7, 23);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-20260723-0001',
          kasirId: const Value('K1'),
          status: 'lunas',
          total: 1000,
          paid: 1000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));

    final next = await db.reserveLocalId('K1', at);
    expect(next, 'K1-20260723-0002');
  });

  test('generateUniqueLocalId (dipakai checkout fallback) menghindari nomor '
      'yang SEDANG direservasi keranjang lain', () async {
    final at = DateTime(2026, 7, 23);
    await db.reserveLocalId('K1', at); // -> 0001, keranjang lain msh terbuka

    final checkoutId = await db.generateUniqueLocalId('K1', at);
    expect(checkoutId, 'K1-20260723-0002',
        reason: 'tidak boleh bentrok dgn reservasi keranjang lain yg '
            'belum checkout');
  });

  test('releaseLocalId melepas reservasi — nomor itu bisa dipakai lagi',
      () async {
    final at = DateTime(2026, 7, 23);
    final id = await db.reserveLocalId('K1', at); // 0001
    await db.releaseLocalId(id);

    final next = await db.reserveLocalId('K1', at);
    expect(next, 'K1-20260723-0001',
        reason: 'nomor yg dilepas boleh dipakai ulang');
  });

  test('reservasi tanggal berbeda tidak saling memengaruhi', () async {
    final d1 = await db.reserveLocalId('K1', DateTime(2026, 7, 23));
    final d2 = await db.reserveLocalId('K1', DateTime(2026, 7, 24));
    expect(d1, 'K1-20260723-0001');
    expect(d2, 'K1-20260724-0001');
  });
}
