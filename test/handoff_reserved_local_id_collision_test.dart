import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug NYATA dilaporkan user (screenshot layar Pembayaran): pesanan
/// dipindah owner -> asisten via QR, lalu dikembalikan asisten -> owner via
/// QR; saat checkout muncul
/// `SqliteException(2067): UNIQUE constraint failed: transactions.local_id`
/// dan transaksi TIDAK BISA diselesaikan sama sekali (kasir mentok padahal
/// uang sudah diterima).
///
/// Akar: nomor nota yang dibawa QR cuma disimpan di `CartMeta.
/// reservedLocalId` (JSON keranjang) TANPA pernah dicatat ke
/// `reserved_order_numbers` device penerima. Akibatnya `reserveLocalId`
/// berikutnya di device itu tidak tahu nomor tsb sedang dipakai dan
/// membagikannya LAGI ke keranjang lain; begitu keranjang lain checkout
/// duluan, nomornya jadi milik `transactions` dan keranjang hasil transfer
/// menabrak UNIQUE saat gilirannya bayar.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> checkout(String localId) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-$localId',
          localId: localId,
          status: 'lunas',
          total: 1000,
          paid: 1000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.releaseLocalId(localId);
  }

  test(
      'nomor nota bawaan QR yang di-adopt TIDAK dibagikan lagi ke keranjang '
      'lain di device penerima', () async {
    // Device pengirim mereservasi nomor, lalu transfer via QR (nomor ikut
    // terbawa & reservasi di pengirim dilepas saat keranjangnya dikosongkan).
    final dikirim = await db.reserveLocalId('A1');
    await db.releaseLocalId(dikirim);

    // Device penerima meng-adopt nomor bawaan itu.
    await db.adoptReservedLocalId(dikirim);

    // Keranjang BARU di device penerima minta nomor — TIDAK BOLEH dapat
    // nomor yang sama.
    final baru = await db.reserveLocalId('A1');
    expect(baru, isNot(dikirim),
        reason: 'nomor bawaan QR sudah di-adopt, tidak boleh dibagikan lagi');
  });

  test(
      'skenario user PERSIS: transfer bolak-balik lalu keranjang lain '
      'checkout duluan -> nomor reservasi basi TIDAK menggagalkan checkout',
      () async {
    // Owner reservasi nomor utk pesanan bu Artia.
    final nomorArtia = await db.reserveLocalId('A1');

    // Transfer owner -> asisten (keranjang owner dikosongkan, reservasi
    // dilepas), lalu asisten -> owner lagi. Tanpa adopt, nomor jadi "bebas".
    await db.releaseLocalId(nomorArtia);

    // Owner melayani pelanggan LAIN dulu; tanpa fix, nomor bebas itu
    // dibagikan ulang & langsung dikonsumsi jadi transaksi sungguhan.
    final nomorLain = await db.reserveLocalId('A1');
    await checkout(nomorLain);

    // Sekarang giliran pesanan bu Artia dibayar. Nomor lamanya mungkin
    // sudah basi — checkout WAJIB tetap bisa jalan (fallback nomor bebas),
    // bukan gagal total spt bug yang dilaporkan.
    final basi = await db.isLocalIdTaken(nomorArtia);
    final localIdDipakai =
        basi ? await db.generateUniqueLocalId('A1') : nomorArtia;

    // Tidak boleh melempar apa pun (dulu: SqliteException 2067).
    await checkout(localIdDipakai);

    final semua = await db.select(db.transactions).get();
    expect(semua, hasLength(2),
        reason: 'kedua nota tersimpan, tidak ada penjualan yang gagal');
    expect(semua.map((t) => t.localId).toSet(), hasLength(2),
        reason: 'nomor nota tetap unik');
  });

  test('adoptReservedLocalId idempoten (QR yang sama di-scan berkali-kali)',
      () async {
    await db.adoptReservedLocalId('A1-20260727-0015');
    await db.adoptReservedLocalId('A1-20260727-0015');
    final rows = await db.select(db.reservedOrderNumbers).get();
    expect(rows, hasLength(1));
  });

  test('isLocalIdTaken: true hanya kalau sudah jadi transaksi sungguhan',
      () async {
    final nomor = await db.reserveLocalId('A1');
    expect(await db.isLocalIdTaken(nomor), isFalse,
        reason: 'baru direservasi, belum jadi transaksi');
    await checkout(nomor);
    expect(await db.isLocalIdTaken(nomor), isTrue);
  });
}
