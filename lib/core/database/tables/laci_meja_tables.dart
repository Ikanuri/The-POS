import 'package:drift/drift.dart';

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
  TextColumn get itemName => text()(); // nama produk, disalin dari nota

  /// Item 52 susulan — id baris `transaction_items` yang ditandai. Tautan
  /// PRESISI ke baris nota (bukan cocok-nama): produk yang SAMA bisa muncul
  /// beberapa kali di satu nota dgn satuan berbeda (Pak vs Slop — lazim di
  /// data toko ini), jadi mencocokkan lewat nama akan salah tandai. Nullable
  /// utk entri lama yang dibuat sebelum kolom ini ada.
  TextColumn get transactionItemId => text().nullable()();
  TextColumn get jenis => text()(); // 'ketinggalan' | 'titip'
  /// SENGAJA TANPA FK ke `Customers` (beda dari kolom lain di tabel ini yang
  /// FK ke `Transactions`) — pola identik `Transactions.customerId`. Sebab:
  /// pelanggan adalah master data yang HANYA mengalir host→klien (lihat
  /// `dumpSince`), jadi pelanggan ad-hoc yang dibuat di device kasir TIDAK
  /// PERNAH tersinkron balik ke host. Kalau kolom ini FK ke `Customers`,
  /// usulan Laci Meja yang menaut pelanggan ad-hoc semacam itu GAGAL
  /// PERMANEN saat diterapkan di host (`FOREIGN KEY constraint failed`,
  /// bug nyata dilaporkan user — migrasi v26 menghapus FK ini).
  TextColumn get customerId => text().nullable()();
  TextColumn get customerNameText => text().nullable()();
  TextColumn get note => text().nullable()();

  /// Item 52 susulan lagi — jumlah yang SEBENARNYA tertinggal/dititip, bisa
  /// SEBAGIAN dari qty baris nota (mis. beli 5, yang ketinggalan cuma 2).
  /// Nullable: entri LAMA (dibuat sebelum kolom ini ada) berarti "seluruh
  /// qty baris nota" (perilaku asal, sebelum fitur ini) — dibedakan dari
  /// entri baru yang SELALU mengisi kolom ini eksplisit (walau nilainya
  /// kebetulan sama dengan qty penuh).
  RealColumn get qty => real().nullable()();

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

  /// Item 52 redesain — id baris `transaction_items` yang dipinjamkan.
  /// Tautan PRESISI ke baris nota (bukan cocok-nama), pola identik
  /// `LeftBehindItems.transactionItemId` — dipakai struk in-app memberi
  /// penanda "Pinjaman" di baris yang benar. Nullable utk entri lama yang
  /// dibuat sebelum kolom ini ada.
  TextColumn get transactionItemId => text().nullable()();
  /// SENGAJA TANPA FK ke `Customers` — lihat komentar di
  /// `LeftBehindItems.customerId` (alasan identik: pelanggan ad-hoc device
  /// kasir tidak pernah tersinkron balik ke host).
  TextColumn get customerId => text().nullable()();
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
