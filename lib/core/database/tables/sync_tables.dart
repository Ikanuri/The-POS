import 'package:drift/drift.dart';

/// Item 17 (Fase 2) — antrian approval sync sisi HOST, PERSISTEN (bukan
/// lagi `static final List` di memori `LanSyncService`). Sebelumnya kalau
/// app owner di-restart/di-kill SEBELUM sempat tap "Setuju", seluruh
/// antrian hilang total — klien wajib SELALU full-dump sejak epoch sbg
/// jaring pengaman (data yang hilang dari antrian otomatis "muncul lagi"
/// di sync berikutnya). Dengan antrian persisten, klien bisa aman beralih
/// ke watermark upload incremental (lihat `_kUploadWatermarkKey` di
/// `lan_sync_service.dart`) — data yang SUDAH tersimpan durable di sini
/// tidak akan hilang walau host restart, jadi tidak perlu dikirim ulang.
///
/// [tablesJson] menyimpan payload penuh (Map<String,List<Map>> hasil
/// decode JSON dari request klien) sbg satu blob — pola sama seperti
/// `HeldOrders.cartJson`/katalog tersimpan (blob JSON di kolom teks,
/// bukan skema ternormalisasi) supaya tidak perlu migrasi tambahan tiap
/// ada tabel sync baru.
class SyncUploadQueue extends Table {
  TextColumn get id => text()();
  TextColumn get fromIp => text()();
  DateTimeColumn get arrivedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get tablesJson => text()();
  DateTimeColumn get since => dateTime()();
  TextColumn get tablesSummary => text()();

  @override
  Set<Column> get primaryKey => {id};
}
