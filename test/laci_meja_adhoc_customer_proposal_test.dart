import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug nyata dilaporkan user (screenshot "Gagal menerapkan usulan:
/// SqliteException(787): FOREIGN KEY constraint failed") — usulan Laci Meja
/// (Titip/Ketinggalan) dari device kasir menaut `customer_id` pelanggan
/// AD-HOC yang dibuat di device kasir itu sendiri, yang TIDAK PERNAH
/// tersinkron balik ke host (pelanggan = master data, cuma mengalir
/// host->klien via `dumpSince`, lihat komentar `_appendOnly`/`_masterData`).
/// Host (yang menerapkan usulan) TIDAK PERNAH punya baris pelanggan itu di
/// tabel `customers`-nya sendiri — kalau kolom `customer_id` di
/// `left_behind_items`/`borrowed_items` FK ke `Customers`, penerapan usulan
/// ini GAGAL PERMANEN, tidak pernah bisa diterapkan sama sekali.
void main() {
  late AppDatabase db;
  // `NativeDatabase.memory()` polos TIDAK mengaktifkan FK enforcement
  // (beda dari koneksi produksi sungguhan di `_openConnection`) — tanpa
  // baris ini, bug FK-related ini TIDAK akan pernah tertangkap test,
  // apa pun skema tabelnya (lihat gotcha yg sama di
  // `lan_sync_transaction_items_repro_test.dart`).
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON;');
  });
  tearDown(() async => db.close());

  test(
      'applyLaciMejaProposals TIDAK melempar FOREIGN KEY constraint failed '
      'walau customer_id menaut pelanggan yang TIDAK ADA di tabel customers '
      'host (pelanggan ad-hoc device kasir)', () async {
    // Transaksi HARUS ada di host (transactionId tetap FK, dan itu memang
    // selalu tersinkron lewat dumpSince append-only sebelum usulan
    // diterapkan) — tapi CUSTOMER-nya SENGAJA TIDAK dibuat di sini, persis
    // skenario bug: pelanggan ad-hoc yang cuma ada di device kasir asal.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));

    final proposals = {
      'left_behind_items': [
        {
          'id': 'l1',
          'transaction_id': 'tx1',
          'item_name': 'Sedap Soto',
          'transaction_item_id': null,
          'jenis': 'ketinggalan',
          // Pelanggan ad-hoc — TIDAK ADA baris 'customers' dgn id ini di DB
          // host manapun. Ini persis kondisi yang bikin FK gagal di bug lama.
          'customer_id': 'cust-adhoc-tidak-ada-di-host',
          'customer_name_text': 'Devi',
          'note': null,
          'locally_modified': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'collected_at': null,
          'qty': 1.0,
        },
      ],
    };
    final approvedIds = {
      'left_behind_items': {'l1'},
    };

    // TIDAK BOLEH throw (dulu: SqliteException 787 FOREIGN KEY constraint
    // failed).
    final result = await db.applyLaciMejaProposals(proposals, approvedIds);
    expect(result.applied, 1);
    expect(result.skippedReasons, isEmpty);

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Sedap Soto');
    expect(rows.single.customerId, 'cust-adhoc-tidak-ada-di-host');
    expect(rows.single.customerNameText, 'Devi');
  });
}
