import 'package:drift/drift.dart';

import 'customer_tables.dart';
import 'transaction_tables.dart';

/// Item 52 ("Laci Meja") — 3 kategori catatan operasional harian toko:
/// barang ketinggalan/dititip, pinjaman wadah/deposit, dan pre-order
/// (backorder, termasuk antri tabung LPG). Rancangan lengkap & keputusan
/// bisnis ada di PLAN.md Item 52 — jangan didesain ulang di sini.
///
/// Semua 3 tabel numpang transaksi yang sedang berjalan (BUKAN bikin nota
/// terpisah) — lihat kolom `transactionId` di masing-masing.

/// Barang ketinggalan (`jenis = 'ketinggalan'`) atau dititip sengaja
/// (`jenis = 'titip'`) oleh pembeli setelah transaksi.
class LeftBehindItems extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get itemName => text()(); // freeform, bukan produk terstruktur
  TextColumn get jenis => text()(); // 'ketinggalan' | 'titip'
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get customerNameText => text().nullable()();
  TextColumn get note => text().nullable()();

  /// Item 40 pattern: true bila baris ini dibuat/diedit di device non-owner,
  /// menunggu persetujuan owner via sync. Device owner tidak pernah set ini.
  BoolColumn get locallyModified =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get collectedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Wadah/deposit (galon, tabung gas) yang dipinjamkan ke pembeli dan harus
/// kembali secara FISIK — bisa kembali sebagian (`qtyReturned` < `qty`).
class BorrowedItems extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get itemName => text()();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get customerNameText => text().nullable()();
  RealColumn get qty => real()();
  RealColumn get qtyReturned => real().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  BoolColumn get locallyModified =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get fullyReturnedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pre-order/backorder untuk produk stok kosong — termasuk antrian tabung
/// LPG (titip wadah kosong sbg jaminan, lihat `ProductUnits.
/// requiresDeposit`). FIFO murni berdasar `createdAt`; `paid` HANYA
/// informatif, TIDAK PERNAH menentukan urutan antrian.
class PreorderEntries extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get productId => text()();
  TextColumn get productUnitId => text()();

  /// NULLABLE — satu-satunya kasus null: pembeli cuma titip wadah tanpa
  /// membeli apa pun (tidak ada transaksi lain berjalan saat itu).
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id)();
  TextColumn get customerName => text()();
  TextColumn get phone => text().nullable()();
  RealColumn get qtyOrdered => real()();

  /// Jumlah wadah dititip sbg jaminan — wajib >0 kalau satuan produknya
  /// `requiresDeposit = true` (divalidasi di layer aplikasi, bukan DB).
  RealColumn get depositQty => real().withDefault(const Constant(0))();
  BoolColumn get paid => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  BoolColumn get locallyModified =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get fulfilledAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
