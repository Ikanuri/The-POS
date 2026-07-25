import 'package:drift/drift.dart';

class Products extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  IntColumn get productGroupId => integer().nullable()();
  TextColumn get kodeProduk => text().nullable()();
  /// Bila terisi, produk ini adalah VARIAN dari produk induk (mis. Pop Ice →
  /// Coklat). Varian disembunyikan dari katalog utama dan muncul sebagai
  /// pilihan add-on di modal entri item induk.
  TextColumn get parentProductId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  /// Item 25a — tanda cepat "stok habis" manual, TERPISAH dari sistem stok
  /// resmi (belum diaudit). Diset lewat modal item kasir (bukan form
  /// Produk) untuk akses cepat. Kosmetik di kasir (tidak menonaktifkan
  /// fungsi + — itu wewenang izin "Izinkan Stok Minus"), tapi benar-benar
  /// menonaktifkan tombol tambah di katalog HTML statis.
  BoolColumn get markedOutOfStock =>
      boolean().withDefault(const Constant(false))();
  /// Item 40 — true bila produk ini diedit LOKAL di device non-owner
  /// (asisten/kasir) sejak terakhir diketahui identik dengan data host.
  /// Dipakai `dumpLocalProposals()` utk kirim "usulan harga/produk" ke
  /// owner via sync — TIDAK pernah di-set true di device owner (owner
  /// adalah sumber kebenaran, tidak perlu mengusulkan ke diri sendiri).
  /// Otomatis kembali false saat baris ini ditimpa oleh push resmi dari
  /// host (mis. setelah owner setuju) — lihat AppDatabase.mergeRows,
  /// row dari host SELALU bawa locally_modified=false.
  BoolColumn get locallyModified =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Group produk legacy (ID 3–20), nama diisi manual oleh owner.
class ProductGroups extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().nullable()();
  /// Item 54 — urutan tampil chip kategori di tab Kasir (drag reorder).
  /// Semua baris lama default 0 setelah migrasi (belum pernah diurutkan
  /// manual) — tie-break sekunder ke `name` menjaga urutan tetap stabil
  /// sampai user benar-benar drag salah satu chip.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Item 54 — kategori TAMBAHAN di luar kategori utama (`Products.
/// productGroupId`). Satu produk boleh punya banyak baris di sini (satu per
/// kategori tambahan), TANPA menimpa kategori utamanya. Keberadaan baris di
/// sini = produk tsb "juga" ada di kategori itu. PK komposit — dijamin tidak
/// ada baris duplikat utk pasangan (productId, groupId) yang sama.
class ProductGroupTags extends Table {
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get groupId => integer().references(ProductGroups, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {productId, groupId};
}

/// Satuan legacy (ID 1–25): Kg, Pcs, Pak, Bal, Sak, Slop, Biji, Dos, dll.
class UnitTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get abbrev => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Varian produk: tiap produk bisa punya beberapa satuan jual
/// (mis. Indomie: pcs / renteng 10 / dus 40) dengan rasio ke satuan dasar.
class ProductUnits extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get unitTypeId => integer().nullable()();
  BoolColumn get isBaseUnit => boolean().withDefault(const Constant(false))();
  RealColumn get ratioToBase => real().withDefault(const Constant(1.0))();
  BoolColumn get isNonStock => boolean().withDefault(const Constant(false))();

  /// Item 11: ambang stok menipis, disimpan di baris satuan DASAR saja
  /// (stok selalu dianker ke satuan dasar). null = tidak dipantau.
  IntColumn get minStock => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Barcode per varian — satu varian bisa punya beberapa barcode.
class ProductBarcodes extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get productUnitId => text().references(ProductUnits, #id)();
  TextColumn get barcode => text().unique()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  BoolColumn get isGenerated => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
