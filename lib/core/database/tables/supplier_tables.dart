import 'package:drift/drift.dart';

class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  IntColumn get outstandingDebt => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Sync LAN pakai delta by `updatedAt` (lihat `dumpSince`/masterData) —
  // `outstandingDebt`/`isActive` bisa berubah SETELAH baris dibuat, jadi
  // `createdAt` saja tidak cukup jadi cursor. WAJIB di-restamp eksplisit di
  // SETIAP fungsi yang meng-update baris ini (lihat gotcha `updated_at` di
  // CLAUDE.md — kolom ini TIDAK auto-touch saat update, cuma saat insert).
  // NULLABLE (bukan `withDefault(currentDateAndTime)`) krn kolom ini
  // ditambah lewat `addColumn` migrasi (skema v41) — SQLite MENOLAK
  // `ALTER TABLE ADD COLUMN` dgn default non-konstan (`CURRENT_TIMESTAMP`);
  // baris lama dibackfill manual (`updated_at = created_at`) saat migrasi,
  // baris baru cukup diisi eksplisit di kode insert/update (pola sama spt
  // `Transactions.updatedAt`).
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// status: draft | received | partial
class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get localId => text().unique()();
  TextColumn get supplierId => text().nullable()();
  TextColumn get kasirId => text().nullable()();
  TextColumn get status => text()();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get paid => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();
  // Sama spt `Suppliers.updatedAt` — `status`/`paid`/`syncedAt` bisa berubah
  // setelah baris dibuat (draft->received->partial, cicilan ke supplier),
  // jadi butuh cursor sendiri buat sync LAN. WAJIB di-restamp eksplisit di
  // SETIAP fungsi yang meng-update baris ini. NULLABLE — lihat dok
  // `Suppliers.updatedAt` soal alasan (ALTER TABLE ADD COLUMN + default
  // non-konstan ditolak SQLite).
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// Baris per-produk pembelian — TIDAK PERNAH di-update setelah dibuat (tidak
// ada satu pun fungsi di app_database.dart yang meng-`update(purchaseItems)`
// per 2026-09, cek lagi kalau menambah fitur edit item pembelian nanti).
// Tidak butuh kolom `updatedAt`: `createdAt` (ditambah skema v41 — tabel ini
// sebelumnya tanpa timestamp sama sekali) saja sudah cukup jadi cursor delta
// sync LAN (lihat `dumpSince`).
class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text().references(Purchases, #id)();
  TextColumn get productUnitId => text()();
  RealColumn get qty => real()();
  IntColumn get pricePerUnit => integer()();
  IntColumn get subtotal => integer()();
  // Tabel ini sebelumnya TIDAK PUNYA timestamp sama sekali — ditambah
  // khusus utk jadi cursor delta sync LAN (`dumpSince`), krn baris ini
  // immutable (lihat dok kelas di atas) `createdAt` saja sudah cukup,
  // tidak perlu `updatedAt`. NULLABLE krn ditambah lewat `addColumn`
  // migrasi (lihat dok `Suppliers.updatedAt` soal alasan); baris lama
  // dibackfill saat migrasi (v41), baris baru WAJIB diisi eksplisit saat
  // insert (belum ada kode yang membuat baris ini per 2026-09).
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
