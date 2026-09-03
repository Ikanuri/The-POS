import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 57 — `laci_meja_events` tidak punya `updated_at`; delta host->klien
/// (`dumpSince`) HANYA pakai `created_at >= since` (waktu kejadian fisik,
/// tidak boleh diubah). Skenario bug: klien membuat event, upload sbg usulan,
/// lalu SEBELUM host sempat approve, klien sudah sync-download sekali lagi
/// dgn watermark yang sudah lewat dari `created_at` event itu — begitu host
/// AKHIRNYA approve, event itu TIDAK PERNAH lagi lolos filter delta ke sync
/// klien manapun, jadi `locally_modified` klien nyangkut 1 selamanya (event
/// yang sama diusulkan ulang tiap sync berikutnya, tanpa akhir).
///
/// Fix: kolom baru `applied_at` (dicap host saat `applyLaciMejaProposals`
/// menyetujui, BUKAN `created_at` yang tetap representasi waktu kejadian)
/// dipakai SEBAGAI TAMBAHAN filter delta `dumpSince`
/// (`created_at >= since OR applied_at >= since`).
void main() {
  late AppDatabase host;
  late AppDatabase client;

  Future<void> seedParent(AppDatabase db) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'A1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Payung',
        jenis: 'ketinggalan',
        qty: 1);
  }

  setUp(() async {
    host = AppDatabase(NativeDatabase.memory());
    client = AppDatabase(NativeDatabase.memory());
    await seedParent(host);
    await seedParent(client);
  });
  tearDown(() async {
    await host.close();
    await client.close();
  });

  test(
      'event dibuat klien, disetujui host SETELAH watermark sync klien lewat '
      '-> applied_at membawanya balik ke klien, locally_modified tereset',
      () async {
    // (a) Klien buat event, usulan (locally_modified = true). created_at =
    // waktu SEKARANG.
    await client.recordLaciMejaEvent(
      id: 'ev1',
      entityType: 'titip',
      entryId: 'l1',
      aksi: 'ambil',
      qty: 1,
      deviceCode: 'K1',
      locallyModified: true,
    );
    var clientRow = await (client.select(client.laciMejaEvents)
          ..where((t) => t.id.equals('ev1')))
        .getSingle();
    expect(clientRow.locallyModified, isTrue);

    // (b) Klien upload usulan -> host terima sbg PENDING (belum di-apply).
    final proposals = await client.dumpLaciMejaProposals();
    expect(proposals['laci_meja_events'], hasLength(1));

    // (c) Simulasikan klien SUDAH sync-download SEKALI LAGI sebelum host
    // approve, dgn watermark SETELAH created_at event ini -> event itu
    // TIDAK ikut (persis kondisi yang bikin bug asli terjadi).
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final clientWatermarkAfterCreate = DateTime.now();
    final dumpBeforeApprove =
        await host.dumpSince(clientWatermarkAfterCreate);
    expect(
        (dumpBeforeApprove['laci_meja_events'] ?? const [])
            .any((r) => r['id'] == 'ev1'),
        isFalse,
        reason: 'event belum disetujui host & watermark klien sudah lewat '
            'created_at-nya -> memang belum boleh ikut dump ini');

    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // (d) Host BARU approve sekarang.
    final result = await host.applyLaciMejaProposals(proposals, {
      'laci_meja_events': {'ev1'},
    });
    expect(result.applied, 1);
    final hostRow = await (host.select(host.laciMejaEvents)
          ..where((t) => t.id.equals('ev1')))
        .getSingle();
    expect(hostRow.appliedAt, isNotNull,
        reason: 'applied_at harus tercap saat host approve');
    expect(hostRow.appliedAt!.isAfter(hostRow.createdAt), isTrue,
        reason: 'applied_at (waktu approve) HARUS beda dari created_at '
            '(waktu kejadian asli) di skenario ini');

    // (e) Klien sync-download LAGI, watermark = SETELAH langkah (c) tapi
    // SEBELUM (d) -> dumpSince HARUS tetap mengembalikan event ini krn
    // applied_at >= since (walau created_at < since).
    final dumpAfterApprove = await host.dumpSince(clientWatermarkAfterCreate);
    final rows = dumpAfterApprove['laci_meja_events'] ?? const [];
    expect(rows.any((r) => r['id'] == 'ev1'), isTrue,
        reason: 'tanpa fix, event yang baru disetujui HOST tidak akan '
            'pernah lolos lagi karena created_at-nya sudah lewat watermark');

    await client.mergeRows('laci_meja_events', rows, false);
    clientRow = await (client.select(client.laciMejaEvents)
          ..where((t) => t.id.equals('ev1')))
        .getSingle();
    expect(clientRow.locallyModified, isFalse,
        reason: 'baris host (locally_modified=0) berhasil ter-merge balik, '
            'jadi klien TIDAK akan mengusulkan event ini lagi di sync '
            'berikutnya');
  });
}
