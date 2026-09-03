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

  /// SENGAJA terpisah dari [updatedAt]. `updatedAt` ikut tersentuh aksi
  /// operasional biasa (ambil sebagian, sync, dsb) sehingga tidak bisa
  /// dipakai menjawab "kapan isinya terakhir DIUBAH orang". Kolom ini HANYA
  /// distempel saat user benar-benar mengedit atribut entri lewat sheet edit
  /// di struk — null berarti entri belum pernah diedit sejak dibuat.
  DateTimeColumn get lastEditedAt => dateTime().nullable()();
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

  /// Kartu pinjaman yang disematkan ke atas daftar dashboard, mengabaikan
  /// urutan FIFO `createdAt` — untuk pinjaman yang perlu terus terlihat
  /// (mis. wadah mahal yang sudah lama belum kembali). Disimpan per BARIS,
  /// tapi UI menyalakan/mematikannya untuk seluruh baris dalam satu grup
  /// pelanggan sekaligus (kartu dashboard dikelompokkan per pelanggan).
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get locallyModified =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Lihat komentar di `LeftBehindItems.lastEditedAt`. Toggle [pinned] TIDAK
  /// menstempel kolom ini (menyematkan kartu bukan mengubah isi entri).
  DateTimeColumn get lastEditedAt => dateTime().nullable()();
  DateTimeColumn get fullyReturnedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Satu KEJADIAN pengambilan/pengembalian/pemenuhan pada salah satu entri
/// Laci Meja (PLAN.md Item 54, poin 1/2/5 dari usulan user).
///
/// **Kenapa tabel log, bukan sekadar mengurangi kolom qty di 3 tabel di
/// atas** — ketiga tabel itu master data yang disinkron *last-write-wins by
/// `updated_at`*. Kalau "ambil 3 dari 5" ditulis sbg read-modify-write pada
/// kolom qty, dua device yang mengambil sebelum sempat sync akan SALING
/// MENIMPA: owner ambil 2 (5->3) dan kasir ambil 1 (5->4), yang `updated_at`
/// -nya lebih baru menang, satu pengambilan HILANG diam-diam. Itu ledger
/// barang FISIK, jadi selisihnya nyata di rak. Sebagai baris log terpisah,
/// dua pengambilan itu jadi dua baris berbeda yang keduanya selamat — sisa
/// dihitung `qty - Σ log`, selalu benar tanpa bergantung urutan sync.
/// Pola acuannya `TransactionPayments` (satu nota, banyak momen bayar).
///
/// Baris di sini TIDAK PERNAH di-update, hanya ditambah — pembatalan
/// diwakili baris `aksi = 'batal'` sendiri, bukan menghapus/mengubah baris
/// lama (jejak audit utuh, sekaligus bikin merge sync bebas konflik).
///
/// **Sinkronisasi**: tetap lewat antrian persetujuan owner spt 3 tabel
/// induknya (keputusan eksplisit user), BUKAN auto-merge ala
/// `LanSyncService.appendOnlyTables`. Append-only di sini soal BENTUK
/// datanya, bukan soal jalur sync-nya.
class LaciMejaEvents extends Table {
  TextColumn get id => text()(); // UUID

  /// 'titip' | 'pinjaman' | 'preorder' — kategori entri induknya. Disimpan
  /// eksplisit (bukan disimpulkan dari tabel mana `entryId` ada) supaya log
  /// gabungan bisa dibaca & difilter tanpa 3x JOIN.
  TextColumn get entityType => text()();

  /// Id baris induk di `left_behind_items` / `borrowed_items` /
  /// `preorder_entries`. SENGAJA TANPA FK: tabelnya berbeda-beda tergantung
  /// [entityType] (SQLite tidak punya FK polimorfik), dan alasan yang sama
  /// dgn `LeftBehindItems.customerId` berlaku — baris induk bisa saja belum
  /// tersinkron ke host saat usulan diterapkan, FK akan bikin gagal permanen.
  TextColumn get entryId => text()();

  /// 'ambil' (titip/ketinggalan diambil) | 'kembali' (pinjaman dikembalikan)
  /// | 'penuhi' (pre-order dipenuhi) | 'batal' (pre-order dibatalkan).
  TextColumn get aksi => text()();

  /// Jumlah pada kejadian ini. Untuk `aksi = 'batal'` nilainya 0 — pembatalan
  /// menutup sisa yang belum terpenuhi tanpa ada barang yang berpindah.
  RealColumn get qty => real().withDefault(const Constant(0))();

  TextColumn get note => text().nullable()();

  /// Device yang mencatat (`device_code`) — sekadar jejak "siapa", tidak
  /// dipakai logika apa pun.
  TextColumn get deviceCode => text().nullable()();

  BoolColumn get locallyModified =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Waktu HOST menyetujui/menerapkan event ini (`applyLaciMejaProposals`),
  /// BUKAN waktu kejadian fisik terjadi (itu [createdAt], tidak pernah
  /// diubah). Item 57 — delta `dumpSince` host->klien murni pakai
  /// `createdAt >= since` sehingga event yang dibuat klien SEBELUM
  /// watermark sync berikutnya tidak pernah lolos balik ke klien manapun,
  /// walau baru saja disetujui host — `locallyModified` klien nyangkut
  /// selamanya & event yang sama diusulkan ulang tiap sync (data aman,
  /// dibuang via `filterUnchangedLaciMejaProposals`, tapi payload usulan
  /// tumbuh tanpa akhir). `appliedAt` dipakai SEBAGAI TAMBAHAN filter
  /// delta (`createdAt >= since OR appliedAt >= since`) supaya event yang
  /// baru disetujui host dijamin lolos ke sync klien berikutnya.
  DateTimeColumn get appliedAt => dateTime().nullable()();

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
  /// SENGAJA TANPA FK ke `Customers` — alasan identik dengan
  /// `LeftBehindItems.customerId`. Nullable: null = nama manual/ad-hoc
  /// (pembeli umum bernama, tanpa record pelanggan), terisi = pelanggan
  /// terdaftar. Dipakai UI membedakan aksen pelanggan tetap vs ad-hoc.
  /// Entri lama (sebelum kolom ini ada) selalu null — tampil sbg ad-hoc,
  /// aman karena [customerName] memang satu-satunya info yang pernah ada.
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text()();
  TextColumn get phone => text().nullable()();
  RealColumn get qtyOrdered => real()();

  /// Susulan (permintaan user) — id baris `transaction_items` yang DP/
  /// harganya dikunci Rp 0 saat checkout (lihat `_effectivePrice` di
  /// `item_entry_sheet.dart`: `isPreorder && !dpPaid` -> harga 0). Tautan
  /// PRESISI ke baris nota (bukan cocok-nama/produk+satuan), pola identik
  /// `LeftBehindItems.transactionItemId`/`BorrowedItems.transactionItemId`
  /// (alasan sama: produk+satuan yang SAMA bisa muncul >1 kali di satu
  /// nota) — dipakai `collectPreorderDeposit` menemukan baris yang harus
  /// dinaikkan dari Rp 0 ke harga asli saat DP akhirnya dibayar. Nullable
  /// utk entri lama (dibuat sebelum kolom ini ada) DAN pre-order titip
  /// wadah tanpa membeli apa pun (tidak ada baris nota utk ditaut).
  TextColumn get transactionItemId => text().nullable()();

  /// Jumlah wadah dititip sbg jaminan — wajib >0 kalau satuan produknya
  /// `requiresDeposit = true` (divalidasi di layer aplikasi, bukan DB).
  RealColumn get depositQty => real().withDefault(const Constant(0))();
  BoolColumn get paid => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  BoolColumn get locallyModified =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Lihat komentar di `LeftBehindItems.lastEditedAt`.
  DateTimeColumn get lastEditedAt => dateTime().nullable()();
  DateTimeColumn get fulfilledAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
