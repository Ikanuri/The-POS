import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 60 — `voidTransaction` sekarang ikut membatalkan (bukan menghapus)
/// entri Laci Meja yang tertaut ke nota yang di-void, DAN dites end-to-end
/// bahwa status batal itu benar-benar ikut sync ke device lain — bukan cuma
/// benar di DB host, sama pola `transaction_updated_at_sync_test.dart`/
/// `laci_meja_events_applied_at_sync_test.dart`.
///
/// Desain: `left_behind_items`/`borrowed_items` SENGAJA TIDAK dapat kolom
/// "batal" baru (lihat dok panjang di `voidTransaction`) — status
/// "disembunyikan dari dashboard" murni disimpulkan dari status
/// `transactions` induk lewat JOIN di `watchLeftBehindItems`/
/// `watchBorrowedItems`/`getLaciMejaPending`. Karena `transactions.status`+
/// `updated_at` SUDAH tersinkron dgn benar (Item 62), status batal Laci Meja
/// otomatis ikut begitu baris `transactions` yang di-void tersinkron ulang —
/// TANPA perlu menyinkron ulang baris `left_behind_items`/`borrowed_items`
/// itu sendiri sama sekali. Test ini membuktikan itu end-to-end.
///
/// `laci_meja_events` aksi='batal' (audit trail) SENGAJA TIDAK dites harus
/// tersinkron ke klien — filter `excludeVoidTx` yang SUDAH ADA sebelum Item
/// 60 (`73338c8`) mengecualikan baris Laci Meja (termasuk log event) milik
/// transaksi void dari dumpSince host->klien sama sekali. Audit trail-nya
/// cukup tersimpan di HOST (tempat void terjadi) — test ini membuktikan itu
/// juga, bukan cuma mengasumsikannya.
void main() {
  late AppDatabase host;
  late AppDatabase client;

  setUp(() async {
    host = AppDatabase(NativeDatabase.memory());
    client = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await host.close();
    await client.close();
  });

  test(
      'void nota berisi entri Laci Meja tertaut SETELAH sync pertama -> '
      'sync ulang -> device lain melihat status void nota MAUPUN status '
      'batal entri Laci Meja-nya', () async {
    // Seed di HOST: satu nota dgn satu entri "ketinggalan" (Titip/
    // Ketinggalan) & satu entri pinjaman, keduanya masih PENDING.
    await host.into(host.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'A1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await host.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Payung',
        jenis: 'ketinggalan',
        qty: 1,
        customerId: 'cust1',
        customerNameText: 'Budi');
    await host.addBorrowedItem(
        id: 'b1',
        transactionId: 'tx1',
        itemName: 'Galon',
        qty: 1,
        customerId: 'cust1',
        customerNameText: 'Budi');

    // Sync PERTAMA: klien terima nota + 2 entri Laci Meja apa adanya.
    final firstDump = await host.dumpSince(DateTime(2000));
    await client.mergeRows('transactions', firstDump['transactions']!, true);
    await client.mergeRows(
        'left_behind_items', firstDump['left_behind_items']!, true);
    await client.mergeRows('borrowed_items', firstDump['borrowed_items']!, true);

    // Sebelum void: kedua entri masih PENDING di klien (JOIN transaksi
    // induk yang statusnya masih 'lunas').
    var pendingBefore =
        await client.getLaciMejaPending(customerId: 'cust1');
    expect(pendingBefore.ketinggalan, 1);
    expect(pendingBefore.pinjaman, 1);

    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Owner VOID nota di HOST — SETELAH sync pertama.
    await host.voidTransaction('tx1', 'OWNER');

    final hostTx = await (host.select(host.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(hostTx.status, 'void');
    expect(hostTx.updatedAt!.isAfter(clientWatermark), isTrue,
        reason: 'Item 60 investigasi (a): voidTransaction WAJIB mencap '
            'updatedAt eksplisit ke transactions supaya status void ikut '
            'sync (pola Item 62)');

    // Event audit trail 'batal' HARUS tertulis utk kedua entri.
    final hostEvents = await (host.select(host.laciMejaEvents)
          ..where((t) => t.aksi.equals('batal')))
        .get();
    expect(hostEvents.map((e) => e.entryId).toSet(), {'l1', 'b1'});

    // Sync KEDUA: klien minta data sejak watermark.
    final secondDump = await host.dumpSince(clientWatermark);
    final txDelta = secondDump['transactions'] ?? const [];
    expect(txDelta.any((r) => r['id'] == 'tx1'), isTrue,
        reason: 'nota yang di-void SETELAH sync pertama harus ikut dump '
            'kedua (Item 62 — updated_at)');
    await client.mergeRows('transactions', txDelta, true);

    // `left_behind_items`/`borrowed_items` itu SENDIRI TIDAK berubah (tidak
    // ada updated_at baru) — desain sengaja, TIDAK perlu ikut dump kedua.
    final leftDelta = secondDump['left_behind_items'] ?? const [];
    expect(leftDelta.any((r) => r['id'] == 'l1'), isFalse,
        reason: 'baris left_behind_items sendiri sengaja TIDAK disentuh '
            'voidTransaction (lihat dok desain) — status batal murni via '
            'JOIN status transaksi induk');

    // `laci_meja_events` audit trail 'batal' TIDAK ikut dump kedua — bukan
    // bug, ini pengulangan dari filter `excludeVoidTx` yang SUDAH ADA lebih
    // dulu di `dumpSince` (`73338c8`, sebelum Item 60): baris Laci Meja
    // (termasuk log event-nya) milik transaksi yang statusnya SUDAH void
    // sengaja dikecualikan dari alur sync host->klien sama sekali — tidak
    // relevan lagi disebar begitu nota induknya batal. Audit trail-nya
    // tetap ADA & lengkap di HOST (diverifikasi di atas); yang penting bagi
    // KLIEN cukup status void nota-nya sendiri (yang SUDAH sync di atas) —
    // itu saja sudah cukup menyembunyikan entri dari dashboard klien lewat
    // JOIN, tanpa perlu event audit itu ikut terkirim.
    final eventsDelta = secondDump['laci_meja_events'] ?? const [];
    expect(eventsDelta.where((r) => r['aksi'] == 'batal').length, 0,
        reason: 'filter excludeVoidTx yang sudah ada sebelumnya sengaja '
            'mengecualikan event Laci Meja milik nota void dari sync '
            'host->klien — bukan regresi, tapi desain existing');

    // Klien sekarang HARUS melihat: (1) nota berstatus void, (2) kedua
    // entri Laci Meja TIDAK LAGI pending (tersembunyi dari dashboard via
    // JOIN status transaksi induk), (3) event audit 'batal' tercatat.
    final clientTx = await (client.select(client.transactions)
          ..where((t) => t.id.equals('tx1')))
        .getSingle();
    expect(clientTx.status, 'void');

    final pendingAfter = await client.getLaciMejaPending(customerId: 'cust1');
    expect(pendingAfter.ketinggalan, 0,
        reason: 'entri "ketinggalan" milik nota yang sudah void tidak boleh '
            'lagi tampil pending di device lain');
    expect(pendingAfter.pinjaman, 0,
        reason: 'entri pinjaman milik nota yang sudah void tidak boleh lagi '
            'tampil pending di device lain');

    final clientLeftList = await client.watchLeftBehindItems().first;
    expect(clientLeftList.any((e) => e.id == 'l1'), isFalse);
    final clientBorrowedList = await client.watchBorrowedItems().first;
    expect(clientBorrowedList.any((e) => e.id == 'b1'), isFalse);

    // Audit trail 'batal' sengaja TIDAK ikut ke klien (lihat dok di atas) —
    // klien tidak akan punya baris `laci_meja_events` aksi='batal' ini,
    // cukup HOST yang menyimpannya.
    final clientEvents = await (client.select(client.laciMejaEvents)
          ..where((t) => t.aksi.equals('batal')))
        .get();
    expect(clientEvents, isEmpty);

    // Mode riwayat (includeCollected/includeFullyReturned) TETAP menampilkan
    // entri walau nota-nya void — nota adalah bukti historis permanen.
    final riwayatLeft =
        await client.watchLeftBehindItems(includeCollected: true).first;
    expect(riwayatLeft.any((e) => e.id == 'l1'), isTrue);
    final riwayatBorrowed =
        await client.watchBorrowedItems(includeFullyReturned: true).first;
    expect(riwayatBorrowed.any((e) => e.id == 'b1'), isTrue);
  });
}
