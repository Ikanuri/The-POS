import 'package:drift/drift.dart';

/// Append-only. Stok terkini = stockAfter dari entry terbaru per productUnitId.
/// type: opening | sale | purchase | return_in | return_out | adjustment
class StockLedger extends Table {
  TextColumn get id => text()();
  TextColumn get productUnitId => text()();
  TextColumn get type => text()();
  RealColumn get qtyChange => real()(); // positif = masuk, negatif = keluar
  RealColumn get stockAfter => real()(); // running balance
  TextColumn get referenceId => text().nullable()();
  TextColumn get kasirId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// type: daily_expense | owner_withdrawal | supplier_payment | change_given
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get localId => text().unique()();
  TextColumn get type => text()();
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get kasirId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  /// Item 61.5 — soft-delete (bukan hard DELETE): `expenses` sync-nya
  /// append-only (cuma kirim baris BARU, tidak pernah kirim "baris ini
  /// dihapus") — hard DELETE di 1 device TIDAK PERNAH propagate, expense
  /// yang dihapus TETAP ada di device lain yang sudah menerimanya, laba
  /// bersih antar-device beda permanen. Null = aktif (belum dihapus); diisi
  /// = dihapus pada waktu itu. Ditulis sbg UPDATE (append-only-compatible,
  /// baris "diupdate" ikut ter-sync sbg baris baru), konsisten dgn pola
  /// tabel lain di app ini (produk/pelanggan pakai `is_active`).
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// type: earn | redeem | adjust
class LoyaltyPointLedger extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get type => text()();
  IntColumn get points => integer()(); // positif atau negatif
  TextColumn get referenceId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
