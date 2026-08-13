import 'package:drift/drift.dart';

/// "Kamus belajar" — pemetaan TEKS yang diketik/ditempel manusia ke satuan
/// produk yang sebenarnya. Dipakai fitur Penerimaan Barang (tempel teks dari
/// tools cek-stok eksternal): begitu owner memilih produk yang benar untuk
/// satu baris yang ambigu, pilihan itu diingat di sini — baris dengan teks
/// SAMA di penerimaan berikutnya langsung cocok otomatis, tidak ditanya lagi.
///
/// Pola & alasan SAMA dengan alias barcode di sinkron harga antar toko
/// (lihat CLAUDE.md): begitu owner mengonfirmasi satu pasangan, simpan
/// permanen supaya tidak pernah ditinjau ulang. BUKAN fuzzy-matching —
/// keputusan user 11 Agt 2026: pencocokan PERSIS saja, ambiguitas
/// diselesaikan lewat pilihan manual yang lalu diingat di sini.
///
/// **Tersinkron DUA ARAH** (permintaan eksplisit user): kamus yang dipelajari
/// device kasir ikut sampai ke owner dan sebaliknya — beda dari master data
/// biasa yang cuma mengalir host→klien. Lihat `LanSyncService.sharedTables`.
class ProductAliases extends Table {
  TextColumn get id => text()();

  /// Nama produk dari teks, SUDAH dinormalisasi (huruf kecil, spasi
  /// dirapikan) — lihat `AliasKey.normalizeName`.
  TextColumn get normalizedName => text()();

  /// Satuan dari teks, sudah dinormalisasi. STRING KOSONG = kunci tingkat-2
  /// "tanpa satuan" (fallback saat kunci ber-satuan tidak ketemu). Sengaja
  /// tidak nullable: SQLite memperlakukan NULL sbg tidak-sama-dengan-NULL di
  /// UNIQUE, jadi kunci "tanpa satuan" tidak akan pernah bentrok dgn benar
  /// kalau memakai NULL.
  TextColumn get normalizedUnit => text()();

  /// Satuan produk tujuan (bukan produk-nya) — penerimaan barang menambah
  /// stok ke satuan tertentu, dan satu produk bisa punya beberapa satuan
  /// jual dgn rasio berbeda.
  TextColumn get productUnitId => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// WAJIB dicap ulang setiap kali baris diubah — `dumpSince` memfilter
  /// tabel ini `WHERE updated_at >= since` (gotcha yang sudah 2x kejadian
  /// di tabel lain, lihat CLAUDE.md §Gotcha).
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  /// Satu teks (nama+satuan) hanya boleh memetakan ke SATU satuan produk —
  /// kalau tidak, kamusnya jadi ambigu dan tidak ada gunanya.
  @override
  List<Set<Column>> get uniqueKeys => [
        {normalizedName, normalizedUnit},
      ];
}
