import 'package:drift/drift.dart';

import 'customer_tables.dart';
import 'product_tables.dart';

/// Harga berjenjang per varian. Tier dengan minQty terbesar yang <= qty menang.
class PriceTiers extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get productUnitId => text().references(ProductUnits, #id)();
  IntColumn get minQty => integer().withDefault(const Constant(1))();
  IntColumn get price => integer()(); // Rupiah bulat
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Harga alternatif berlabel (mis. "Harga Toko A" = 3000) — BUKAN tier
/// berjenjang minQty seperti [PriceTiers]. Murni pilihan cepat yang tampil
/// sebagai chip tap-untuk-pakai di kasir (`ItemEntrySheet`), tidak pernah
/// dipilih otomatis oleh `PriceService.resolvePrice`.
///
/// Fase B "Kategori Harga" (schemaVersion 40) menambah 4 kolom NULLABLE di
/// bawah — baris lama/ad-hoc tanpa kategori TIDAK berubah perilakunya sama
/// sekali (kolom-kolom itu tetap NULL, `price` dipakai apa adanya). Baris
/// yang PUNYA kategori (`priceCategoryId` + `marginType` + `marginValue`
/// terisi) sebaliknya jadi "hidup": `price` di baris ini cuma SNAPSHOT
/// terakhir (histori/fallback) — nilai yang sebenarnya dipakai pemanggil
/// dihitung ULANG live dari `marginAnchor`/`marginType`/`marginValue` +
/// harga dasar/modal produk TERKINI, lihat `AppDatabase.getAltPrices()` &
/// `computeCategoryPrice()` (`lib/core/utils/price_category_calc.dart`).
class AltPrices extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get productUnitId => text().references(ProductUnits, #id)();
  TextColumn get label => text()();
  IntColumn get price => integer()(); // Rupiah bulat
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Urutan tampil chip di ItemEntrySheet, diatur lewat drag-reorder di form
  // Produk. TIDAK bisa mengandalkan createdAt: saveProduct menulis semua
  // baris harga-lain dalam satu batch dengan timestamp yang sama persis.
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Kategori harga pemilik baris ini (nullable — baris ad-hoc lama/manual
  /// tanpa kategori tidak diisi). References [PriceCategories].
  TextColumn get priceCategoryId =>
      text().nullable().references(PriceCategories, #id)();

  /// Acuan margin: `'modal'` (HPP/`costPrice` tier) atau `'dasar'` (harga
  /// jual dasar, tier `minQty=1`). Nullable — hanya terisi untuk baris
  /// kategori (lihat dok kelas).
  TextColumn get marginAnchor => text().nullable()();

  /// Jenis margin: `'percent'` atau `'fixed'` (Rupiah tetap). Nullable.
  TextColumn get marginType => text().nullable()();

  /// Nilai margin sesuai [marginType] — mis. 15.0 untuk 15%, atau 2000.0
  /// untuk Rp2.000 tetap. Nullable.
  RealColumn get marginValue => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Kategori pengelompokan produk untuk "Harga Kategori" (Fase B) — MURNI
/// label pengelompokan tampilan/manajemen, TIDAK ADA margin default per
/// kategori (satu kategori boleh berisi produk dengan karakter margin
/// sangat berbeda, mis. rokok margin tipis + telur margin tebal — margin
/// SELALU per-produk lewat baris [AltPrices] yang menunjuk ke sini via
/// `priceCategoryId`).
///
/// schemaVersion 43: [name] jadi NULLABLE — dipakai sbg penanda tombstone
/// (bukan hard delete), persis pola [ProductGroups.name]. `deletePriceCategory`
/// men-set `name=null` alih-alih menghapus barisnya: sync satu-arah
/// host->klien (`dumpSince`/`masterData`) TIDAK PERNAH propagate DELETE
/// (lihat dok `_allTables`/`masterData` di `AppDatabase`) — kalau barisnya
/// benar² hilang dari host, penghapusan kategori TIDAK AKAN PERNAH sampai
/// ke klien. Full-dump tiap sync (spt `product_groups`) baru bisa
/// merefleksikan penghapusan itu kalau barisnya masih ada (dgn `name=null`)
/// utk di-INSERT OR REPLACE ke klien. `getAllPriceCategories`/
/// `watchPriceCategories` memfilter `name IS NOT NULL` supaya kategori yg
/// ditombstone tidak lagi tampil di UI manapun.
class PriceCategories extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Harga khusus per group pelanggan — prioritas tertinggi di price resolver.
class CustomerGroupPrices extends Table {
  TextColumn get id => text()();
  TextColumn get productUnitId => text().references(ProductUnits, #id)();
  TextColumn get customerGroupId => text().references(CustomerGroups, #id)();
  IntColumn get price => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {productUnitId, customerGroupId},
      ];
}
