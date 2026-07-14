import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Regresi: sync LAN gagal total di HP Infinix Smart 8 dengan
/// `SqliteException(1): table transactions has no column named
/// checked_item_ids` — device itu menerima dump dari device LAIN yang
/// skemanya lebih baru (checked_item_ids, schemaVersion 15), sementara
/// tabel FISIK lokalnya belum punya kolom itu (app belum ter-update).
/// `mergeRows` sebelumnya membangun INSERT dari SEMUA kolom yang dikirim
/// pengirim tanpa memvalidasi ke skema lokal — satu kolom asing saja
/// menggagalkan SELURUH baris (bahkan seluruh proses sync tsb, karena
/// exception menjalar keluar dari `transaction()`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
      'mergeRows TIDAK gagal saat baris masuk membawa kolom yang belum ada '
      'di tabel fisik lokal (device tertinggal versi schema) — kolom asing '
      'diabaikan, kolom lain tetap ke-insert', () async {
    // Simulasikan device yang tabel `transactions` fisiknya belum punya
    // `checked_item_ids` (mis. app belum ter-update ke schemaVersion 15),
    // walau AppDatabase yang jalan di test ini sudah versi terbaru.
    await db.customStatement(
        'ALTER TABLE transactions DROP COLUMN checked_item_ids');

    final incomingRow = <String, Object?>{
      'id': 'tx-remote-1',
      'local_id': 'K1-0001',
      'kasir_id': 'K1',
      'customer_id': null,
      'customer_name': null,
      'status': 'lunas',
      'total': 50000,
      'paid': 50000,
      'change_amount': 0,
      'payment_method': 'tunai',
      'internal_note': null,
      'struk_note': null,
      'employee_name': null,
      'points_earned': 0,
      'change_taken': 0,
      'created_at': 1700000000,
      'synced_at': null,
      // Kolom yang TIDAK ADA secara fisik di tabel lokal (device sender
      // sudah versi lebih baru) — harus diabaikan, bukan bikin insert gagal.
      'checked_item_ids': '["ti1","ti2"]',
    };

    final count = await db.mergeRows('transactions', [incomingRow], true);

    expect(count, 1,
        reason: 'baris tetap ter-insert, kolom asing cukup di-drop saja');
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx-remote-1')))
        .getSingle();
    expect(tx.total, 50000);
    expect(tx.status, 'lunas');
  });
}
