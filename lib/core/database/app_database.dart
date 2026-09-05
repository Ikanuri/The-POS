import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:uuid/uuid.dart';

import '../services/crash_log_service.dart';
import '../services/crypto_service.dart';
import '../services/receive_text_parser.dart';
import '../utils/preorder_calc.dart';
import 'tables/app_settings_table.dart';
import 'tables/cash_closing_tables.dart';
import 'tables/customer_tables.dart';
import 'tables/employee_tables.dart';
import 'tables/adjustment_tables.dart';
import 'tables/alias_tables.dart';
import 'tables/laci_meja_tables.dart';
import 'tables/ledger_tables.dart';
import 'tables/pricing_tables.dart';
import 'tables/product_tables.dart';
import 'tables/settings_tables.dart';
import 'tables/summary_tables.dart';
import 'tables/supplier_tables.dart';
import 'tables/sync_tables.dart';
import 'tables/transaction_tables.dart';

part 'app_database.g.dart';

const _kDefaultUnitTypes = <int, String>{
  1: 'Kg',
  2: 'Pcs',
  4: 'Pak',
  5: 'Bal',
  6: 'Sak',
  9: 'Slop',
  10: 'Pres',
  11: 'Ons',
  12: 'Biji',
  13: 'Kas',
  14: 'Dos',
  15: 'Lusin',
  16: 'Box',
  17: 'Rek',
  18: 'Ret',
  19: 'Tas',
  20: 'Ikat',
  22: 'Roll',
  23: 'Toples',
  24: 'Paket',
  25: 'Karton',
};

const kKasirPermissionKeys = <String>[
  'input_stok',
  'tambah_pelanggan',
  'input_pengeluaran',
  'input_pembelian',
  'override_harga',
  'batal_transaksi',
  // Item 24d — default OFF. Tanpa izin ini, tombol "Bayar" di kasir
  // berubah jadi "Kirim ke Owner/Asisten" (lihat kasir_screen.dart).
  'terima_pembayaran',
];

/// Izin khusus role Asisten. Disimpan di tabel kasir_permissions yang sama
/// (dengan prefix `asisten_`) agar ikut tersinkron, tapi ditampilkan di layar
/// "Izin Asisten" terpisah. Asisten tetap punya akses penuh untuk hal lain.
const kAsistenPermissionKeys = <String>[
  'asisten_stok_minus',
];

/// Baris hasil [AppDatabase.watchStockOverview] — Item 30 ("Cek Stok").
/// [unitId] = id satuan DASAR produk ini (dipakai Item 36 stock opname utk
/// panggil [AppDatabase.commitOpname], yang butuh productUnitId bukan productId).
typedef StockOverviewRow = ({
  String productId,
  String unitId,
  String name,
  int? groupId,
  double stock,
  double? minStock,
  bool markedOutOfStock,
  bool requiresDeposit,
});

/// Baris ringkasan satu sesi stock opname (Item 36) — dikelompokkan dari
/// `stock_ledger` by (createdAt, note) yang identik (lihat [AppDatabase.
/// commitOpname]: semua baris dalam satu sesi commit memakai timestamp &
/// note yang SAMA PERSIS supaya bisa direkonstruksi jadi satu sesi di sini).
typedef OpnameSessionSummary = ({
  DateTime createdAt,
  String note,
  int itemCount,

  /// Nilai rupiah TOTAL selisih sesi ini (Σ `qtyChange × HPP satuan`).
  /// NEGATIF = stok fisik lebih SEDIKIT dari catatan (kerugian/susut);
  /// positif = fisik lebih banyak. Dihitung dari HPP (`price_tiers.
  /// cost_price` tier `min_qty = 1`) — pola sama [AppDatabase.getInventoryRows]
  /// — supaya angkanya berarti "berapa modal yang menguap", bukan potensi
  /// omzet yang hilang.
  int valueChange,
});

/// Baris detail satu produk dalam satu sesi opname (Item 36).
typedef OpnameSessionDetailRow = ({
  String productName,
  double qtyChange,
  double stockAfter,

  /// HPP per satuan dasar saat query dijalankan (bukan snapshot saat opname
  /// — `stock_ledger` tidak menyimpan harga). Konsekuensi yang disengaja:
  /// kalau HPP diubah setelah opname, nilai rupiah riwayat lama IKUT
  /// berubah. Alternatifnya (snapshot HPP ke ledger) butuh migrasi kolom
  /// baru & tidak bisa mengisi mundur data lama, jadi tidak diambil.
  int costPrice,

  /// `qtyChange × costPrice`, dibulatkan. Negatif = susut.
  int valueChange,
});

/// Baris hasil [AppDatabase.getInventoryRows] — Item 30(c) (laporan
/// analitik/audit nilai inventori di tab Laporan).
typedef InventoryRow = ({
  String productId,
  String name,
  int? groupId,
  double stock,
  int costPrice,
});

/// Satu produk pre-order yang masih menunggu, lengkap dgn nama produk (hasil
/// JOIN) — dipakai baris pre-order di pengingat cart bar, yang menurut
/// permintaan user WAJIB menyebut produknya, bukan cuma jumlah entri.
typedef PreorderPendingLine = ({
  String productName,
  double qty,
  double depositQty,

  /// Id baris `preorder_entries` & nota tempat pre-order ini dicatat —
  /// permintaan user: cart bar bisa merujuk balik ke nota ASLI pre-order
  /// (bukan cuma info nama+qty). `transactionId` nullable (satu-satunya
  /// kasus: titip wadah tanpa beli apa pun sama sekali, lihat dok
  /// `PreorderEntries.transactionId`) — link hanya ditampilkan kalau terisi.
  String id,
  String? transactionId,
});

/// Ringkasan Laci Meja yang masih menggantung utk SATU pelanggan — dipakai
/// pengingat cart bar (per-kategori, satu baris masing-masing) & modal
/// checkout. `titip`/`ketinggalan` sengaja dipisah (jenisnya beda maknanya,
/// lihat dok `getLaciMejaPending`); `preorders` berisi RINCIAN (bukan sekadar
/// jumlah) krn baris pre-order di cart bar menyebut nama produk + qty +
/// jaminan.
typedef LaciMejaPending = ({
  int titip,
  int ketinggalan,
  int pinjaman,
  List<PreorderPendingLine> preorders,
});

const LaciMejaPending kEmptyLaciMejaPending =
    (titip: 0, ketinggalan: 0, pinjaman: 0, preorders: []);

/// Satu baris log Laci Meja yang SUDAH diperkaya nama barang & pelanggan —
/// dipakai layar "Riwayat" (PLAN.md Item 54 poin 5). Bentuk record (bukan
/// `LaciMejaEvent` mentah) karena tampilan butuh data dari tabel induk yang
/// berbeda-beda per kategori; menjoinnya sekali di SQL jauh lebih murah
/// daripada N+1 di layar. Lihat `AppDatabase.watchLaciMejaEventLog`.
typedef LaciMejaEventView = ({
  String id,
  String entityType,
  String entryId,
  String aksi,
  double qty,
  String? note,
  DateTime createdAt,
  String itemName,
  String? customerName,
  String? transactionId,
});

/// Barcode yang mau dipakai ternyata masih dipegang produk LAIN yang aktif.
/// Dilempar dari dalam transaksi [AppDatabase.saveProduct] supaya seluruh
/// penyimpanan di-rollback (tidak ada produk setengah tersimpan), dan supaya
/// UI bisa menyebut produk mana yang bentrok — bukan sekadar "UNIQUE
/// constraint failed". Satu barcode WAJIB memetakan ke tepat satu produk:
/// kalau tidak, scan di kasir jadi ambigu & bisa menagih barang yang salah.
class BarcodeConflictException implements Exception {
  BarcodeConflictException({
    required this.barcode,
    required this.productName,
    required this.productId,
  });
  final String barcode;
  final String productName;

  /// Supaya UI bisa menawarkan "buka produk itu" langsung dari pesan error —
  /// owner tidak perlu mencarinya manual utk membebaskan barcode-nya.
  final String productId;
  @override
  String toString() =>
      'Barcode "$barcode" sudah dipakai produk "$productName". Gunakan '
      'barcode lain, atau hapus dulu barcode itu dari produk tersebut.';
}

@DriftDatabase(tables: [
  AppSettings,
  Products,
  ProductGroups,
  ProductGroupTags,
  UnitTypes,
  ProductUnits,
  ProductBarcodes,
  PriceTiers,
  AltPrices,
  CustomerGroups,
  CustomerGroupPrices,
  Customers,
  Transactions,
  TransactionItems,
  TransactionPayments,
  HeldOrders,
  ReservedOrderNumbers,
  StockLedger,
  Expenses,
  LoyaltyPointLedger,
  Suppliers,
  Purchases,
  PurchaseItems,
  KasirPermissions,
  PaymentMethods,
  DailySummaries,
  Employees,
  CashClosings,
  SyncUploadQueue,
  LeftBehindItems,
  BorrowedItems,
  PreorderEntries,
  LaciMejaEvents,
  ProductAliases,
  TransactionAdjustmentLines,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e, {this.readOnly = false});

  /// true untuk koneksi arsip (PRAGMA query_only = ON). Saat read-only,
  /// `beforeOpen` tidak boleh menulis (seed batch) karena DB tidak bisa ditulis.
  final bool readOnly;

  static AppDatabase open(String encryptionKey) =>
      AppDatabase(_openConnection(encryptionKey));

  @override
  int get schemaVersion => 39;

  /// Key `app_settings` yang BOLEH ikut sync host->klien.
  ///
  /// ALLOWLIST, bukan blacklist — dan tabel `app_settings` TIDAK BOLEH
  /// di-dump bulat-bulat. Isinya bercampur antara setting TOKO (harus
  /// seragam di semua device) dgn IDENTITAS/STATE DEVICE
  /// (`store_uuid`, `store_key`, `device_code`, `device_role`, watermark
  /// sync, `last_archive_date`). Kalau semua ikut, device klien akan
  /// tertimpa identitasnya sendiri — kerusakan parah & sulit dipulihkan.
  ///
  /// Dipakai di DUA sisi: saat MEMBUAT dump (host) dan saat MENERIMA
  /// (klien, di [mergeRows]) — supaya payload yang menyelundupkan key lain
  /// tetap ditolak walau dump-nya tidak lagi bisa dipercaya.
  static const syncableSettingKeys = {
    // Aturan poin loyalti — dibaca SAAT CHECKOUT. Tanpa disinkron, nota
    // bernilai sama dapat poin BERBEDA tergantung device yang melayani,
    // padahal `loyalty_point_ledger`-nya sendiri ikut tersync (jadi
    // inkonsistensinya masuk ke data bersama).
    'loyalty_point_threshold',
    'loyalty_points_per',
    // Kebijakan stok minus — ditetapkan owner, dibaca kasir saat checkout.
    'allow_negative_stock',
    // Identitas toko yang tercetak di struk. `store_name` selama ini cuma
    // ikut SEKALI saat pairing (payload QR); perubahan setelahnya tidak
    // pernah menyebar, jadi struk antar device bisa beda alamat/nomor.
    'store_name',
    'store_address',
    'store_phone',
    'store_whatsapp',
    'store_telegram',
    // Tampilan struk.
    'receipt_header',
    'receipt_note',
    'receipt_show_employee',
    // Perilaku katalog pesanan.
    'katalog_wa_direct',
    // Kuota antrian pre-order per produk — ditetapkan owner, dibaca kasir
    // saat memutuskan siapa yang diprioritaskan di dashboard Laci Meja.
    // BEDA dari `saved_catalogs` (scratchpad pribadi per device, sengaja
    // lokal): ini kebijakan toko, harus seragam di semua device spt
    // `allow_negative_stock`.
    'preorder_quota_thresholds',
  };

  /// Indeks performa — dipakai filter laporan, riwayat, JOIN produk, dan audit
  /// stok. Idempotent (IF NOT EXISTS) agar aman dijalankan di onCreate maupun
  /// onUpgrade.
  static const _performanceIndexes = <String>[
    'CREATE INDEX IF NOT EXISTS idx_tx_created_at ON transactions(created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_tx_customer ON transactions(customer_id, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_tx_kasir ON transactions(kasir_id, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_tx_status ON transactions(status, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_ti_transaction ON transaction_items(transaction_id)',
    'CREATE INDEX IF NOT EXISTS idx_ti_product ON transaction_items(product_id)',
    // Tanpa indeks ini, query pembayaran per-transaksi (getPaymentsForTx,
    // rekonsiliasi total, dan anti-join backfillMissingPayments di startup)
    // memindai seluruh tabel → O(n^2) yang makin berat seiring data menua.
    'CREATE INDEX IF NOT EXISTS idx_tp_transaction ON transaction_payments(transaction_id)',
    // Retur & timeline pembayaran memfilter berdasarkan waktu bayar.
    'CREATE INDEX IF NOT EXISTS idx_tp_paid_at ON transaction_payments(paid_at)',
    'CREATE INDEX IF NOT EXISTS idx_stock_ledger_unit ON stock_ledger(product_unit_id, created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_stock_ledger_created ON stock_ledger(created_at DESC)',
  ];

  /// Indeks tambahan (v30, dari audit efisiensi storage) — tabel pricing/
  /// produk/loyalti yang belum terindeks sebelumnya (bisa jadi besar seiring
  /// katalog produk bertambah), plus `transaction_id` di 3 tabel Laci Meja
  /// (dipakai guard baru [TutupBukuService.execute] yang JOIN ke sini).
  static const _v30Indexes = <String>[
    'CREATE INDEX IF NOT EXISTS idx_pu_product ON product_units(product_id)',
    'CREATE INDEX IF NOT EXISTS idx_pt_unit ON price_tiers(product_unit_id)',
    'CREATE INDEX IF NOT EXISTS idx_ap_unit ON alt_prices(product_unit_id)',
    'CREATE INDEX IF NOT EXISTS idx_pb_unit ON product_barcodes(product_unit_id)',
    'CREATE INDEX IF NOT EXISTS idx_lpl_customer ON loyalty_point_ledger(customer_id)',
    'CREATE INDEX IF NOT EXISTS idx_lbi_tx ON left_behind_items(transaction_id)',
    'CREATE INDEX IF NOT EXISTS idx_bi_tx ON borrowed_items(transaction_id)',
    'CREATE INDEX IF NOT EXISTS idx_pe_tx ON preorder_entries(transaction_id)',
  ];

  /// Jalankan tiap `CREATE INDEX ... ON <table>(<col>[, <col>...])` di
  /// [statements], SKIP diam-diam kalau `<table>`-nya belum ada ATAU salah
  /// satu kolomnya belum ada (lihat dok pemanggil — fixture test migrasi
  /// lama sering pakai stub tabel MINIMAL, mis. cuma kolom `id`). Idempoten
  /// & aman (index hilang cuma berarti query itu sedikit lebih lambat,
  /// BUKAN salah data) — tidak menyembunyikan bug produksi karena
  /// tabel+kolom yang ditarget di sini semuanya sudah ada sejak
  /// schemaVersion 1 di DB produksi nyata manapun.
  Future<void> _createIndexesIfTableExists(List<String> statements) async {
    final existingTables =
        (await customSelect("SELECT name FROM sqlite_master WHERE type='table'")
                .get())
            .map((r) => r.data['name'] as String)
            .toSet();
    for (final stmt in statements) {
      final match = RegExp(r'\sON\s+(\w+)\s*\(([^)]+)\)').firstMatch(stmt);
      final table = match?.group(1);
      if (table == null || !existingTables.contains(table)) continue;
      final cols = (await customSelect("PRAGMA table_info('$table')").get())
          .map((r) => r.data['name'] as String)
          .toSet();
      final wantedCols =
          match!.group(2)!.split(',').map((c) => c.trim().split(' ').first);
      if (wantedCols.any((c) => !cols.contains(c))) continue;
      await customStatement(stmt);
    }
  }

  /// `addColumn` yang melewati tabel yang belum ada & kolom yang sudah ada.
  /// Keduanya kondisi SAH di sini, bukan bug yang disembunyikan: langkah
  /// migrasi `alterTable` (v26) merekonstruksi tabel dari definisi Dart
  /// TERKINI sehingga kolom yang "baru" bisa sudah terbawa duluan, dan
  /// fixture test migrasi lama sengaja cuma berisi tabel yang relevan.
  Future<void> _addColumnIfMissing(String tableName, String columnName,
      TableInfo table, GeneratedColumn column, Migrator m) async {
    final cols = (await customSelect("PRAGMA table_info('$tableName')").get())
        .map((r) => r.data['name'] as String)
        .toSet();
    if (cols.isEmpty || cols.contains(columnName)) return;
    await m.addColumn(table, column);
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final stmt in _performanceIndexes) {
            await customStatement(stmt);
          }
          for (final stmt in _v30Indexes) {
            await customStatement(stmt);
          }
          await _seedDefaults();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(dailySummaries);
            for (final stmt in _performanceIndexes) {
              await customStatement(stmt);
            }
          }
          if (from < 3) {
            // Varian produk via kolom parent_product_id.
            await m.addColumn(products, products.parentProductId);
          }
          if (from < 4) {
            // Konsolidasi stok ke satuan dasar: tiap entry non-base di
            // stock_ledger dikonversi dan digabung ke satuan dasar.
            await _migrateStockToBaseUnitsV4();
          }
          if (from < 5) {
            // Pegawai toko: master data + kolom snapshot nama di transaksi.
            await m.createTable(employees);
            await m.addColumn(transactions, transactions.employeeName);
          }
          if (from < 6) {
            // Tambah belanjaan ke transaksi yang sudah dibayar: kolom penanda
            // waktu item susulan.
            await m.addColumn(transactionItems, transactionItems.addedAt);
          }
          if (from < 7) {
            // Indeks pembayaran per-transaksi (idx_tp_*). Krusial: tanpa ini
            // query pembayaran O(n^2) di DB lama yang sudah menumpuk data.
            // Jalankan ulang seluruh daftar (idempotent) agar instalasi lama
            // ikut mendapat indeks apa pun yang ditambahkan belakangan.
            for (final stmt in _performanceIndexes) {
              await customStatement(stmt);
            }
          }
          if (from < 8) {
            // Harga alternatif berlabel per satuan produk (mis. "Harga Toko
            // A" = 3000) — tap-untuk-pakai di kasir, terpisah dari tier
            // minQty di price_tiers.
            await m.createTable(altPrices);
          }
          if (from < 9) {
            // Centang "kembalian sudah diambil" di struk — mencegah kembalian
            // diserahkan dua kali untuk nota yang barangnya diambil belakangan.
            await m.addColumn(transactions, transactions.changeTaken);
          }
          if (from < 10 && from >= 8) {
            // Urutan tampil "Harga Lain" bisa direorder (drag-handle) di
            // form Produk — butuh kolom urutan eksplisit, tidak bisa lagi
            // mengandalkan createdAt (lihat komentar di tabel AltPrices).
            // Guard `from >= 8`: kalau upgrade langsung dari versi < 8,
            // `createTable(altPrices)` di atas SUDAH memakai definisi tabel
            // TERKINI (sudah termasuk sort_order) — addColumn lagi di sini
            // akan gagal "duplicate column name".
            await m.addColumn(altPrices, altPrices.sortOrder);
          }
          if (from < 11) {
            // Ambang "stok menipis" per satuan dasar (Item 11). ProductUnits
            // hanya dibuat di base schema (onCreate), TIDAK di createTable
            // migrasi inkremental mana pun — jadi tak perlu guard `from >= X`
            // seperti alt_prices.sortOrder; addColumn aman untuk semua upgrade.
            await m.addColumn(productUnits, productUnits.minStock);
          }
          if (from < 12) {
            // Tutup Kasir harian — rekap kas fisik vs sistem (Item 15).
            await m.createTable(cashClosings);
          }
          if (from < 13) {
            // Kembalian per-pembayaran (bukan cuma per-transaksi) — tiap
            // baris transaction_payments punya kembaliannya sendiri +
            // status sudah-diambil sendiri.
            await m.addColumn(
                transactionPayments, transactionPayments.changeGiven);
            await m.addColumn(
                transactionPayments, transactionPayments.changeTaken);
          }
          if (from < 14) {
            // Tanda cepat "stok habis" manual per produk (Item 25a).
            await m.addColumn(products, products.markedOutOfStock);
          }
          if (from < 15) {
            // Centang verifikasi serah-terima jadi permanen (dulu murni
            // lokal, tidak disimpan) + "Batalkan Pembayaran" per-baris.
            await m.addColumn(transactions, transactions.checkedItemIds);
            await m.addColumn(transactionPayments, transactionPayments.voided);
          }
          if (from < 16) {
            // Item 40 — usulan harga/produk dari device non-owner via sync.
            await m.addColumn(products, products.locallyModified);
          }
          if (from < 17) {
            // Item 49g — retur nota LUNAS tanpa nota baru: baris item retur
            // (qty negatif) ditandai returnedAt, pola sama dgn addedAt.
            await m.addColumn(transactionItems, transactionItems.returnedAt);
          }
          if (from < 18) {
            // Item 17 Fase 2 — antrian approval sync sisi host, PERSISTEN
            // (dulu murni in-memory `_pendingQueue` di LanSyncService, hilang
            // total kalau app di-restart sebelum owner sempat approve).
            await m.createTable(syncUploadQueue);
          }
          if (from < 19) {
            // Item 54 — kategori tambahan (many-to-many) di luar kategori
            // utama `Products.productGroupId`, + urutan tampil chip kategori
            // di tab Kasir (drag reorder).
            await m.addColumn(productGroups, productGroups.sortOrder);
            await m.createTable(productGroupTags);
          }
          if (from < 20) {
            // Item 55 — reservasi nomor nota lebih awal (sejak keranjang
            // diisi/ditahan), supaya bisa tampil stabil & ikut ter-transfer
            // via QR (Item 56).
            await m.createTable(reservedOrderNumbers);
          }
          if (from < 21 && from >= 18) {
            // Bug nyata dilaporkan user (sama persis dgn `_pendingProposals`
            // yang sudah diperbaiki 25 Juli): antrian sync_upload_queue
            // dikunci per-IP mentah, device beda yg kebetulan berbagi IP
            // (hotspot HP) saling menimpa antrian. Kolom baru dipakai sbg
            // kunci slot pengganti (nullable, fallback ke from_ip kalau
            // klien lama belum kirim deviceCode).
            // Guard `from >= 18`: kalau upgrade langsung dari versi < 18,
            // `createTable(syncUploadQueue)` di step v18 di atas SUDAH
            // memakai definisi tabel TERKINI (sudah termasuk device_code)
            // — addColumn lagi di sini akan gagal "duplicate column name".
            await m.addColumn(syncUploadQueue, syncUploadQueue.deviceCode);
          }
          if (from < 22) {
            // Item 52 ("Laci Meja") — Titip/Ketinggalan, Pinjaman Barang,
            // Pre-order.
            await m.createTable(leftBehindItems);
            await m.createTable(borrowedItems);
            await m.createTable(preorderEntries);
            await m.addColumn(productUnits, productUnits.requiresDeposit);
          }
          if (from < 23 && from >= 22) {
            // Item 52 susulan — tautan presisi entri Titip/Ketinggalan ke
            // baris nota (lihat dok kolom di laci_meja_tables.dart).
            // Guard `from >= 22`: kalau upgrade dari versi < 22,
            // `createTable(leftBehindItems)` di step v22 di atas SUDAH
            // memakai definisi tabel TERKINI (sudah termasuk kolom ini) —
            // addColumn lagi di sini akan gagal "duplicate column name".
            // Pola identik dgn guard v21 (`syncUploadQueue.deviceCode`).
            await m.addColumn(
                leftBehindItems, leftBehindItems.transactionItemId);
          }
          if (from < 24 && from >= 22) {
            // Item 52 redesain — tautan presisi entri Pinjaman ke baris
            // nota, pola identik guard v23 di atas (`leftBehindItems.
            // transactionItemId`). Guard `from >= 22`: upgrade dari versi
            // < 22 sudah dapat definisi tabel TERKINI dari `createTable`
            // di step v22.
            await m.addColumn(borrowedItems, borrowedItems.transactionItemId);
          }
          if (from < 25 && from >= 22) {
            // Item 52 susulan lagi — qty parsial Titip/Ketinggalan (bisa
            // sebagian dari qty baris nota), pola guard identik v23/v24 di
            // atas.
            await m.addColumn(leftBehindItems, leftBehindItems.qty);
          }
          if (from < 26) {
            // Bug nyata dilaporkan user: FK `customerId -> Customers` di
            // `left_behind_items`/`borrowed_items` bikin usulan Laci Meja yang
            // menaut pelanggan AD-HOC (dibuat di device kasir, tidak pernah
            // tersinkron balik ke host — pelanggan itu master data satu-arah
            // host->klien) GAGAL PERMANEN saat diterapkan di host (FOREIGN
            // KEY constraint failed). `alterTable` merekonstruksi tabel dari
            // definisi Dart TERKINI (sudah tanpa FK itu, lihat
            // laci_meja_tables.dart) — data lama ikut disalin apa adanya,
            // tidak ada yang hilang.
            //
            // `columnTransformer` WAJIB utk kolom yang baru ditambahkan di
            // migrasi SESUDAH v26 (`pinned`, v35): `alterTable` merekonstruksi
            // tabel dari definisi Dart TERKINI, jadi tabel barunya sudah punya
            // kolom itu sementara tabel lamanya belum — tanpa nilai pengganti,
            // salinannya NULL dan melanggar CHECK boolean-nya.
            await m.alterTable(TableMigration(
              leftBehindItems,
              columnTransformer: {
                leftBehindItems.lastEditedAt: const Constant<DateTime>(null),
              },
            ));
            await m.alterTable(TableMigration(
              borrowedItems,
              columnTransformer: {
                borrowedItems.pinned: const Constant(false),
                borrowedItems.lastEditedAt: const Constant<DateTime>(null),
              },
            ));
          }
          if (from < 27) {
            // Item 53 (permintaan user) — saklar "ikut harga satuan dasar"
            // per satuan jual varian.
            await m.addColumn(productUnits, productUnits.followsParentPrice);
          }
          if (from < 28) {
            // Susulan (permintaan user) — usulan sync pelanggan, pola SAMA
            // PERSIS dgn `products.locallyModified` (Item 40).
            await m.addColumn(customers, customers.locallyModified);
          }
          if (from < 29) {
            // Item 61.5 — soft-delete expenses (lihat dok `Expenses.deletedAt`).
            await m.addColumn(expenses, expenses.deletedAt);
          }
          if (from < 30) {
            // Audit efisiensi storage — indeks yang belum ada sebelumnya.
            // Tabel targetnya (price_tiers/product_barcodes/loyalty_point_
            // ledger/dkk) sudah ada sejak schemaVersion 1 di DB PRODUKSI
            // manapun (tidak pernah disentuh migrasi lain) — defensif thd
            // tabel belum ada murni utk fixture test migrasi lama yang
            // sengaja minimal (cuma tabel relevan ke migrasi yang diuji),
            // bukan replika skema penuh.
            await _createIndexesIfTableExists(_v30Indexes);
          }
          if (from < 31) {
            // Kamus belajar penerimaan barang (teks -> satuan produk).
            await m.createTable(productAliases);
          }
          if (from < 32) {
            // Riwayat Pembayaran: rincian per-produk retur/edit + sisa
            // tempo per momen (lihat dok `TransactionAdjustmentLines` &
            // `TransactionPayments.sisaAfter`).
            await m.addColumn(
                transactionPayments, transactionPayments.sisaAfter);
            await m.createTable(transactionAdjustmentLines);
          }
          if (from < 33) {
            // PLAN.md Item 54 — log kejadian Laci Meja (ambil/kembali/
            // penuhi/batal), lihat dok `LaciMejaEvents`.
            await m.createTable(laciMejaEvents);
            // BACKFILL: pinjaman SUDAH bisa kembali sebagian sejak dulu lewat
            // kolom akumulator `qty_returned`, tapi TANPA jejak per-momen.
            // Tanpa backfill, entri lama yang qty-nya sudah berkurang akan
            // tampil "belum pernah ada pengembalian" di riwayat baru —
            // seolah datanya hilang. Satu baris log historis per entri
            // mewakili SELURUH akumulasi yang sudah terjadi (momen aslinya
            // memang tidak pernah tercatat, jadi tidak bisa dipecah).
            // Waktunya pakai `updated_at` baris itu = perkiraan terbaik kapan
            // pengembalian terakhir tercatat. Id deterministik (`bf-<id>`)
            // supaya migrasi yang terulang tidak menggandakan baris.
            final tables = (await customSelect(
                        "SELECT name FROM sqlite_master WHERE type='table'")
                    .get())
                .map((r) => r.data['name'] as String)
                .toSet();
            if (tables.contains('borrowed_items')) {
              await customStatement(
                "INSERT OR IGNORE INTO laci_meja_events "
                "(id, entity_type, entry_id, aksi, qty, note, device_code, "
                " locally_modified, created_at) "
                "SELECT 'bf-' || id, 'pinjaman', id, 'kembali', qty_returned, "
                "'Dicatat sebelum riwayat per-momen ada', NULL, 0, updated_at "
                "FROM borrowed_items WHERE qty_returned > 0",
              );
            }
          }
          if (from < 34) {
            // Susulan (permintaan user) — nama SPESIFIK metode pembayaran
            // (mis. "GoPay", "BCA"), bukan cuma kategori generik yang sudah
            // ada. Lihat dok `Transactions.methodName`/
            // `TransactionPayments.methodName`. Nota lama tetap null —
            // seluruh tempat tampilan WAJIB fallback ke label generik.
            await m.addColumn(transactions, transactions.methodName);
            await m.addColumn(
                transactionPayments, transactionPayments.methodName);
          }
          if (from < 35) {
            // Laci Meja lanjutan (permintaan user): atribut entri jadi bisa
            // diedit (butuh `last_edited_at` TERPISAH dari `updated_at` yang
            // ikut tersentuh aksi operasional/sync), kartu pinjaman bisa
            // disematkan (`pinned`), dan pre-order ikut membedakan pelanggan
            // terdaftar vs nama ad-hoc (`customer_id`, kolom yang sudah lama
            // ada di 2 tabel Laci Meja lain). Semua aditif & nullable/
            // berdefault — entri lama tetap valid apa adanya.
            //
            // Defensif thd tabel/kolom yang SUDAH ada: langkah v26 memakai
            // `alterTable` yang merekonstruksi tabel dari definisi Dart
            // terkini — DB yang naik dari versi <26 karena itu sudah membawa
            // kolom-kolom ini sebelum sampai ke sini. Fixture test migrasi
            // lama juga sengaja minimal (bisa belum punya tabelnya sama
            // sekali).
            await _addColumnIfMissing('left_behind_items', 'last_edited_at',
                leftBehindItems, leftBehindItems.lastEditedAt, m);
            await _addColumnIfMissing('borrowed_items', 'last_edited_at',
                borrowedItems, borrowedItems.lastEditedAt, m);
            await _addColumnIfMissing('borrowed_items', 'pinned', borrowedItems,
                borrowedItems.pinned, m);
            await _addColumnIfMissing('preorder_entries', 'last_edited_at',
                preorderEntries, preorderEntries.lastEditedAt, m);
            await _addColumnIfMissing('preorder_entries', 'customer_id',
                preorderEntries, preorderEntries.customerId, m);
          }
          if (from < 36) {
            // Susulan (permintaan user) — kumpulkan pembayaran DP/jaminan
            // pre-order yang tadinya dikunci Rp 0 saat checkout, begitu
            // pre-order dipenuhi. Butuh tautan PRESISI ke baris nota (lihat
            // dok kolom), pola identik migrasi v35 utk 2 tabel Laci Meja
            // lain yang sudah lebih dulu punya kolom serupa.
            await _addColumnIfMissing('preorder_entries', 'transaction_item_id',
                preorderEntries, preorderEntries.transactionItemId, m);
          }
          if (from < 37) {
            // Item 62 — bug sync serius: `transactions` diperlakukan
            // append-only murni oleh `dumpSince` (filter `created_at >=
            // since` saja), jadi perubahan pada nota yang SUDAH pernah
            // tersinkron (mis. void, ganti pelanggan, poin) tidak pernah
            // terkirim lagi ke device lain. Tambah `updated_at` supaya bisa
            // difilter juga (lihat `dumpSince`/`mergeRows` case khusus
            // 'transactions').
            await _addColumnIfMissing('transactions', 'updated_at',
                transactions, transactions.updatedAt, m);
          }
          if (from < 38) {
            // Item 57 — `laci_meja_events` delta host->klien (`dumpSince`)
            // cuma pakai `created_at` (waktu kejadian fisik, tidak boleh
            // diubah), jadi event yang dibuat klien sebelum watermark sync
            // berikutnya tidak pernah lolos balik walau host sudah
            // menyetujuinya -> `locallyModified` klien nyangkut selamanya
            // & payload usulan tumbuh terus. `appliedAt` dicap saat HOST
            // menyetujui (`applyLaciMejaProposals`), dipakai tambahan di
            // filter delta `dumpSince` (lihat kolom & case khusus terkait).
            await _addColumnIfMissing('laci_meja_events', 'applied_at',
                laciMejaEvents, laciMejaEvents.appliedAt, m);
          }
          if (from < 39) {
            // Log void (permintaan user) — siapa yang membatalkan & alasan
            // opsional (lihat dok `Transactions.voidedBy`/`voidReason`).
            // Nullable & aditif, nota lama tetap valid apa adanya.
            await _addColumnIfMissing('transactions', 'voided_by',
                transactions, transactions.voidedBy, m);
            await _addColumnIfMissing('transactions', 'void_reason',
                transactions, transactions.voidReason, m);
          }
        },
        beforeOpen: (details) async {
          // Arsip dibuka read-only (query_only = ON) — jangan menulis apa pun.
          if (readOnly) return;
          // Sisipkan unit type & permission key baru (insertOrIgnore) agar DB
          // lama turut mendapat entri yang ditambahkan setelah instalasi
          // pertama (mis. permission 'batal_transaksi' di v2).
          await batch((b) {
            b.insertAll(
              unitTypes,
              _kDefaultUnitTypes.entries.map(
                (e) =>
                    UnitTypesCompanion.insert(id: Value(e.key), name: e.value),
              ),
              mode: InsertMode.insertOrReplace,
            );
            b.insertAll(
              kasirPermissions,
              [
                ...kKasirPermissionKeys,
                ...kAsistenPermissionKeys
              ].map((k) => KasirPermissionsCompanion.insert(permissionKey: k)),
              mode: InsertMode.insertOrIgnore,
            );
          });
          // Bersihkan tier duplikat (product_unit_id, min_qty) yang
          // terbentuk akibat LAN sync INSERT OR REPLACE dengan UUID berbeda.
          await customStatement('''
            DELETE FROM price_tiers WHERE id IN (
              SELECT pt.id FROM price_tiers pt
              WHERE pt.rowid NOT IN (
                SELECT MIN(rowid) FROM price_tiers
                GROUP BY product_unit_id, min_qty
              )
            )
          ''');
        },
      );

  Future<void> _seedDefaults() async {
    await batch((b) {
      // Satuan legacy. ID 7 & 8 di sistem lama = 'Biji', merge ke ID 12.
      b.insertAll(
        unitTypes,
        _kDefaultUnitTypes.entries.map(
            (e) => UnitTypesCompanion.insert(id: Value(e.key), name: e.value)),
        mode: InsertMode.insertOrIgnore,
      );
      // Group produk legacy 3–20, nama diisi manual.
      b.insertAll(
        productGroups,
        [
          for (var i = 3; i <= 20; i++)
            ProductGroupsCompanion.insert(id: Value(i))
        ],
        mode: InsertMode.insertOrIgnore,
      );
      // Permission kasir & asisten, semua default OFF.
      b.insertAll(
        kasirPermissions,
        [...kKasirPermissionKeys, ...kAsistenPermissionKeys]
            .map((k) => KasirPermissionsCompanion.insert(permissionKey: k)),
        mode: InsertMode.insertOrIgnore,
      );
      // Metode bayar bawaan: tunai selalu ada, tidak bisa dihapus di UI.
      b.insert(
        paymentMethods,
        PaymentMethodsCompanion.insert(
            id: 'pm-tunai', type: 'tunai', name: 'Tunai'),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  // ───────────────────────── Settings helpers ─────────────────────────

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// `updatedAt` distempel EKSPLISIT (bukan cuma `withDefault`) — kolom itu
  /// cuma berlaku otomatis saat INSERT, tidak pernah tersentuh saat baris
  /// yang sudah ada di-UPDATE lewat `insertOnConflictUpdate` (gotcha yang
  /// sama persis dgn soft-delete master-data lain, lihat CLAUDE.md). Tanpa
  /// ini, mengubah setting yang SUDAH pernah tersinkron sebelumnya
  /// (mis. kuota pre-order disetel ulang) tidak akan pernah lewat filter
  /// `dumpSince` `WHERE updated_at >= ?` lagi — perubahan diam-diam TIDAK
  /// PERNAH sampai ke device lain walau nilainya sendiri sudah benar lokal.
  Future<void> setSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: key,
          value: value,
          updatedAt: Value(DateTime.now()),
        ),
      );

  // ───────────────────────── Pricing queries ─────────────────────────

  Future<CustomerGroupPrice?> getCustomerGroupPrice(
      String productUnitId, String customerGroupId) {
    return (select(customerGroupPrices)
          ..where((t) =>
              t.productUnitId.equals(productUnitId) &
              t.customerGroupId.equals(customerGroupId)))
        .getSingleOrNull();
  }

  /// Tier harga untuk satu varian, diurut minQty DESC (terbesar dulu).
  Future<List<PriceTier>> getPriceTiers(String productUnitId) {
    return (select(priceTiers)
          ..where((t) => t.productUnitId.equals(productUnitId))
          ..orderBy([(t) => OrderingTerm.desc(t.minQty)]))
        .get();
  }

  /// Harga alternatif berlabel untuk satu satuan produk, diurut sesuai
  /// posisi hasil drag-reorder user di form Produk (bukan waktu dibuat).
  /// Beda dari [getPriceTiers]: bukan tier qty, murni pilihan cepat manual.
  Future<List<AltPrice>> getAltPrices(String productUnitId) {
    return (select(altPrices)
          ..where((t) => t.productUnitId.equals(productUnitId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  // ───────────────────────── Stock queries ─────────────────────────

  /// Lookup satuan dasar dan rasio dari sembarang productUnitId.
  /// Mengembalikan (id: baseUnitId, ratio: ratioToBase).
  Future<({String id, double ratio})> _baseUnitOf(String productUnitId) async {
    final unit = await (select(productUnits)
          ..where((t) => t.id.equals(productUnitId)))
        .getSingleOrNull();
    // Satuan dasar selalu rasio 1.0 (abaikan nilai kolom yang mungkin salah).
    if (unit == null || unit.isBaseUnit) {
      return (id: productUnitId, ratio: 1.0);
    }
    final base = await (select(productUnits)
          ..where((t) =>
              t.productId.equals(unit.productId) & t.isBaseUnit.equals(true))
          ..limit(1))
        .getSingleOrNull();
    // Tidak ada satuan dasar → perlakukan unit ini sebagai dasar (fallback).
    if (base == null) return (id: productUnitId, ratio: 1.0);
    return (id: base.id, ratio: unit.ratioToBase);
  }

  /// Stok mentah satuan dasar (stockAfter terakhir dalam ledger, selalu dalam
  /// satuan dasar). Tidak boleh dipanggil langsung dari luar — gunakan
  /// [currentStock].
  Future<double> _rawBaseStock(String baseUnitId) async {
    // Item 38 — tie-break dulu pakai `id` (UUID v4 ACAK), yang TIDAK
    // berkorelasi dgn urutan insert. `created_at` presisi DETIK — kalau 2
    // penulisan stok jatuh di detik yang sama (mis. `adjustStock` setup
    // langsung disusul `commitOpname` di alur otomatis/test, atau 2
    // penyesuaian manual cepat berurutan), tie-break `id DESC` bisa memilih
    // baris LAMA, bukan yang terakhir ditulis (stok jadi tampak "mundur").
    // Fix: tie-break kedua pakai `rowid` (SQLite built-in, monoton naik
    // sesuai urutan insert, tanpa perlu migrasi kolom baru).
    final row = await (select(stockLedger)
          ..where((t) => t.productUnitId.equals(baseUnitId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (_) => OrderingTerm(
                expression: const CustomExpression<int>('rowid'),
                mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row?.stockAfter ?? 0;
  }

  /// Stok terkini dalam satuan yang diminta.
  /// Semua ledger ditulis ke satuan dasar; satuan non-dasar = baseStock ÷ ratio.
  /// Rasio < 1 (satuan lebih kecil dari dasar, mis. Ons saat dasar Kg) tetap
  /// dikonversi; hanya rasio tak valid (<= 0) yang di-fallback tanpa konversi.
  Future<double> currentStock(String productUnitId) async {
    final info = await _baseUnitOf(productUnitId);
    final base = await _rawBaseStock(info.id);
    return info.ratio <= 0 ? base : base / info.ratio;
  }

  /// Item 46 — teks stok tersisa sebuah produk dalam satuan dasar + konversi
  /// ke satuan lain dalam kurung, mis. "100 biji (5 pak, 1 dus)". Satuan lain
  /// hanya ikut bila hasil konversi >= 1 (agar tidak "0 dus"). null bila
  /// produk tak punya satuan.
  Future<String?> stockBreakdownText(String productId) async {
    final units = await (select(productUnits)
          ..where((t) => t.productId.equals(productId)))
        .get();
    if (units.isEmpty) return null;
    var base = units.first;
    for (final u in units) {
      if (u.isBaseUnit) {
        base = u;
        break;
      }
    }
    final baseStock = await _rawBaseStock(base.id);
    final typeIds =
        units.map((u) => u.unitTypeId).whereType<int>().toSet().toList();
    final types = typeIds.isEmpty
        ? <UnitType>[]
        : await (select(unitTypes)..where((t) => t.id.isIn(typeIds))).get();
    final typeName = {for (final t in types) t.id: t.name};
    String fmt(double q) =>
        q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(1);
    final buf = StringBuffer('${fmt(baseStock)} '
        '${typeName[base.unitTypeId] ?? 'satuan'}');
    final others = <String>[];
    for (final u in units) {
      if (u.id == base.id || u.ratioToBase <= 0) continue;
      final q = baseStock / u.ratioToBase;
      if (q < 1) continue;
      others.add('${fmt(q)} ${typeName[u.unitTypeId] ?? 'satuan'}');
    }
    if (others.isNotEmpty) buf.write(' (${others.join(', ')})');
    return buf.toString();
  }

  /// Item 46 — dari sekumpulan productId yang BARU terjual, kembalikan pesan
  /// siap-tampil untuk produk yang stok satuan dasarnya kini <= ambang
  /// minStock (ambang hanya di satuan dasar, Item 11). Kosong bila tak ada
  /// yang menipis.
  Future<List<String>> lowStockAlertsForProducts(Set<String> productIds) async {
    final msgs = <String>[];
    for (final pid in productIds) {
      final units = await (select(productUnits)
            ..where((t) => t.productId.equals(pid)))
          .get();
      if (units.isEmpty) continue;
      ProductUnit? base;
      for (final u in units) {
        if (u.isBaseUnit) {
          base = u;
          break;
        }
      }
      base ??= units.first;
      final min = base.minStock;
      if (min == null) continue;
      final baseStock = await _rawBaseStock(base.id);
      if (baseStock > min) continue; // masih di atas ambang → bukan menipis
      final breakdown = await stockBreakdownText(pid);
      final prod = await (select(products)..where((t) => t.id.equals(pid)))
          .getSingleOrNull();
      final name = prod?.name ?? 'Produk';
      msgs.add('Stok $name menipis: sisa ${breakdown ?? '$baseStock'}');
    }
    return msgs;
  }

  /// Tulis satu entry ke stock_ledger, selalu pada satuan dasar.
  /// [productUnitId] boleh satuan apa pun; [qtyChange] dalam satuan itu.
  Future<void> _appendStock({
    required String productUnitId,
    required double qtyChange,
    required String type,
    String? referenceId,
    String? kasirId,
    String? note,
    required DateTime now,
  }) async {
    final info = await _baseUnitOf(productUnitId);
    final baseChange = qtyChange * info.ratio;
    final prevBase = await _rawBaseStock(info.id);
    await into(stockLedger).insert(StockLedgerCompanion.insert(
      id: const Uuid().v4(),
      productUnitId: info.id,
      type: type,
      qtyChange: baseChange,
      stockAfter: prevBase + baseChange,
      referenceId: Value(referenceId),
      kasirId: Value(kasirId),
      note: Value(note),
      createdAt: Value(now),
    ));
  }

  /// Penyesuaian stok manual (opname / koreksi). Tulis ke satuan dasar.
  /// [newQty] dalam satuan [productUnitId] — dikonversi ke dasar sebelum disimpan.
  /// Mengembalikan selisih dalam satuan yang diminta.
  Future<double> adjustStock({
    required String productUnitId,
    required double newQty,
    String? kasirId,
    String? note,
  }) async {
    return transaction(() async {
      final info = await _baseUnitOf(productUnitId);
      final newBase = newQty * info.ratio;
      final prevBase = await _rawBaseStock(info.id);
      final deltaBase = newBase - prevBase;
      await into(stockLedger).insert(StockLedgerCompanion.insert(
        id: const Uuid().v4(),
        productUnitId: info.id,
        type: 'adjustment',
        qtyChange: deltaBase,
        stockAfter: newBase,
        kasirId: Value(kasirId),
        note: Value(note),
        createdAt: Value(DateTime.now()),
      ));
      // Kembalikan delta dalam satuan yang diminta UI.
      return info.ratio <= 0 ? deltaBase : deltaBase / info.ratio;
    });
  }

  /// Migrasi v4: konversi semua entry stock_ledger non-base ke satuan dasar.
  /// Hanya menjaga saldo akhir (tidak mereplikasi riwayat per entry).
  Future<void> _migrateStockToBaseUnitsV4() async {
    final now = DateTime.now();
    // Ambil semua satuan non-dasar yang punya entri di ledger.
    final rows = await customSelect(
      'SELECT pu.id, pu.ratio_to_base, pu.product_id '
      'FROM product_units pu '
      'WHERE pu.is_base_unit = 0 '
      '  AND EXISTS (SELECT 1 FROM stock_ledger sl WHERE sl.product_unit_id = pu.id)',
    ).get();

    for (final row in rows) {
      final unitId = row.data['id'] as String;
      final ratio = (row.data['ratio_to_base'] as num).toDouble();
      final productId = row.data['product_id'] as String;

      // Saldo non-base dari entry terakhir (dalam satuan non-base).
      final lastRow = await customSelect(
        'SELECT stock_after FROM stock_ledger '
        'WHERE product_unit_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1',
        variables: [Variable.withString(unitId)],
      ).getSingleOrNull();
      if (lastRow == null) continue;
      final nonBaseStock = (lastRow.data['stock_after'] as num).toDouble();

      // Hapus semua entry non-base (tidak lagi diperlukan).
      await customStatement(
        'DELETE FROM stock_ledger WHERE product_unit_id = ?',
        [unitId],
      );

      if (nonBaseStock <= 0) continue; // tidak perlu tambah ke dasar

      // Cari satuan dasar produk ini.
      final baseRow = await customSelect(
        'SELECT id FROM product_units WHERE product_id = ? AND is_base_unit = 1 LIMIT 1',
        variables: [Variable.withString(productId)],
      ).getSingleOrNull();
      if (baseRow == null) continue;
      final baseUnitId = baseRow.data['id'] as String;

      // Saldo dasar saat ini.
      final baseLastRow = await customSelect(
        'SELECT stock_after FROM stock_ledger '
        'WHERE product_unit_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 1',
        variables: [Variable.withString(baseUnitId)],
      ).getSingleOrNull();
      final currentBase = baseLastRow != null
          ? (baseLastRow.data['stock_after'] as num).toDouble()
          : 0.0;

      final contrib = nonBaseStock * ratio;
      await into(stockLedger).insert(StockLedgerCompanion.insert(
        id: const Uuid().v4(),
        productUnitId: baseUnitId,
        type: 'adjustment',
        qtyChange: contrib,
        stockAfter: currentBase + contrib,
        note: const Value('Migrasi stok ke satuan dasar'),
        createdAt: Value(now),
      ));
    }
  }

  // ───────────────────────── Transaction helpers ─────────────────────────

  /// Nomor nota harian yang dijamin unik. Penjualan dan retur berbagi ruang
  /// penghitung yang sama, sehingga menghitung jumlah transaksi hari ini +1
  /// mentah bisa bertabrakan. Method ini mencari sequence bebas berikutnya
  /// dengan memeriksa localId yang sudah ada. Item 55 — juga menghindari
  /// nomor yang sedang DIRESERVASI (`reserved_order_numbers`, mis. keranjang
  /// lain yang belum checkout) supaya tidak bentrok begitu keranjang itu
  /// akhirnya dibayar. Dipakai sbg FALLBACK saat checkout tanpa
  /// `CartMeta.reservedLocalId` (seharusnya jarang terjadi di alur normal —
  /// lihat `reserveLocalId`, dipanggil lebih awal saat keranjang mulai
  /// diisi/ditahan).
  Future<String> generateUniqueLocalId(String deviceCode,
      [DateTime? at]) async {
    final prefix = _localIdPrefix(deviceCode, at ?? DateTime.now());
    final used = await _usedLocalIdsWithPrefix(prefix);
    return _nextFreeLocalId(prefix, used);
  }

  /// Item 55 — reserve nomor nota LEBIH AWAL (sebelum ada baris `transactions`
  /// sungguhan), sejak keranjang mulai diisi atau ditahan — supaya nomor
  /// "urutan pelanggan yang harus dilayani" tampil stabil di cart bar & kartu
  /// pesanan tertahan, dan ikut terbawa utuh saat transfer via QR (Item 56).
  /// Nomor dicatat ke `reserved_order_numbers` (bukan `transactions`) supaya
  /// reservasi keranjang LAIN yang juga belum checkout tidak kebentur nomor
  /// yang sama. Lepaskan dengan [releaseLocalId] setelah dikonsumsi jadi
  /// transaksi sungguhan, atau saat keranjang dibatalkan.
  Future<String> reserveLocalId(String deviceCode, [DateTime? at]) async {
    final prefix = _localIdPrefix(deviceCode, at ?? DateTime.now());
    final used = await _usedLocalIdsWithPrefix(prefix);
    final candidate = _nextFreeLocalId(prefix, used);
    await into(reservedOrderNumbers)
        .insert(ReservedOrderNumbersCompanion.insert(localId: candidate));
    return candidate;
  }

  /// Lepaskan reservasi [localId] — dipanggil setelah nomor dikonsumsi jadi
  /// `transactions.local_id` sungguhan, atau saat keranjang yang mereservasi
  /// dibatalkan/dikosongkan tanpa checkout.
  Future<void> releaseLocalId(String localId) =>
      (delete(reservedOrderNumbers)..where((t) => t.localId.equals(localId)))
          .go();

  /// Daftarkan ulang nomor nota yang DIBAWA MASUK dari device lain (transfer
  /// QR, Item 56) ke `reserved_order_numbers` di device INI.
  ///
  /// Bug nyata dilaporkan user: pesanan dipindah owner→asisten via QR lalu
  /// dikembalikan asisten→owner, saat checkout gagal total dgn "UNIQUE
  /// constraint failed: transactions.local_id". Akarnya: nomor yang
  /// diterima lewat QR cuma disimpan di `CartMeta.reservedLocalId`
  /// (in-memory/JSON keranjang) tanpa PERNAH dicatat ke
  /// `reserved_order_numbers` device penerima — jadi `reserveLocalId`
  /// berikutnya di device itu tidak tahu nomor tsb sedang dipakai dan
  /// membagikannya lagi ke keranjang LAIN. Begitu keranjang lain itu
  /// checkout duluan, nomornya jadi milik `transactions`, dan keranjang
  /// hasil transfer tadi menabrak UNIQUE saat gilirannya bayar.
  ///
  /// `insertOrIgnore`: aman dipanggil berkali-kali (mis. QR yang sama
  /// di-scan ulang) & aman kalau nomor itu memang sudah direservasi di sini.
  Future<void> adoptReservedLocalId(String localId) =>
      into(reservedOrderNumbers).insert(
          ReservedOrderNumbersCompanion.insert(localId: localId),
          mode: InsertMode.insertOrIgnore);

  /// true bila [localId] SUDAH dipakai baris `transactions` sungguhan —
  /// dipakai checkout utk mendeteksi nomor reservasi basi sebelum insert
  /// (lihat dok `adoptReservedLocalId` soal bagaimana itu bisa terjadi).
  Future<bool> isLocalIdTaken(String localId) async =>
      (await (select(transactions)..where((t) => t.localId.equals(localId)))
          .getSingleOrNull()) !=
      null;

  String _localIdPrefix(String deviceCode, DateTime at) {
    final datePart = '${at.year}'
        '${at.month.toString().padLeft(2, '0')}'
        '${at.day.toString().padLeft(2, '0')}';
    return '$deviceCode-$datePart-';
  }

  Future<Set<String>> _usedLocalIdsWithPrefix(String prefix) async {
    final existingTx = await (select(transactions)
          ..where((t) => t.localId.like('$prefix%')))
        .get();
    final existingReserved = await (select(reservedOrderNumbers)
          ..where((t) => t.localId.like('$prefix%')))
        .get();
    return {
      ...existingTx.map((t) => t.localId),
      ...existingReserved.map((r) => r.localId),
    };
  }

  String _nextFreeLocalId(String prefix, Set<String> used) {
    var seq = used.length + 1;
    var candidate = '$prefix${seq.toString().padLeft(4, '0')}';
    while (used.contains(candidate)) {
      seq++;
      candidate = '$prefix${seq.toString().padLeft(4, '0')}';
    }
    return candidate;
  }

  /// Qty yang sudah diretur per productUnitId untuk transaksi asal [originalTxId].
  /// Dipakai untuk mencegah retur melebihi jumlah pembelian (double-retur).
  Future<Map<String, double>> getReturnedQtyByUnit(String originalTxId) async {
    final rows = await customSelect(
      'SELECT ti.product_unit_id AS uid, '
      'COALESCE(SUM(-ti.qty), 0) AS qty '
      'FROM transaction_items ti '
      'JOIN transactions t ON t.id = ti.transaction_id '
      "WHERE t.internal_note = ? AND t.status != 'void' "
      'GROUP BY ti.product_unit_id',
      variables: [Variable.withString('RETUR:$originalTxId')],
      readsFrom: {transactionItems, transactions},
    ).get();
    final out = <String, double>{};
    for (final r in rows) {
      out[r.data['uid'] as String] = (r.data['qty'] as num).toDouble();
    }
    return out;
  }

  // ───────────────────────── Stok menipis (Item 11) ────────────────────────

  /// SQL: baris satuan DASAR aktif yang punya ambang minStock DAN stok
  /// terkini (stock_after ledger terbaru) < ambang. Diurut paling kritis dulu.
  static const _lowStockSql = '''
    SELECT * FROM (
      SELECT pu.product_id AS pid, p.name AS name, pu.min_stock AS min_stock,
        COALESCE((SELECT sl.stock_after FROM stock_ledger sl
                  WHERE sl.product_unit_id = pu.id
                  ORDER BY sl.created_at DESC, sl.rowid DESC LIMIT 1), 0) AS stock
      FROM product_units pu
      JOIN products p ON p.id = pu.product_id
      WHERE pu.is_base_unit = 1 AND pu.min_stock IS NOT NULL AND p.is_active = 1
    ) WHERE stock < min_stock
    ORDER BY (stock - min_stock) ASC''';

  /// Stream jumlah produk yang stoknya menipis (untuk badge tab Produk).
  Stream<int> watchLowStockCount() {
    return customSelect(
      'SELECT COUNT(*) AS c FROM ($_lowStockSql)',
      readsFrom: {productUnits, products, stockLedger},
    ).watchSingle().map((r) => (r.data['c'] as int?) ?? 0);
  }

  /// Set id produk yang stoknya menipis (untuk filter daftar Produk).
  Future<Set<String>> getLowStockProductIds() async {
    final rows = await customSelect(_lowStockSql,
        readsFrom: {productUnits, products, stockLedger}).get();
    return rows.map((r) => r.data['pid'] as String).toSet();
  }

  /// Stok riil (base unit) produk aktif yang STOK-nya AKTIF DILACAK
  /// (`isNonStock == false` DAN minimal punya 1 baris `stock_ledger`) —
  /// dipakai Item 29 (katalog HTML auto-tandai "habis" dari stok sungguhan)
  /// & Item 30 (kontrol stok owner). SENGAJA pakai `EXISTS` (bukan
  /// `COALESCE(...,0)`) — produk yang BELUM PERNAH disentuh stoknya sama
  /// sekali (baru ditambah, belum sempat "Atur Stok") secara teknis
  /// `stock_after` terakhirnya kosong, TAPI itu bukan berarti stoknya
  /// sungguhan 0 — cuma belum pernah dilacak. Kalau tetap diperlakukan
  /// sbg 0, produk yg owner memang tidak berniat lacak stoknya (banyak
  /// toko kecil pakai katalog HTML murni utk harga, bukan stok) akan
  /// mendadak tampil "Stok Habis" di katalog publik tanpa alasan nyata.
  /// Produk non-stok ATAU belum pernah punya histori ledger SENGAJA tidak
  /// masuk map — pemanggil harus treat "tidak ada di map" sbg "tidak
  /// berlaku ambang stok riil", bukan 0. Agregat 1 query, bukan N+1 per
  /// produk (§Pola Arsitektur CLAUDE.md).
  Future<Map<String, double>> getBaseUnitRealStock() async {
    final rows = await customSelect('''
      SELECT pu.product_id AS pid,
        (SELECT sl.stock_after FROM stock_ledger sl
         WHERE sl.product_unit_id = pu.id
         ORDER BY sl.created_at DESC, sl.rowid DESC LIMIT 1) AS stock
      FROM product_units pu
      JOIN products p ON p.id = pu.product_id
      WHERE pu.is_base_unit = 1 AND pu.is_non_stock = 0 AND p.is_active = 1
        AND EXISTS (SELECT 1 FROM stock_ledger sl
                    WHERE sl.product_unit_id = pu.id)
    ''', readsFrom: {productUnits, products, stockLedger}).get();
    return {
      for (final r in rows)
        r.data['pid'] as String: (r.data['stock'] as num).toDouble(),
    };
  }

  /// Baris overview stok utk Item 30 ("Cek Stok" — kontrol stok manual
  /// owner). BEDA tujuan dari [getBaseUnitRealStock] (Item 29, katalog
  /// publik): di sini layar SENGAJA dibuka owner utk MEREVIEW stok, jadi
  /// produk yang belum pernah disentuh stoknya TETAP tampil sbg "0" (biar
  /// kelihatan perlu dicek/diisi) — bukan disembunyikan spt di Item 29.
  Stream<List<StockOverviewRow>> watchStockOverview({int? groupId}) {
    final variables = <Variable<Object>>[];
    var where =
        'pu.is_base_unit = 1 AND pu.is_non_stock = 0 AND p.is_active = 1';
    if (groupId != null) {
      where += ' AND p.product_group_id = ?';
      variables.add(Variable<Object>(groupId));
    }
    return customSelect(
            '''
      SELECT pu.id AS unit_id, pu.product_id AS pid, p.name AS name,
        p.product_group_id AS group_id, pu.min_stock AS min_stock,
        p.marked_out_of_stock AS marked_out_of_stock,
        pu.requires_deposit AS requires_deposit,
        COALESCE((SELECT sl.stock_after FROM stock_ledger sl
                  WHERE sl.product_unit_id = pu.id
                  ORDER BY sl.created_at DESC, sl.rowid DESC LIMIT 1), 0) AS stock
      FROM product_units pu
      JOIN products p ON p.id = pu.product_id
      WHERE $where
      ORDER BY stock ASC
    ''',
            variables: variables,
            readsFrom: {productUnits, products, stockLedger})
        .watch()
        .map((rows) => rows
            .map((r) => (
                  productId: r.data['pid'] as String,
                  unitId: r.data['unit_id'] as String,
                  name: r.data['name'] as String,
                  groupId: r.data['group_id'] as int?,
                  stock: (r.data['stock'] as num).toDouble(),
                  minStock: (r.data['min_stock'] as num?)?.toDouble(),
                  markedOutOfStock: (r.data['marked_out_of_stock'] as int) == 1,
                  requiresDeposit: (r.data['requires_deposit'] as int) == 1,
                ))
            .toList());
  }

  /// Commit hasil satu sesi stock opname sekaligus (Item 36). Semua baris
  /// ledger dalam sesi ini memakai [note] & satu timestamp yang SAMA PERSIS
  /// (di-capture SEKALI di sini, bukan per-baris) — supaya
  /// [getOpnameSessions] bisa mengelompokkannya kembali jadi satu sesi
  // ───────────────── Penerimaan Barang + kamus belajar ─────────────────

  /// Cari satuan produk untuk satu baris teks penerimaan.
  ///
  /// Urutan (SEMUA persis, TIDAK ada fuzzy — keputusan user):
  ///   1. Kamus, kunci SPESIFIK-satuan (`nama|satuan`).
  ///   2. Kamus, kunci TANPA satuan (`nama|`) — fallback tingkat 2, pola
  ///      sama `nkLearn` di tools user.
  ///   3. Nama produk PERSIS (setelah normalisasi) — kalau cuma ada SATU
  ///      produk yang cocok. Lebih dari satu = ambigu, biar user yang pilih.
  /// null = tidak ketemu / ambigu → UI menampilkan dropdown kandidat.
  Future<String?> resolveReceiveUnit({
    required String name,
    required String unit,
  }) async {
    final nName = AliasKey.normalizeName(name);
    final nUnit = AliasKey.normalizeUnit(unit);

    for (final key in [nUnit, '']) {
      final hit = await (select(productAliases)
            ..where((t) =>
                t.normalizedName.equals(nName) & t.normalizedUnit.equals(key)))
          .getSingleOrNull();
      if (hit != null) {
        // Alias bisa menunjuk satuan yang sudah dihapus sejak dipelajari —
        // jangan kembalikan id hantu yang nanti gagal saat menulis stok.
        final unitRow = await (select(productUnits)
              ..where((t) => t.id.equals(hit.productUnitId)))
            .getSingleOrNull();
        if (unitRow != null) return hit.productUnitId;
      }
    }

    // Nama persis — dibandingkan setelah normalisasi yang SAMA dgn kamus.
    final rows = await customSelect(
      'SELECT pu.id AS uid FROM products p '
      'JOIN product_units pu ON pu.product_id = p.id '
      'WHERE p.is_active = 1 AND pu.is_base_unit = 1 '
      "AND LOWER(TRIM(p.name)) = ?",
      variables: [Variable.withString(nName)],
      readsFrom: {products, productUnits},
    ).get();
    if (rows.length == 1) return rows.single.data['uid'] as String;
    return null;
  }

  /// Simpan/perbarui satu entri kamus. Dipanggil begitu user memilih produk
  /// untuk baris yang ambigu — supaya teks yang sama tidak ditanya lagi.
  ///
  /// Menulis DUA kunci sekaligus saat teksnya bersatuan: kunci spesifik
  /// (`nama|satuan`) DAN kunci fallback (`nama|`) — jadi baris berikutnya
  /// yang menyebut produk sama TANPA satuan (atau dgn satuan beda) tetap
  /// ketemu, persis perilaku 2-tingkat di tools user.
  Future<void> learnReceiveAlias({
    required String name,
    required String unit,
    required String productUnitId,
  }) async {
    final nName = AliasKey.normalizeName(name);
    final nUnit = AliasKey.normalizeUnit(unit);
    final now = DateTime.now();
    for (final key in {nUnit, ''}) {
      final existing = await (select(productAliases)
            ..where((t) =>
                t.normalizedName.equals(nName) & t.normalizedUnit.equals(key)))
          .getSingleOrNull();
      if (existing != null) {
        await (update(productAliases)..where((t) => t.id.equals(existing.id)))
            .write(ProductAliasesCompanion(
          productUnitId: Value(productUnitId),
          // WAJIB dicap ulang — `dumpSince` memfilter `updated_at >= since`.
          updatedAt: Value(now),
        ));
      } else {
        await into(productAliases).insert(ProductAliasesCompanion.insert(
          id: const Uuid().v4(),
          normalizedName: nName,
          normalizedUnit: key,
          productUnitId: productUnitId,
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
      }
    }
  }

  /// Seluruh isi kamus + nama produk/satuannya — untuk layar kelola kamus.
  Future<List<ReceiveAliasRow>> getReceiveAliases() async {
    final rows = await customSelect(
      'SELECT a.id AS id, a.normalized_name AS nm, a.normalized_unit AS un, '
      '  a.product_unit_id AS uid, p.name AS pname '
      'FROM product_aliases a '
      'LEFT JOIN product_units pu ON pu.id = a.product_unit_id '
      'LEFT JOIN products p ON p.id = pu.product_id '
      'ORDER BY a.normalized_name, a.normalized_unit',
      readsFrom: {productAliases, productUnits, products},
    ).get();
    return rows
        .map((r) => (
              id: r.data['id'] as String,
              normalizedName: r.data['nm'] as String,
              normalizedUnit: r.data['un'] as String,
              productUnitId: r.data['uid'] as String,
              productName: r.data['pname'] as String?,
            ))
        .toList();
  }

  Future<void> deleteReceiveAlias(String id) =>
      (delete(productAliases)..where((t) => t.id.equals(id))).go();

  /// Terapkan penerimaan barang: TAMBAH stok sebesar qty tiap baris.
  ///
  /// BEDA MENDASAR dari [commitOpname] yang MENIMPA stok jadi hasil hitung
  /// fisik — di sini qty adalah barang yang DATANG, jadi ditambahkan ke stok
  /// yang sudah ada. Ditulis sbg `stock_ledger` type `purchase`, satu
  /// timestamp & note yang sama untuk seluruh sesi supaya bisa
  /// direkonstruksi jadi satu penerimaan (pola sama sesi opname).
  Future<void> commitReceive({
    required List<({String productUnitId, double qty})> entries,
    required String note,
    String? kasirId,
  }) async {
    if (entries.isEmpty) return;
    final at = DateTime.now();
    await transaction(() async {
      for (final e in entries) {
        if (e.qty <= 0) continue;
        // Konversi ke satuan DASAR — stok di app ini SELALU dianker ke
        // satuan dasar (lihat dok `variantSaleUnit`/`_appendStock`).
        final info = await _baseUnitOf(e.productUnitId);
        await _appendStock(
          productUnitId: info.id,
          qtyChange: e.qty * info.ratio,
          type: 'purchase',
          kasirId: kasirId,
          note: note,
          now: at,
        );
      }
    });
  }

  /// Konvensi note sesi penerimaan — dipakai saat commit DAN saat memfilter
  /// riwayat, harus selalu sinkron (pola sama [buildOpnameNote]).
  static String buildReceiveNote(DateTime at) {
    final tgl = '${at.day.toString().padLeft(2, '0')} '
        '${_bulanIndo[at.month - 1]} ${at.year}';
    return 'Penerimaan $tgl';
  }

  /// riwayat. [entries] hanya berisi produk yang selisihnya != 0 (pemanggil
  /// bertanggung jawab menyaring produk yang tidak berubah sebelum commit).
  Future<void> commitOpname({
    required List<({String productUnitId, double newQty})> entries,
    required String note,
    String? kasirId,
  }) async {
    final sessionAt = DateTime.now();
    await transaction(() async {
      for (final e in entries) {
        final info = await _baseUnitOf(e.productUnitId);
        final newBase = e.newQty * info.ratio;
        final prevBase = await _rawBaseStock(info.id);
        final deltaBase = newBase - prevBase;
        await into(stockLedger).insert(StockLedgerCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: info.id,
          type: 'adjustment',
          qtyChange: deltaBase,
          stockAfter: newBase,
          kasirId: Value(kasirId),
          note: Value(note),
          createdAt: Value(sessionAt),
        ));
      }
    });
  }

  /// Riwayat sesi stock opname (Item 36) — dikelompokkan dari `stock_ledger`
  /// by (createdAt, note) yang identik (lihat [commitOpname]). Note sesi
  /// opname SELALU diawali `"Opname "` (konvensi penamaan, lihat
  /// [buildOpnameNote]) — jadi filter `LIKE` ini aman membedakannya dari
  /// penyesuaian stok manual biasa ("Penyesuaian manual").
  Future<List<OpnameSessionSummary>> getOpnameSessions() async {
    final rows = await (select(stockLedger)
          ..where((t) => t.type.equals('adjustment') & t.note.like('Opname %'))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    final grouped = <String, List<StockLedgerData>>{};
    for (final r in rows) {
      final key = '${r.createdAt.millisecondsSinceEpoch}|${r.note}';
      grouped.putIfAbsent(key, () => []).add(r);
    }
    // HPP per satuan diambil SEKALI utk seluruh unit yang tersentuh (bukan
    // per-sesi/per-baris) — hindari N+1 di layar riwayat yang bisa berisi
    // puluhan sesi × puluhan baris.
    final costByUnit =
        await _costPriceByUnitIds(rows.map((r) => r.productUnitId).toSet());
    final sessions = grouped.values
        .map((list) => (
              createdAt: list.first.createdAt,
              note: list.first.note!,
              itemCount: list.length,
              valueChange: list.fold<int>(
                  0,
                  (s, r) =>
                      s +
                      (r.qtyChange * (costByUnit[r.productUnitId] ?? 0))
                          .round()),
            ))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }

  /// HPP (tier `min_qty = 1`) per `product_unit_id` — satu query utk semua id
  /// sekaligus. Unit tanpa tier harga tidak muncul di map (dianggap 0 oleh
  /// pemanggil), bukan error: opname tetap sah walau HPP belum pernah diisi.
  Future<Map<String, int>> _costPriceByUnitIds(Set<String> unitIds) async {
    if (unitIds.isEmpty) return {};
    final ids = unitIds.toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await customSelect(
      'SELECT product_unit_id AS uid, cost_price AS cp FROM price_tiers '
      'WHERE min_qty = 1 AND product_unit_id IN ($placeholders)',
      variables: [for (final id in ids) Variable.withString(id)],
      readsFrom: {priceTiers},
    ).get();
    return {
      for (final r in rows)
        r.data['uid'] as String: ((r.data['cp'] as num?) ?? 0).toInt(),
    };
  }

  /// Detail per-produk satu sesi opname — dipanggil dari layar riwayat saat
  /// user tap salah satu sesi di [getOpnameSessions]. 3 query total (ledger →
  /// unit → produk), bukan N+1 per baris.
  Future<List<OpnameSessionDetailRow>> getOpnameSessionDetail({
    required DateTime createdAt,
    required String note,
  }) async {
    final ledgerRows = await (select(stockLedger)
          ..where((t) =>
              t.type.equals('adjustment') &
              t.note.equals(note) &
              t.createdAt.equals(createdAt)))
        .get();
    if (ledgerRows.isEmpty) return [];
    final unitIds = ledgerRows.map((r) => r.productUnitId).toSet().toList();
    final unitRows =
        await (select(productUnits)..where((u) => u.id.isIn(unitIds))).get();
    final productIdByUnit = {for (final u in unitRows) u.id: u.productId};
    final productIds = productIdByUnit.values.toSet().toList();
    final productRows =
        await (select(products)..where((p) => p.id.isIn(productIds))).get();
    final nameByProduct = {for (final p in productRows) p.id: p.name};
    final costByUnit = await _costPriceByUnitIds(unitIds.toSet());
    final out = ledgerRows.map((r) {
      final pid = productIdByUnit[r.productUnitId];
      final name = pid != null
          ? (nameByProduct[pid] ?? r.productUnitId)
          : r.productUnitId;
      final cost = costByUnit[r.productUnitId] ?? 0;
      return (
        productName: name,
        qtyChange: r.qtyChange,
        stockAfter: r.stockAfter,
        costPrice: cost,
        valueChange: (r.qtyChange * cost).round(),
      );
    }).toList()
      ..sort((a, b) => a.productName.compareTo(b.productName));
    return out;
  }

  /// Konvensi penamaan note sesi opname (Item 36) — dipakai saat commit DAN
  /// saat filter riwayat ([getOpnameSessions]), harus selalu sinkron.
  ///
  /// [isReset] (susulan, permintaan user) — sesi "Reset Stok" (fitur
  /// terpisah dari opname biasa, semua produk terpilih ditimpa jadi 0
  /// tanpa hitung fisik) TETAP diawali `"Opname "` supaya otomatis muncul
  /// di [getOpnameSessions]/riwayat yang sudah ada — tidak perlu layar
  /// riwayat baru, cukup label scope-nya beda ("Reset ke 0 - ...") supaya
  /// tetap bisa dibedakan dari opname sungguhan saat ditinjau.
  static String buildOpnameNote(DateTime at,
      {String? categoryLabel, bool isReset = false}) {
    final tgl = '${at.day.toString().padLeft(2, '0')} '
        '${_bulanIndo[at.month - 1]} ${at.year}';
    final scopeBase =
        categoryLabel == null ? 'Seluruh' : 'Kategori: $categoryLabel';
    final scope = isReset ? 'Reset ke 0 - $scopeBase' : scopeBase;
    return 'Opname $tgl ($scope)';
  }

  static const _bulanIndo = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  /// Baris mentah utk laporan nilai inventori (Item 30(c), tab Laporan) —
  /// agregasi (per-kategori/grand-total/deteksi harga pokok kosong) dihitung
  /// di layer UI dari list ini, bukan di SQL — laporan, bukan hot-path,
  /// & lebih mudah diuji/dibaca sbg logika Dart murni. 1 query, bukan N+1.
  Future<List<InventoryRow>> getInventoryRows() async {
    final rows = await customSelect('''
      SELECT p.id AS pid, p.name AS name, p.product_group_id AS group_id,
        COALESCE((SELECT sl.stock_after FROM stock_ledger sl
                  WHERE sl.product_unit_id = pu.id
                  ORDER BY sl.created_at DESC, sl.rowid DESC LIMIT 1), 0) AS stock,
        COALESCE(pt.cost_price, 0) AS cost_price
      FROM product_units pu
      JOIN products p ON p.id = pu.product_id
      LEFT JOIN price_tiers pt ON pt.product_unit_id = pu.id AND pt.min_qty = 1
      WHERE pu.is_base_unit = 1 AND pu.is_non_stock = 0 AND p.is_active = 1
    ''', readsFrom: {productUnits, products, stockLedger, priceTiers}).get();
    return rows
        .map((r) => (
              productId: r.data['pid'] as String,
              name: r.data['name'] as String,
              groupId: r.data['group_id'] as int?,
              stock: (r.data['stock'] as num).toDouble(),
              costPrice: (r.data['cost_price'] as num).toInt(),
            ))
        .toList();
  }

  // ───────────────────────── Tutup Kasir (Item 15) ─────────────────────────

  /// Rekap kas hari ini: total tunai (paid), non-tunai (paid), jumlah nota.
  /// Non-void; 'tempo' (belum dibayar) tidak dihitung sebagai kas masuk.
  Future<({int cash, int nonCash, int txCount})> getTodayCashRecap(
      DateTime from, DateTime to) async {
    final row = await customSelect(
      "SELECT "
      "COALESCE(SUM(CASE WHEN payment_method='tunai' THEN paid ELSE 0 END),0) AS cash, "
      "COALESCE(SUM(CASE WHEN payment_method NOT IN ('tunai','tempo') THEN paid ELSE 0 END),0) AS noncash, "
      "COUNT(*) AS cnt "
      "FROM transactions WHERE status != 'void' "
      "AND created_at >= ? AND created_at <= ?",
      variables: [
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {transactions},
    ).getSingle();
    return (
      cash: (row.data['cash'] as num).toInt(),
      nonCash: (row.data['noncash'] as num).toInt(),
      txCount: row.data['cnt'] as int,
    );
  }

  /// Simpan/timpa tutup kasir untuk (tanggal, device) — satu entri per hari.
  Future<void> saveCashClosing(CashClosingsCompanion entry) =>
      into(cashClosings).insertOnConflictUpdate(entry);

  Stream<List<CashClosing>> watchCashClosings() =>
      (select(cashClosings)..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  Future<bool> isPermissionEnabled(String key) async {
    final row = await (select(kasirPermissions)
          ..where((t) => t.permissionKey.equals(key)))
        .getSingleOrNull();
    return row?.isEnabled ?? false;
  }

  // ───────────────────────── Product queries ─────────────────────────

  Future<List<Product>> searchProducts(String query) {
    final q = (select(products)..where((t) => t.isActive.equals(true)));
    if (query.isNotEmpty) {
      q.where((t) =>
          t.name.lower().contains(query.toLowerCase()) |
          t.kodeProduk.lower().contains(query.toLowerCase()));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.get();
  }

  Stream<List<Product>> watchProducts({String query = '', int? groupId}) {
    final q = (select(products)
      ..where((t) => t.isActive.equals(true))
      // Sembunyikan varian (produk anak) dari katalog utama.
      ..where((t) => t.parentProductId.isNull()));
    if (query.isNotEmpty) {
      // Cari berdasarkan nama ATAU kode produk (SKU). Contoh: ketik "GBF"
      // memunculkan "Gajah Baru Filter" yang kode_produk-nya GBF.
      q.where((t) =>
          t.name.lower().contains(query.toLowerCase()) |
          t.kodeProduk.lower().contains(query.toLowerCase()));
    }
    if (groupId != null) {
      q.where((t) => t.productGroupId.equals(groupId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
  }

  /// Item 54 — versi [watchProducts] untuk chip kategori tab Kasir: filter
  /// [groupId] mencakup UNION kategori utama (`productGroupId`) ATAU
  /// kategori tambahan (`product_group_tags`) — beda dari [watchProducts]
  /// yang dipakai filter kategori di tab Produk (`produk_list_screen.dart`),
  /// SENGAJA tetap primary-only di sana (di luar scope Item 54, tidak
  /// disentuh). Tanpa `groupId`, perilaku identik [watchProducts].
  Stream<List<Product>> watchProductsForKasir(
      {String query = '', int? groupId}) {
    if (groupId == null) return watchProducts(query: query);
    final q = select(products).join([
      leftOuterJoin(
        productGroupTags,
        productGroupTags.productId.equalsExp(products.id) &
            productGroupTags.groupId.equals(groupId),
      ),
    ])
      ..where(products.isActive.equals(true))
      ..where(products.parentProductId.isNull())
      ..where(products.productGroupId.equals(groupId) |
          productGroupTags.groupId.equals(groupId));
    if (query.isNotEmpty) {
      final ql = query.toLowerCase();
      q.where(products.name.lower().contains(ql) |
          products.kodeProduk.lower().contains(ql));
    }
    q.orderBy([OrderingTerm.asc(products.name)]);
    return q
        .watch()
        .map((rows) => rows.map((r) => r.readTable(products)).toList());
  }

  /// Harga dasar (tier minQty=1) tiap produk pada satuan DASARnya — dipakai
  /// tab Produk utk tampilkan harga di bawah nama tanpa N+1 query per baris.
  Future<Map<String, int>> getBaseUnitPrices() async {
    final rows = await customSelect(
      'SELECT pu.product_id AS product_id, pt.price AS price '
      'FROM product_units pu '
      'JOIN price_tiers pt ON pt.product_unit_id = pu.id AND pt.min_qty = 1 '
      'WHERE pu.is_base_unit = 1',
      readsFrom: {productUnits, priceTiers},
    ).get();
    return {
      for (final r in rows)
        r.data['product_id'] as String: (r.data['price'] as num).toInt(),
    };
  }

  /// Item 17 — versi reaktif [getBaseUnitPrices]: harga di daftar produk
  /// ikut ter-update begitu tier harga diubah di form Produk, tanpa perlu
  /// layar ditutup-buka ulang (`_basePricesProvider` sebelumnya snapshot
  /// sekali, tidak refresh selama widget masih hidup di Navigator stack).
  Stream<Map<String, int>> watchBaseUnitPrices() {
    return customSelect(
      'SELECT pu.product_id AS product_id, pt.price AS price '
      'FROM product_units pu '
      'JOIN price_tiers pt ON pt.product_unit_id = pu.id AND pt.min_qty = 1 '
      'WHERE pu.is_base_unit = 1',
      readsFrom: {productUnits, priceTiers},
    ).watch().map((rows) => {
          for (final r in rows)
            r.data['product_id'] as String: (r.data['price'] as num).toInt(),
        });
  }

  /// Varian (produk anak) aktif milik [parentProductId], urut nama.
  Future<List<Product>> getVariants(String parentProductId) => (select(products)
        ..where((t) =>
            t.parentProductId.equals(parentProductId) & t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();

  /// Ambil satu produk berdasarkan id (mis. saat membuka modal edit item dari
  /// keranjang). Mengembalikan null bila tidak ditemukan.
  Future<Product?> getProductById(String id) =>
      (select(products)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<Product>> watchVariants(String parentProductId) =>
      (select(products)
            ..where((t) =>
                t.parentProductId.equals(parentProductId) &
                t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  /// Map productId → parentProductId untuk daftar produk tertentu (dipakai
  /// struk untuk menyusun varian di bawah induk). Hanya yang punya induk.
  Future<Map<String, String>> getParentMap(List<String> productIds) async {
    if (productIds.isEmpty) return {};
    final rows = await (select(products)
          ..where((t) => t.id.isIn(productIds) & t.parentProductId.isNotNull()))
        .get();
    return {for (final r in rows) r.id: r.parentProductId!};
  }

  /// Satuan JUAL sebuah varian, dipilih dari seluruh satuannya.
  ///
  /// Varian SELALU punya satu satuan DASAR (jangkar ke satuan dasar produk
  /// induk, `ratioToBase` 1.0) — satuan itulah yang memegang stok, karena
  /// seluruh `stock_ledger` di app ini ditulis dalam satuan dasar (lihat
  /// [_baseUnitOf]). Susulan (permintaan user): varian sekarang boleh DIJUAL
  /// dalam satuan lain yang berisi N satuan dasar (mis. "Renteng" berisi 10) —
  /// diwakili SATU satuan non-dasar tambahan, dan satuan ITU-lah yang
  /// memegang harga, barcode, Harga Lain, serta label satuan yang dilihat
  /// kasir. Varian lama (satu satuan saja) otomatis jatuh ke satuan dasarnya,
  /// jadi tidak ada migrasi data yang dibutuhkan.
  static ProductUnit? variantSaleUnit(List<ProductUnit> units) {
    if (units.isEmpty) return null;
    for (final u in units) {
      if (!u.isBaseUnit) return u;
    }
    for (final u in units) {
      if (u.isBaseUnit) return u;
    }
    return units.first;
  }

  /// Buat varian baru: produk anak + satuan dasar (+ satuan jual bila
  /// [contentPerUnit] != 1) + tier harga + barcode opsional. Harga default
  /// mengikuti induk (di-pass oleh pemanggil). Mengembalikan id produk varian
  /// baru agar pemanggil bisa melacaknya (mis. untuk undo bila edit dibatalkan).
  Future<String> createVariant({
    required String parentProductId,
    required String name,
    required int price,
    required int costPrice,
    int? unitTypeId,
    String? barcode,
    String? kodeProduk,
    bool isNonStock = true,
    // Susulan (permintaan user) — Harga Lain per varian, pola identik
    // `saveProduct` (selalu ganti seluruh baris, bukan menumpuk). Sah-sah
    // saja secara data krn `AltPrices` sudah di-key per `productUnitId`,
    // dan varian sudah punya `ProductUnits` sendiri sejak awal.
    List<({String label, int price})>? altPrices,

    /// Jenis satuan DASAR varian (jangkar, pemegang stok). Hanya dipakai
    /// bila [contentPerUnit] != 1 — selain itu satuan dasar sekaligus satuan
    /// jual, jadi jenisnya = [unitTypeId]. Null → ikut [unitTypeId].
    int? baseUnitTypeId,

    /// Isi satu satuan jual dalam satuan dasar varian (mis. 1 Renteng = 10).
    /// 1.0 (default) = varian dijual dalam satuan dasarnya sendiri, cukup
    /// SATU baris `product_units` persis seperti varian sebelum fitur ini.
    double contentPerUnit = 1.0,

    /// Item 53 (permintaan user) — true = harga dasar varian ini otomatis
    /// ikut berubah setiap kali harga satuan dasar produk induk (yg
    /// jenisnya sama dgn [baseUnitTypeId]/[unitTypeId]) diubah. Lihat
    /// `_cascadeVariantPricesForUnit`.
    bool followsParentPrice = false,
  }) async {
    final now = DateTime.now();
    final productId = const Uuid().v4();
    final baseUnitId = const Uuid().v4();
    // Rasio <= 0 tidak masuk akal (dan bikin `currentStock` fallback tanpa
    // konversi) — diperlakukan sama seperti 1, yaitu tanpa satuan jual.
    final hasSaleUnit = contentPerUnit > 0 && contentPerUnit != 1.0;
    final unitId = hasSaleUnit ? const Uuid().v4() : baseUnitId;
    await transaction(() async {
      await into(products).insert(ProductsCompanion.insert(
        id: productId,
        name: name,
        parentProductId: Value(parentProductId),
        kodeProduk: Value(kodeProduk),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
      await into(productUnits).insert(ProductUnitsCompanion.insert(
        id: baseUnitId,
        productId: productId,
        unitTypeId:
            Value(hasSaleUnit ? (baseUnitTypeId ?? unitTypeId) : unitTypeId),
        isBaseUnit: const Value(true),
        ratioToBase: const Value(1.0),
        isNonStock: Value(isNonStock),
        followsParentPrice: Value(!hasSaleUnit && followsParentPrice),
      ));
      if (hasSaleUnit) {
        await into(productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: productId,
          unitTypeId: Value(unitTypeId),
          isBaseUnit: const Value(false),
          ratioToBase: Value(contentPerUnit),
          isNonStock: Value(isNonStock),
          followsParentPrice: Value(followsParentPrice),
        ));
      }
      await into(priceTiers).insert(PriceTiersCompanion.insert(
        id: const Uuid().v4(),
        productUnitId: unitId,
        minQty: const Value(1),
        price: price,
        costPrice: Value(costPrice),
        createdAt: Value(now),
      ));
      if (barcode != null && barcode.trim().isNotEmpty) {
        await into(productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: unitId,
          barcode: barcode.trim(),
          isPrimary: const Value(true),
        ));
      }
      if (altPrices != null && altPrices.isNotEmpty) {
        await batch((b) => b.insertAll(
              this.altPrices,
              [
                for (var i = 0; i < altPrices.length; i++)
                  AltPricesCompanion.insert(
                    id: const Uuid().v4(),
                    productUnitId: unitId,
                    label: altPrices[i].label,
                    price: altPrices[i].price,
                    sortOrder: Value(i),
                  ),
              ],
            ));
      }
    });
    return productId;
  }

  /// Soft-delete varian (set isActive=false) + lepas barcode-nya (lihat
  /// `_releaseBarcodesForProduct`) — bug yang sama dengan `deactivateProduct`.
  Future<void> deleteVariant(String variantProductId) => transaction(() async {
        await (update(products)..where((t) => t.id.equals(variantProductId)))
            .write(
          ProductsCompanion(
            isActive: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await _releaseBarcodesForProduct(variantProductId);
      });

  /// Perbarui varian (produk anak): nama, harga dasar, barcode utama, dan
  /// pelacakan stok. Mengubah satuan dasar varian beserta tier harga minQty=1
  /// dan barcode primer. Tidak menyentuh stok yang sudah tercatat.
  Future<void> updateVariant({
    required String variantProductId,
    required String name,
    required int price,
    String? barcode,
    bool? isNonStock,
    // Susulan (permintaan user) — null = tidak disentuh (form lama/tanpa
    // Harga Lain); list (termasuk kosong) = SELALU ganti seluruh baris,
    // pola identik `saveProduct`.
    List<({String label, int price})>? altPrices,

    /// Jenis satuan JUAL varian (mis. Renteng/Dus). Null = tidak disentuh.
    int? unitTypeId,

    /// Isi satu satuan jual dalam satuan dasar varian. Null = tidak disentuh.
    double? contentPerUnit,

    /// Item 53 — null = tidak disentuh.
    bool? followsParentPrice,
  }) async {
    final now = DateTime.now();
    await transaction(() async {
      await (update(products)..where((t) => t.id.equals(variantProductId)))
          .write(ProductsCompanion(
        name: Value(name),
        updatedAt: Value(now),
      ));

      final units = await (select(productUnits)
            ..where((t) => t.productId.equals(variantProductId)))
          .get();
      if (units.isEmpty) return;
      final baseUnit =
          units.firstWhere((u) => u.isBaseUnit, orElse: () => units.first);
      var unitId = variantSaleUnit(units)!.id;

      // Susulan (permintaan user) — varian bisa dijual dalam satuan lain yang
      // berisi N satuan dasar. Satuan jual dibuat MALAS (baru saat isi per
      // satuan pertama kali != 1); setelah ada, TIDAK PERNAH dihapus lagi
      // walau isinya dikembalikan ke 1 — `transaction_items` nota lama
      // menunjuk ke id satuan, menghapusnya memutus riwayat nota.
      if (contentPerUnit != null) {
        final ratio = contentPerUnit > 0 ? contentPerUnit : 1.0;
        if (unitId == baseUnit.id && ratio != 1.0) {
          final newId = const Uuid().v4();
          await into(productUnits).insert(ProductUnitsCompanion.insert(
            id: newId,
            productId: variantProductId,
            unitTypeId: Value(unitTypeId ?? baseUnit.unitTypeId),
            isBaseUnit: const Value(false),
            ratioToBase: Value(ratio),
            isNonStock: Value(isNonStock ?? baseUnit.isNonStock),
          ));
          // Harga/barcode/Harga Lain PINDAH ke satuan jual — stok sengaja
          // tetap di satuan dasar (semua ledger app ini memang ditulis dalam
          // satuan dasar, lihat `_baseUnitOf`), jadi stok yang sudah tercatat
          // tidak berubah sama sekali, hanya cara membacanya (dibagi rasio).
          await (update(priceTiers)
                ..where((t) => t.productUnitId.equals(baseUnit.id)))
              .write(PriceTiersCompanion(productUnitId: Value(newId)));
          await (update(productBarcodes)
                ..where((t) => t.productUnitId.equals(baseUnit.id)))
              .write(ProductBarcodesCompanion(productUnitId: Value(newId)));
          await (update(this.altPrices)
                ..where((t) => t.productUnitId.equals(baseUnit.id)))
              .write(AltPricesCompanion(productUnitId: Value(newId)));
          unitId = newId;
        } else if (unitId != baseUnit.id) {
          await (update(productUnits)..where((t) => t.id.equals(unitId)))
              .write(ProductUnitsCompanion(ratioToBase: Value(ratio)));
        }
      }
      if (followsParentPrice != null) {
        await (update(productUnits)..where((t) => t.id.equals(unitId))).write(
            ProductUnitsCompanion(
                followsParentPrice: Value(followsParentPrice)));
      }
      if (unitTypeId != null) {
        await (update(productUnits)..where((t) => t.id.equals(unitId)))
            .write(ProductUnitsCompanion(unitTypeId: Value(unitTypeId)));
      }

      if (isNonStock != null) {
        // Ditulis ke SEMUA satuan varian: stoknya memang dilacak di satuan
        // dasar, tapi UI kasir membaca flag ini dari satuan JUAL.
        await (update(productUnits)
              ..where((t) => t.productId.equals(variantProductId)))
            .write(ProductUnitsCompanion(isNonStock: Value(isNonStock)));
      }

      // Tier harga dasar (minQty == 1): update bila ada, selainnya buat baru.
      final baseTier = await (select(priceTiers)
            ..where((t) => t.productUnitId.equals(unitId) & t.minQty.equals(1)))
          .getSingleOrNull();
      if (baseTier != null) {
        await (update(priceTiers)..where((t) => t.id.equals(baseTier.id)))
            .write(PriceTiersCompanion(price: Value(price)));
      } else {
        await into(priceTiers).insert(PriceTiersCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: unitId,
          minQty: const Value(1),
          price: price,
          createdAt: Value(now),
        ));
      }

      // Barcode utama: update / hapus / buat sesuai input.
      final existing = await (select(productBarcodes)
            ..where((t) =>
                t.productUnitId.equals(unitId) & t.isPrimary.equals(true)))
          .getSingleOrNull();
      final bc = barcode?.trim() ?? '';
      if (bc.isEmpty) {
        if (existing != null) {
          await (delete(productBarcodes)
                ..where((t) => t.id.equals(existing.id)))
              .go();
        }
      } else if (existing != null) {
        await (update(productBarcodes)..where((t) => t.id.equals(existing.id)))
            .write(ProductBarcodesCompanion(barcode: Value(bc)));
      } else {
        await into(productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: unitId,
          barcode: bc,
          isPrimary: const Value(true),
        ));
      }

      if (altPrices != null) {
        await (delete(this.altPrices)
              ..where((t) => t.productUnitId.equals(unitId)))
            .go();
        if (altPrices.isNotEmpty) {
          await batch((b) => b.insertAll(
                this.altPrices,
                [
                  for (var i = 0; i < altPrices.length; i++)
                    AltPricesCompanion.insert(
                      id: const Uuid().v4(),
                      productUnitId: unitId,
                      label: altPrices[i].label,
                      price: altPrices[i].price,
                      sortOrder: Value(i),
                    ),
                ],
              ));
        }
      }
    });
  }

  Future<List<ProductUnit>> getProductUnits(String productId) =>
      (select(productUnits)..where((t) => t.productId.equals(productId))).get();

  /// Satuan + nama tipe satuannya untuk BANYAK produk sekaligus, satu query
  /// JOIN. Untuk layar yang butuh pemilih satuan seluruh daftar sekaligus
  /// (Stock Opname): `getProductUnits` per produk lalu `unit_types` per
  /// satuan = N+1 BERLAPIS — 1000 produk berjenjang jadi 3000 round-trip
  /// (~440ms di SQLite memori x86; jauh lebih lambat di HP kelas bawah krn
  /// SQLCipher mendekripsi tiap page + I/O file), dan layarnya menunggu
  /// SELURUH loop selesai di balik spinner.
  ///
  /// `coalesce(unit_type_id, 1)` MEMPERTAHANKAN perilaku lama `u.unitTypeId
  /// ?? 1` apa adanya (satuan tanpa tipe jatuh ke unit type id 1 = 'Kg') —
  /// sengaja tidak "dirapikan" di sini supaya refactor ini murni soal
  /// jumlah query, tidak mengubah nama satuan yang tampil.
  ///
  /// Urutan per produk mengikuti `rowid` (urutan insert) — sama dengan yang
  /// SELAMA INI dihasilkan `getProductUnits` (tanpa `orderBy`, jadi urutan
  /// scan alami), dibuat eksplisit karena indeks pilihan dropdown &
  /// `indexWhere(isBaseUnit)` bergantung padanya.
  Future<Map<String, List<({ProductUnit unit, String unitName})>>>
      getUnitsWithTypeNamesFor(List<String> productIds) async {
    if (productIds.isEmpty) return {};
    final query = select(productUnits).join([
      leftOuterJoin(
        unitTypes,
        unitTypes.id
            .equalsExp(coalesce([productUnits.unitTypeId, const Constant(1)])),
      ),
    ])
      ..where(productUnits.productId.isIn(productIds))
      ..orderBy([
        OrderingTerm(
            expression: const CustomExpression<int>('product_units.rowid')),
      ]);
    final rows = await query.get();
    final map = <String, List<({ProductUnit unit, String unitName})>>{};
    for (final row in rows) {
      final unit = row.readTable(productUnits);
      final name = row.readTableOrNull(unitTypes)?.name ?? 'Satuan';
      (map[unit.productId] ??= []).add((unit: unit, unitName: name));
    }
    return map;
  }

  Future<List<ProductBarcode>> getProductBarcodes(String productUnitId) =>
      (select(productBarcodes)
            ..where((t) => t.productUnitId.equals(productUnitId)))
          .get();

  Future<ProductBarcode?> lookupBarcode(String barcode) =>
      (select(productBarcodes)..where((t) => t.barcode.equals(barcode)))
          .getSingleOrNull();

  Future<List<UnitType>> getAllUnitTypes() =>
      (select(unitTypes)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<List<ProductGroup>> getAllProductGroups() => (select(productGroups)
        ..where((t) => t.name.isNotNull())
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();

  /// Item 54 — kategori terurut `sortOrder` (tie-break nama) untuk chip
  /// kategori tab Kasir, reaktif terhadap hasil drag-reorder
  /// ([reorderProductGroups]) TANPA perlu tutup-buka layar.
  Stream<List<ProductGroup>> watchProductGroupsForKasir() =>
      (select(productGroups)
            ..where((t) => t.name.isNotNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.sortOrder),
              (t) => OrderingTerm.asc(t.name),
            ]))
          .watch();

  /// Item 54 — simpan urutan baru chip kategori Kasir setelah drag-reorder.
  /// [orderedIds] adalah urutan tampil BARU secara utuh (index 0 = paling
  /// kiri) — sortOrder ditulis sbg index-nya, dibungkus 1 transaksi.
  Future<void> reorderProductGroups(List<int> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(productGroups)..where((t) => t.id.equals(orderedIds[i])))
            .write(ProductGroupsCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Simpan urutan baru metode pembayaran (drag-reorder di
  /// `PaymentMethodsScreen`) — pola sama dgn [reorderProductGroups].
  /// [orderedIds] adalah urutan tampil BARU secara utuh (index 0 = paling
  /// atas), sortOrder ditulis sbg index-nya, dibungkus 1 transaksi.
  Future<void> reorderPaymentMethods(List<String> orderedIds) async {
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(paymentMethods)..where((t) => t.id.equals(orderedIds[i])))
            .write(PaymentMethodsCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// `sortOrder` tertinggi saat ini di antara metode pembayaran (-1 bila
  /// tabel kosong) — dipakai utk menaruh metode BARU di posisi paling
  /// bawah, bukan tie di default 0 dgn baris lain.
  Future<int> paymentMethodsMaxSortOrder() async {
    final row = await (select(paymentMethods)
          ..orderBy([(t) => OrderingTerm.desc(t.sortOrder)])
          ..limit(1))
        .getSingleOrNull();
    return row?.sortOrder ?? -1;
  }

  /// Peta id produk → nama kategori untuk sekumpulan id (dipakai katalog untuk
  /// mengelompokkan produk per kategori). Hanya satu query untuk produk + grup.
  Future<Map<String, String>> getCategoryNamesForProducts(
      List<String> ids) async {
    if (ids.isEmpty) return {};
    final groups = await getAllProductGroups();
    final groupName = {for (final g in groups) g.id: g.name};
    final rows = await (select(products)..where((t) => t.id.isIn(ids))).get();
    final map = <String, String>{};
    for (final p in rows) {
      final gid = p.productGroupId;
      final name = gid == null ? null : groupName[gid];
      if (name != null && name.isNotEmpty) map[p.id] = name;
    }
    return map;
  }

  Future<void> addProductGroup(String name) async {
    // Item 54 — kategori baru selalu ditaruh PALING AKHIR urutan chip Kasir
    // (bukan 0) — begitu kategori lain sudah pernah di-reorder manual,
    // default 0 akan melompat kategori baru ke paling depan tanpa alasan.
    final maxOrderRow =
        await customSelect('SELECT MAX(sort_order) as mx FROM product_groups')
            .getSingleOrNull();
    final nextOrder = (maxOrderRow?.data['mx'] as int? ?? -1) + 1;

    final emptySlot = await (select(productGroups)
          ..where((t) => t.name.isNull())
          ..limit(1))
        .getSingleOrNull();
    if (emptySlot != null) {
      await (update(productGroups)..where((t) => t.id.equals(emptySlot.id)))
          .write(ProductGroupsCompanion(
              name: Value(name), sortOrder: Value(nextOrder)));
    } else {
      final rows =
          await customSelect('SELECT MAX(id) as mx FROM product_groups')
              .getSingleOrNull();
      final nextId = (rows?.data['mx'] as int? ?? 20) + 1;
      await into(productGroups).insert(ProductGroupsCompanion.insert(
          id: Value(nextId), name: Value(name), sortOrder: Value(nextOrder)));
    }
  }

  /// Tambah banyak kategori sekaligus (satu nama per baris di UI). Nama
  /// kosong dilewati; tiap nama diproses lewat `addProductGroup` yang sama
  /// (alokasi slot id tetap konsisten, dieksekusi berurutan dlm 1 transaksi
  /// supaya tidak ada baris lain yg nyelip di antaranya).
  Future<int> addProductGroups(List<String> names) async {
    final cleaned = names.map((n) => n.trim()).where((n) => n.isNotEmpty);
    var count = 0;
    await transaction(() async {
      for (final name in cleaned) {
        await addProductGroup(name);
        count++;
      }
    });
    return count;
  }

  Future<void> renameProductGroup(int id, String newName) =>
      (update(productGroups)..where((t) => t.id.equals(id)))
          .write(ProductGroupsCompanion(name: Value(newName)));

  /// Item 53 — `updatedAt` WAJIB dicap ulang di sini (pola sama spt gotcha
  /// `deactivateProduct`/`applyProductProposals` yang sudah tercatat
  /// CLAUDE.md) supaya produk yang jadi "Tanpa Kategori" gara-gara
  /// kategorinya dihapus ikut tersinkron ke klien lain, bukan cuma diam
  /// di DB lokal. Tag kategori TAMBAHAN (`product_group_tags`) milik
  /// kategori ini juga WAJIB dihapus di sini — kalau tidak, id kategori
  /// (nama-nya di-null-kan tapi barisnya tetap ada utk dipakai ulang lewat
  /// slot kosong `addProductGroup`) bisa "hidup lagi" nempel ke kategori
  /// BARU yang kebetulan dapat id yang sama, produk lama tiba-tiba tampil
  /// tertag ke kategori yang sama sekali tidak berhubungan.
  Future<void> deleteProductGroup(int id) async {
    await transaction(() async {
      await (update(products)..where((t) => t.productGroupId.equals(id)))
          .write(ProductsCompanion(
        productGroupId: const Value(null),
        updatedAt: Value(DateTime.now()),
      ));
      await (delete(productGroupTags)..where((t) => t.groupId.equals(id))).go();
      await (update(productGroups)..where((t) => t.id.equals(id)))
          .write(const ProductGroupsCompanion(name: Value(null)));
    });
  }

  /// Hapus banyak kategori sekaligus — produk yg memakainya jadi tanpa
  /// kategori (sama spt `deleteProductGroup` tunggal), dibungkus 1 transaksi.
  Future<void> deleteProductGroups(List<int> ids) async {
    await transaction(() async {
      for (final id in ids) {
        await deleteProductGroup(id);
      }
    });
  }

  /// Item 54 — live-toggle centang produk di layar assign kategori
  /// (menggantikan `assignProductsToGroup` Item 52 yang batch-overwrite —
  /// dihapus krn kontradiktif dgn keputusan baru "kategori lama tetap
  /// dipertahankan"). [member]=true: kalau produk BELUM punya kategori
  /// utama, kategori ini jadi kategori UTAMA-nya; kalau SUDAH punya
  /// kategori utama LAIN, kategori ini jadi TAG TAMBAHAN (`product_group_
  /// tags`) — kategori utama lama tidak tersentuh. [member]=false:
  /// lepaskan dari kategori ini, entah itu kategori utama (→ null,
  /// `updatedAt` dicap ulang spt gotcha `deactivateProduct`) atau tag
  /// tambahan (→ hapus baris `product_group_tags`).
  Future<void> setProductGroupMembership(
      String productId, int groupId, bool member) async {
    final product = await getProductById(productId);
    if (product == null) return;
    await transaction(() async {
      if (member) {
        if (product.productGroupId == null) {
          await (update(products)..where((t) => t.id.equals(productId)))
              .write(ProductsCompanion(
            productGroupId: Value(groupId),
            updatedAt: Value(DateTime.now()),
          ));
        } else if (product.productGroupId != groupId) {
          await into(productGroupTags).insertOnConflictUpdate(
            ProductGroupTagsCompanion.insert(
                productId: productId, groupId: groupId),
          );
        }
        // else: kategori ini SUDAH jadi kategori utama produk — no-op.
      } else {
        if (product.productGroupId == groupId) {
          await (update(products)..where((t) => t.id.equals(productId)))
              .write(ProductsCompanion(
            productGroupId: const Value(null),
            updatedAt: Value(DateTime.now()),
          ));
        } else {
          await (delete(productGroupTags)
                ..where((t) =>
                    t.productId.equals(productId) & t.groupId.equals(groupId)))
              .go();
        }
      }
    });
  }

  /// Peta productId → set id kategori TAMBAHAN (tag) untuk sekumpulan produk
  /// — satu query, hindari N+1 (dipakai layar assign kategori utk tampilkan
  /// "juga ada di kategori lain"). Kategori UTAMA (`productGroupId`) TIDAK
  /// ikut di sini — pemanggil sudah punya itu langsung dari baris `Product`.
  Future<Map<String, Set<int>>> getProductGroupTagsFor(
      List<String> productIds) async {
    if (productIds.isEmpty) return {};
    final rows = await (select(productGroupTags)
          ..where((t) => t.productId.isIn(productIds)))
        .get();
    final map = <String, Set<int>>{};
    for (final r in rows) {
      map.putIfAbsent(r.productId, () => {}).add(r.groupId);
    }
    return map;
  }

  /// Dihitung dari UNION kategori utama + tag tambahan (Item 54) — dipakai
  /// peringatan "N produk menggunakan kategori ini" sebelum hapus kategori.
  Future<int> countProductsInGroup(int groupId) async {
    final row = await customSelect(
      'SELECT COUNT(DISTINCT p.id) as cnt FROM products p '
      'LEFT JOIN product_group_tags t ON t.product_id = p.id AND t.group_id = ? '
      'WHERE p.is_active = 1 AND (p.product_group_id = ? OR t.group_id = ?)',
      variables: [
        Variable.withInt(groupId),
        Variable.withInt(groupId),
        Variable.withInt(groupId)
      ],
    ).getSingleOrNull();
    return row?.data['cnt'] as int? ?? 0;
  }

  Future<String> saveProduct({
    required ProductsCompanion product,
    required List<ProductUnitsCompanion> units,
    required Map<String, List<PriceTiersCompanion>> tiersByUnitTempId,
    required Map<String, List<ProductBarcodesCompanion>> barcodesByUnitTempId,
    Map<String, List<AltPricesCompanion>> altPricesByUnitTempId = const {},
  }) async {
    return transaction(() async {
      final productId = product.id.value;
      await into(products).insertOnConflictUpdate(product);

      // Delete units removed during edit (cascades their tiers and barcodes).
      final existingUnits = await (select(productUnits)
            ..where((t) => t.productId.equals(productId)))
          .get();
      final newUnitIds = units.map((u) => u.id.value).toSet();
      for (final existing in existingUnits) {
        if (!newUnitIds.contains(existing.id)) {
          await (delete(priceTiers)
                ..where((t) => t.productUnitId.equals(existing.id)))
              .go();
          await (delete(altPrices)
                ..where((t) => t.productUnitId.equals(existing.id)))
              .go();
          await (delete(productBarcodes)
                ..where((t) => t.productUnitId.equals(existing.id)))
              .go();
          await (delete(customerGroupPrices)
                ..where((t) => t.productUnitId.equals(existing.id)))
              .go();
          await (delete(productUnits)..where((t) => t.id.equals(existing.id)))
              .go();
        }
      }

      for (final unit in units) {
        final unitId = unit.id.value;
        await into(productUnits).insertOnConflictUpdate(unit);

        // Always replace tiers to keep them in sync with the form.
        await (delete(priceTiers)..where((t) => t.productUnitId.equals(unitId)))
            .go();
        final tiers = tiersByUnitTempId[unitId] ?? [];
        if (tiers.isNotEmpty) {
          await batch((b) => b.insertAll(priceTiers, tiers));
        }

        // Sama seperti tiers: selalu ganti seluruh harga alternatif agar
        // tetap sinkron dengan form (tidak menumpuk baris lama).
        await (delete(altPrices)..where((t) => t.productUnitId.equals(unitId)))
            .go();
        final altPriceList = altPricesByUnitTempId[unitId] ?? [];
        if (altPriceList.isNotEmpty) {
          await batch((b) => b.insertAll(altPrices, altPriceList));
        }

        final barcodes = barcodesByUnitTempId[unitId] ?? [];
        // Form hanya mengelola barcode utama; hapus yang lama agar tidak
        // menumpuk baris baru dengan id berbeda. Barcode hasil generate
        // (isPrimary=false) dibiarkan.
        await (delete(productBarcodes)
              ..where((t) =>
                  t.productUnitId.equals(unitId) & t.isPrimary.equals(true)))
            .go();
        for (final bc in barcodes) {
          await _claimBarcodeFor(productId, bc.barcode.value);
          await into(productBarcodes).insert(bc);
        }

        // Item 53 (permintaan user) — varian yg "ikut harga satuan dasar"
        // (`followsParentPrice`) disesuaikan otomatis di sini, begitu harga
        // dasar SATUAN INDUK yg jadi jangkarnya berubah. Cuma relevan utk
        // satuan dasar (base unit selalu satuan yg dipegang stok/jangkar
        // varian, lihat `createVariant`'s `baseUnitTypeId`).
        if (unit.isBaseUnit.present && unit.isBaseUnit.value) {
          final baseTierPrice = tiers
              .where((t) => t.minQty.present && t.minQty.value == 1)
              .map((t) => t.price.value)
              .firstOrNull;
          final unitTypeId =
              unit.unitTypeId.present ? unit.unitTypeId.value : null;
          if (baseTierPrice != null && unitTypeId != null) {
            await _cascadeVariantPricesForUnit(
              parentProductId: productId,
              anchorUnitTypeId: unitTypeId,
              newBasePrice: baseTierPrice,
            );
          }
        }
      }
      return productId;
    });
  }

  /// Item 53 (permintaan user) — "ikut harga satuan dasar": begitu harga
  /// dasar (tier `minQty=1`) satuan [anchorUnitTypeId] milik produk INDUK
  /// [parentProductId] berubah jadi [newBasePrice], semua varian anaknya yg
  /// (a) jangkarnya (satuan dasar varian) berjenis SAMA dgn
  /// [anchorUnitTypeId], DAN (b) satuan jualnya (`variantSaleUnit`) diberi
  /// `followsParentPrice=true`, ikut disesuaikan: harga baru = harga induk
  /// baru × isi-per-satuan varian itu (`ratioToBase`). Dipanggil dari
  /// [saveProduct] — BELUM dipanggil dari `applyProductProposals` (jalur
  /// approve usulan sync), lihat catatan Item 53 di PLAN.md.
  Future<void> _cascadeVariantPricesForUnit({
    required String parentProductId,
    required int anchorUnitTypeId,
    required int newBasePrice,
  }) async {
    final variants = await getVariants(parentProductId);
    for (final v in variants) {
      final vUnits = await getProductUnits(v.id);
      if (vUnits.isEmpty) continue;
      final vBase =
          vUnits.firstWhere((u) => u.isBaseUnit, orElse: () => vUnits.first);
      if (vBase.unitTypeId != anchorUnitTypeId) continue;
      final saleUnit = variantSaleUnit(vUnits)!;
      if (!saleUnit.followsParentPrice) continue;
      final ratio = saleUnit.ratioToBase > 0 ? saleUnit.ratioToBase : 1.0;
      final newPrice = (newBasePrice * ratio).round();
      final baseTier = await (select(priceTiers)
            ..where((t) =>
                t.productUnitId.equals(saleUnit.id) & t.minQty.equals(1)))
          .getSingleOrNull();
      if (baseTier != null) {
        await (update(priceTiers)..where((t) => t.id.equals(baseTier.id)))
            .write(PriceTiersCompanion(price: Value(newPrice)));
      }
    }
  }

  /// Nonaktifkan produk (soft-delete — TIDAK PERNAH ada hard-delete utk
  /// produk di app ini). `updatedAt` WAJIB dicap ulang: `dumpSince` (host→
  /// klien) memfilter tabel `products` dgn `WHERE updated_at >= since` —
  /// tanpa ini, baris yang `updated_at`-nya sudah lama (dari kapan produk
  /// itu terakhir diedit) TIDAK PERNAH lagi ikut terkirim ke klien yang
  /// watermark-nya sudah lewat dari situ, sehingga nonaktif produk di owner
  /// tidak PERNAH sampai ke klien (produk "hantu" tetap muncul selamanya
  /// di HP kasir/asisten). Pola sama persis dgn `deleteVariant` (yang sudah
  /// benar) dan akar masalah yang sama dgn bug `applyProductProposals` —
  /// lihat `proposal_apply_updated_at_test.dart`.
  Future<void> deactivateProduct(String productId) => transaction(() async {
        await (update(products)..where((t) => t.id.equals(productId))).write(
          ProductsCompanion(
            isActive: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await _releaseBarcodesForProduct(productId);
      });

  /// Bebaskan semua barcode milik unit-unit produk ini SUPAYA nilainya bisa
  /// dipakai ulang produk lain — tanpa menghapus barisnya. `product_barcodes.
  /// barcode` UNIQUE di seluruh katalog, dan deactivate/deleteVariant dulunya
  /// cuma set `isActive=false` di produk tanpa menyentuh barcode-nya sama
  /// sekali, jadi barcode produk yang "dihapus" via UI tetap terkunci
  /// selamanya (blocker nyata: user tidak bisa refactor produk satu-varian
  /// jadi satu-produk-banyak-varian selama barcode lama masih dipegang
  /// produk lama yang cuma disembunyikan).
  ///
  /// SENGAJA mutasi nilai `barcode` (prefix `RELEASED:<id>:`), BUKAN DELETE
  /// baris: baris `product_barcodes` disinkron via full-dump tanpa watermark
  /// (lihat `dumpSince`) — kalau baris benar-benar dihapus, device lain yang
  /// sudah punya salinannya TIDAK PERNAH menerima kabar "baris ini dihapus"
  /// (sync tidak delete-aware), jadi salinan basi di device lain akan
  /// mengunci barcode itu SELAMANYA di device tersebut. Dengan mutasi nilai,
  /// barisnya tetap ada & ikut ke-dump lagi di sync berikutnya, ter-`INSERT
  /// OR REPLACE` (keyed by id yang sama) ke device lain — pelepasan ikut
  /// terpropagasi otomatis lewat mekanisme sync yang sudah ada, tanpa
  /// perubahan protokol.
  /// Bebaskan nilai [barcode] supaya bisa dipakai [productId], ATAU lempar
  /// [BarcodeConflictException] kalau nilai itu masih dipegang produk lain
  /// yang MASIH AKTIF.
  ///
  /// Dulu di sini cuma `DELETE ... WHERE barcode = value` polos supaya tidak
  /// menabrak `UNIQUE(barcode)`. Efeknya: menyimpan produk B dgn barcode
  /// produk A **MENGHAPUS barcode A tanpa error apa pun** — A jadi tidak
  /// bisa di-scan, dan scan kode itu di kasir menagih produk yang SALAH (B),
  /// tanpa ada yang sadar. Dilaporkan user 25 Juli ("dua produk barcode sama
  /// lolos" — yang sebenarnya terjadi: yang kedua mencuri dari yang pertama).
  ///
  /// Kasus reuse yang SAH tidak lewat sini: produk yang dinonaktifkan/varian
  /// dihapus sudah dilepas lewat [_releaseBarcodesForProduct] (nilainya
  /// di-rename `RELEASED:...`), jadi tidak pernah cocok dgn `equals(value)`.
  /// Yang MASIH perlu diganti tanpa protes: baris milik produk INI sendiri —
  /// mis. alias `isPrimary=false` yang ditulis sinkron harga antar toko
  /// (lihat CLAUDE.md) lalu diketik owner sbg barcode utama.
  Future<void> _claimBarcodeFor(String productId, String barcode) async {
    // `barcode` UNIQUE, jadi paling banyak satu pemegang.
    final holder = await (select(productBarcodes)
          ..where((t) => t.barcode.equals(barcode)))
        .getSingleOrNull();
    if (holder == null) return;

    final holderUnit = await (select(productUnits)
          ..where((t) => t.id.equals(holder.productUnitId)))
        .getSingleOrNull();
    if (holderUnit == null || holderUnit.productId == productId) {
      // Milik produk ini sendiri (atau baris yatim) — aman diganti.
      await (delete(productBarcodes)..where((t) => t.id.equals(holder.id)))
          .go();
      return;
    }

    final other = await (select(products)
          ..where((t) => t.id.equals(holderUnit.productId)))
        .getSingleOrNull();
    if (other != null && other.isActive) {
      throw BarcodeConflictException(
        barcode: barcode,
        productName: other.name,
        productId: other.id,
      );
    }
    // Pemegangnya produk tidak aktif yang barcode-nya belum pernah dilepas
    // (data lama, sebelum mekanisme RELEASED ada). Lepas dgn cara yang sama
    // — rename, JANGAN hard-delete, supaya jejaknya tidak hilang.
    await (update(productBarcodes)..where((t) => t.id.equals(holder.id)))
        .write(ProductBarcodesCompanion(
      barcode: Value('RELEASED:${holder.id}:${holder.barcode}'),
    ));
  }

  Future<void> _releaseBarcodesForProduct(String productId) async {
    final units = await (select(productUnits)
          ..where((t) => t.productId.equals(productId)))
        .get();
    if (units.isEmpty) return;
    final unitIds = units.map((u) => u.id).toList();
    final barcodes = await (select(productBarcodes)
          ..where((t) => t.productUnitId.isIn(unitIds)))
        .get();
    for (final bc in barcodes) {
      if (bc.barcode.startsWith('RELEASED:')) continue; // sudah dilepas
      await (update(productBarcodes)..where((t) => t.id.equals(bc.id)))
          .write(ProductBarcodesCompanion(
        barcode: Value('RELEASED:${bc.id}:${bc.barcode}'),
      ));
    }
  }

  /// Item 25a — tandai/lepas tanda "stok habis" manual (lihat komentar
  /// kolom `markedOutOfStock` di product_tables.dart).
  ///
  /// `updated_at` WAJIB dicap ulang eksplisit — kelas bug yang SAMA PERSIS
  /// dgn `deactivateProduct`/`applyProductProposals` (lihat dok panjang di
  /// keduanya): tanpa ini, `dumpSince` (host→klien, filter `WHERE
  /// updated_at >= since`) tidak akan pernah lagi menyertakan baris ini
  /// begitu watermark klien sudah lewat dari kapan produk itu TERAKHIR
  /// DIEDIT (bukan kapan ditandai habis) — tanda "stok habis" yang di-toggle
  /// owner di host tidak pernah sampai ke klien.
  Future<void> setMarkedOutOfStock(String productId, bool value) =>
      (update(products)..where((t) => t.id.equals(productId))).write(
          ProductsCompanion(
              markedOutOfStock: Value(value),
              updatedAt: Value(DateTime.now())));

  // ───────────────────────── Jeda pelacakan stok (sementara) ───────────────

  static const _stockPauseSnapshotKey = 'stock_pause_snapshot';

  Future<bool> isStockTrackingPaused() async {
    final raw = await getSetting(_stockPauseSnapshotKey);
    return raw != null && raw.isNotEmpty;
  }

  /// Set SEMUA satuan produk yang saat ini masih dilacak stoknya jadi
  /// non-stok, sekaligus (idempoten — panggilan kedua saat sudah jeda
  /// adalah no-op, mengembalikan 0). Daftar id yang diubah disimpan sbg
  /// snapshot di `app_settings` supaya [resumeStockTrackingForAllProducts]
  /// bisa mengembalikan PERSIS satuan yang sama — satuan yang MEMANG sudah
  /// non-stok sebelumnya (mis. varian jasa) sengaja tidak ikut tersentuh
  /// sama sekali, baik saat jeda maupun saat dipulihkan.
  Future<int> pauseStockTrackingForAllProducts() async {
    if (await isStockTrackingPaused()) return 0;
    final tracked = await (select(productUnits)
          ..where((t) => t.isNonStock.equals(false)))
        .get();
    final ids = tracked.map((u) => u.id).toList();
    await setSetting(_stockPauseSnapshotKey, jsonEncode(ids));
    if (ids.isNotEmpty) {
      await (update(productUnits)..where((t) => t.id.isIn(ids)))
          .write(const ProductUnitsCompanion(isNonStock: Value(true)));
    }
    return ids.length;
  }

  /// Kembalikan pelacakan stok utk satuan yang diubah oleh
  /// [pauseStockTrackingForAllProducts] (dan HANYA itu — lihat dok di sana).
  /// No-op (return 0) bila sedang tidak dijeda.
  Future<int> resumeStockTrackingForAllProducts() async {
    final raw = await getSetting(_stockPauseSnapshotKey);
    if (raw == null) return 0;
    final ids = (jsonDecode(raw) as List).cast<String>();
    if (ids.isNotEmpty) {
      await (update(productUnits)..where((t) => t.id.isIn(ids)))
          .write(const ProductUnitsCompanion(isNonStock: Value(false)));
    }
    await setSetting(_stockPauseSnapshotKey, '');
    return ids.length;
  }

  // ───────────────────────── Transaction save ─────────────────────────

  Future<void> saveTransaction({
    required TransactionsCompanion tx,
    required List<TransactionItemsCompanion> items,
    required List<TransactionPaymentsCompanion> payments,
    required List<({String productUnitId, double qty, String note})> stockItems,
    DateTime? now,
    LoyaltyPointLedgerCompanion? loyaltyEntry,
  }) async {
    final ts = now ?? DateTime.now();
    await transaction(() async {
      await into(transactions).insert(tx);
      await batch((b) {
        b.insertAll(transactionItems, items);
        if (payments.isNotEmpty) b.insertAll(transactionPayments, payments);
        if (loyaltyEntry != null) {
          b.insert(loyaltyPointLedger, loyaltyEntry);
        }
      });
      // Deduct stock — semua ditulis ke satuan dasar via _appendStock.
      for (final s in stockItems) {
        await _appendStock(
          productUnitId: s.productUnitId,
          qtyChange: -s.qty,
          type: 'sale',
          note: s.note,
          now: ts,
        );
      }
      // Update loyalty balance untuk pelanggan.
      final cid = tx.customerId.value;
      if (cid != null && loyaltyEntry != null) {
        final delta = loyaltyEntry.points.value;
        await customUpdate(
          'UPDATE customers SET loyalty_points = loyalty_points + ? WHERE id = ?',
          variables: [Variable.withInt(delta), Variable.withString(cid)],
          updates: {customers},
        );
      }
      // Materialisasi ringkasan harian (di dalam transaksi → atomik).
      await _rebuildDailySummaryFor(_dateKey(ts));
    });
  }

  /// Tambah item ke transaksi yang SUDAH tersimpan (fitur "tambah belanjaan").
  /// Tetap satu transaksi & satu localId. Dalam satu transaksi DB:
  ///  - insert transaction_items baru (ditandai addedAt = sekarang)
  ///  - potong stok tiap item
  ///  - catat pembayaran susulan (bila ada)
  ///  - hitung ulang total & paid dari child rows, sesuaikan status
  ///  - rebuild ringkasan harian
  Future<void> addItemsToTransaction({
    required String txId,
    required List<TransactionItemsCompanion> items,
    required List<({String productUnitId, double qty, String note})> stockItems,
    TransactionPaymentsCompanion? payment,
    String? kasirId,

    /// Id `transaction_items` (dari [items]) yang sudah dicentang kasir di
    /// keranjang. Di-GABUNG (union) dengan `transactions.checkedItemIds` yang
    /// sudah ada, BUKAN menimpa — barang nota lama yang sudah dicentang di
    /// struk tidak boleh ikut hilang gara-gara ada tambahan belanjaan.
    List<String> checkedItemIds = const [],
  }) async {
    final now = DateTime.now();
    await transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return;

      // Insert item susulan dengan penanda addedAt.
      await batch((b) {
        b.insertAll(
          transactionItems,
          items.map((c) => c.copyWith(addedAt: Value(now))),
        );
      });

      if (checkedItemIds.isNotEmpty) {
        final merged = <String>{};
        if (tx.checkedItemIds != null && tx.checkedItemIds!.isNotEmpty) {
          try {
            merged.addAll(
                (jsonDecode(tx.checkedItemIds!) as List).cast<String>());
          } catch (_) {
            // JSON rusak/format lama — abaikan, mulai dari daftar baru saja.
          }
        }
        merged.addAll(checkedItemIds);
        // Item 62 — SENGAJA TIDAK mencap `updatedAt` di sini: `checkedItemIds`
        // dokumentasinya sendiri (lihat kolom `Transactions.checkedItemIds`)
        // murni per-perangkat & tidak ikut sync, sama seperti `changeTaken`.
        // Mencapnya akan membuat baris ini dianggap "berubah" oleh
        // `dumpSince`/`mergeRows` padahal field yang genuinely butuh
        // propagasi lintas-device (status/customer/points) tidak berubah di
        // sini.
        await (update(transactions)..where((t) => t.id.equals(txId)))
            .write(TransactionsCompanion(
          checkedItemIds: Value(jsonEncode(merged.toList())),
        ));
      }

      if (payment != null) {
        // Total SETELAH item susulan ini tapi SEBELUM _reconcileTransactionTotals
        // (yang baru jalan belakangan) — dihitung manual dari total lama +
        // subtotal item baru, supaya kembalian pembayaran ini dihitung
        // terhadap total yang benar (bukan total lama yang belum termasuk
        // tambahan barang).
        final newItemsTotal =
            items.fold<int>(0, (s, c) => s + c.subtotal.value);
        final totalAfterAddition = tx.total + newItemsTotal;
        final delta = await _computePaymentDelta(
          txId: txId,
          newPaymentAmount: payment.amount.value,
          currentTotal: totalAfterAddition,
        );
        await into(transactionPayments).insert(payment.copyWith(
          changeGiven: Value(delta.changeGiven),
          sisaAfter: Value(delta.sisaAfter),
        ));
      }

      // Potong stok.
      for (final s in stockItems) {
        await _appendStock(
          productUnitId: s.productUnitId,
          qtyChange: -s.qty,
          type: 'sale',
          note: s.note,
          kasirId: kasirId,
          now: now,
        );
      }

      // Hitung ulang total & paid dari child rows → sumber kebenaran tunggal.
      await _reconcileTransactionTotals(txId);

      await _rebuildDailySummaryFor(_dateKey(tx.createdAt));
    });
  }

  /// Hitung kembalian milik SATU baris pembayaran baru pada transaksi [txId]:
  /// total kembalian gabungan (Σpaid + pembayaran baru dikurangi [currentTotal])
  /// dikurangi kembalian yang sudah "dimiliki" pembayaran-pembayaran
  /// sebelumnya pada nota yang sama. Dipanggil SEKALI saat baris pembayaran
  /// dibuat — hasilnya ditulis permanen ke baris itu, tidak pernah dihitung
  /// ulang/ditimpa belakangan (beda dari `Transactions.changeAmount` yang
  /// selalu representasi TERKINI).
  ///
  /// [currentTotal] wajib dioper eksplisit (bukan dibaca ulang dari
  /// `transactions`) karena caller kadang perlu memakai total yang sudah
  /// termasuk perubahan dalam operasi yang sama (mis. tambah belanjaan —
  /// `transactions.total` belum terupdate sampai `_reconcileTransactionTotals`
  /// jalan belakangan).
  ///
  /// Sekalian menghitung [sisaAfter] — sisi SEBALIKNYA (kurang bayar,
  /// bukan lebih bayar) dgn formula simetris: `max(0, currentTotal -
  /// (priorPaid + newPaymentAmount))`. Beda dari `changeGiven`, `sisaAfter`
  /// TIDAK perlu dikurangi `priorChangeSum`/akumulasi baris sebelumnya —
  /// murni gap titik-waktu "berapa yang masih kurang SAAT INI", bukan
  /// kuantitas yang terakumulasi lintas baris (lihat dok
  /// `TransactionPayments.sisaAfter`).
  Future<({int changeGiven, int sisaAfter})> _computePaymentDelta({
    required String txId,
    required int newPaymentAmount,
    required int currentTotal,
  }) async {
    final amountSum = transactionPayments.amount.sum();
    final changeSum = transactionPayments.changeGiven.sum();
    final row = await (selectOnly(transactionPayments)
          ..addColumns([amountSum, changeSum])
          ..where(transactionPayments.transactionId.equals(txId) &
              transactionPayments.voided.equals(false)))
        .getSingle();
    var priorPaid = row.read(amountSum);
    final priorChangeSum = row.read(changeSum) ?? 0;
    if (priorPaid == null) {
      // Belum ada baris pembayaran sama sekali untuk nota ini (nota
      // legacy/pre-backfill) — jatuhkan ke header `transactions.paid`,
      // konsisten dengan fallback yang sama di `_reconcileTransactionTotals`.
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      priorPaid = tx?.paid ?? 0;
    }
    final aggregateChange = (priorPaid + newPaymentAmount) - currentTotal;
    // `priorChangeSum` WAJIB ikut dikurangi utk sisaAfter juga (bukan cuma
    // changeGiven) — kembalian lama yang dipakai ULANG sbg pembayaran baru
    // (mis. tambah belanjaan) tercatat lagi di `priorPaid`/`newPaymentAmount`
    // seolah uang baru, padahal net-nya bukan. Tanpa pengurangan ini,
    // sisaAfter UNDERSTATED persis pola bug lama `netRemainingOwed` (lihat
    // dok `_computePaymentDelta` & `receipt_sisa_tagihan_net_test.dart`).
    final thisChange = aggregateChange - priorChangeSum;
    return (
      changeGiven: thisChange > 0 ? thisChange : 0,
      sisaAfter: thisChange < 0 ? -thisChange : 0,
    );
  }

  /// Σ subtotal baris item nota [txId] APA ADANYA dari DB saat ini — dipakai
  /// jalur retur/hapus item nota BELUM LUNAS untuk mengetahui total AKHIR
  /// nota SEBELUM [_reconcileTransactionTotals] sempat menuliskannya ke
  /// header `transactions`. Tidak bisa membaca `transactions.total` di titik
  /// itu: nilainya masih total LAMA (pra-retur).
  Future<int> _sumItemSubtotals(String txId) async {
    final rows = await (select(transactionItems)
          ..where((t) => t.transactionId.equals(txId)))
        .get();
    return rows.fold<int>(0, (s, i) => s + i.subtotal);
  }

  /// Kelebihan bayar yang jadi HAK PELANGGAN setelah nota BELUM LUNAS
  /// diretur/itemnya dihapus sampai total akhirnya turun di bawah uang yang
  /// sudah pernah disetor.
  ///
  /// Dicatat sbg `changeGiven` di baris pembayaran penanda (`amount: 0`) —
  /// PERSIS mekanisme kembalian biasa, memakai [_computePaymentDelta]
  /// yang sama. Konsekuensinya SELURUH UX kembalian yang sudah ada langsung
  /// berlaku tanpa kode tampilan baru: baris "Kembalian" di struk (yang
  /// membaca `changeGiven` pembayaran TERAKHIR), centang "kembalian sudah
  /// diserahkan" per baris pembayaran (`changeTaken`), dan `netRemainingOwed`
  /// (`total - paid + Σ changeGiven`) otomatis jadi 0 alih-alih negatif.
  ///
  /// Bug yang ditutup (dilaporkan user): sebelumnya kelebihan itu HANYA
  /// mendarat di `transactions.changeAmount`, kolom yang TIDAK PERNAH
  /// dirender di layar manapun (struk membaca `changeGiven`, bukan kolom
  /// header itu) — jadi uang yang jadi hak pelanggan hilang tanpa jejak yang
  /// bisa dilihat kasir.
  ///
  /// Sekalian mengembalikan `sisaAfter` — sisi sebaliknya, dipakai KHUSUS
  /// nota tempo/kurang_bayar (retur/edit yang MENGURANGI total tapi masih
  /// menyisakan hutang) — lihat dok [_computePaymentDelta].
  Future<({int changeGiven, int sisaAfter})> _paymentDeltaAfterUnpaidItemChange(
          String txId) =>
      _sumItemSubtotals(txId).then((remainingTotal) => _computePaymentDelta(
            txId: txId,
            newPaymentAmount: 0,
            currentTotal: remainingTotal,
          ));

  /// Nama produk & label satuan SAAT INI untuk [productUnitId] — dipakai
  /// men-snapshot [TransactionAdjustmentLines.productName]/`unitName` supaya
  /// rincian retur/edit lama tetap benar walau produk/satuan diubah/dihapus
  /// belakangan (lihat dok tabel itu).
  Future<({String productName, String unitName})> _productUnitLabel(
      String productUnitId) async {
    final u = await (select(productUnits)
          ..where((t) => t.id.equals(productUnitId)))
        .getSingleOrNull();
    if (u == null) return (productName: '', unitName: '');
    final p = await (select(products)..where((t) => t.id.equals(u.productId)))
        .getSingleOrNull();
    var unitName = '';
    if (u.unitTypeId != null) {
      final ut = await (select(unitTypes)
            ..where((t) => t.id.equals(u.unitTypeId!)))
          .getSingleOrNull();
      unitName = ut?.name ?? '';
    }
    return (productName: p?.name ?? '', unitName: unitName);
  }

  /// Sisipkan satu baris rincian retur/edit — dipanggil dari 4 fungsi mutasi
  /// item nota (lihat dok [TransactionAdjustmentLines]). [qty]/[priceAtSale]
  /// bernilai POSITIF selalu (arah retur/tambah/kurang direpresentasikan
  /// lewat konteks momen, bukan tanda qty) — kolom `subtotal` = `qty *
  /// priceAtSale` (dibulatkan), dipakai UI menjumlah total momen.
  Future<void> _insertAdjustmentLine({
    required String paymentId,
    required String txId,
    required String productId,
    required String productUnitId,
    required double qty,
    required int priceAtSale,
    required DateTime now,
  }) async {
    if (qty <= 0) return;
    final label = await _productUnitLabel(productUnitId);
    await into(transactionAdjustmentLines)
        .insert(TransactionAdjustmentLinesCompanion.insert(
      id: const Uuid().v4(),
      paymentId: paymentId,
      transactionId: txId,
      productId: productId,
      productUnitId: productUnitId,
      productName: label.productName,
      unitName: label.unitName,
      qty: qty,
      priceAtSale: priceAtSale,
      subtotal: (qty * priceAtSale).round(),
      createdAt: Value(now),
    ));
  }

  /// Hitung ulang `total` (Σ subtotal item) dan `paid` (Σ pembayaran) sebuah
  /// transaksi dari child rows, lalu sesuaikan `status` & `change_amount`.
  /// Dipakai setelah tambah-item dan setelah sync (rekonsiliasi).
  ///
  /// Sumber kebenaran:
  ///  - total = Σ transaction_items.subtotal
  ///  - paid  = Σ transaction_payments.amount (pembayaran awal pun tercatat di
  ///            sini saat transaksi dibuat). Bila tabel pembayaran kosong
  ///            (transaksi legacy/tempo), pakai kolom header `paid` apa adanya.
  /// Keduanya hanya bergantung pada child rows yang menyebar via sync sebagai
  /// baris baru → hasil identik di semua perangkat & idempoten.
  /// [guardEmptyItems] — Item 61.2: kalau `true`, transaksi TANPA baris item
  /// sama sekali TIDAK dianggap genuinely bertotal 0 — total LAMA
  /// dipertahankan. Dipakai KHUSUS oleh path rekonsiliasi PASCA-SYNC
  /// ([reconcileTransactionsByIds]), di mana item kosong bisa berarti item
  /// susulan via sync di-skip permanen (mis. header parent-nya sempat
  /// DITOLAK di antrian lama lalu di-reject, FK gagal saat item baru datang
  /// belakangan, `mergeRows` skip baris itu diam-diam — lihat dok
  /// error-swallow FK) — BUKAN genuinely nota kosong. Default `false`
  /// (perilaku lama, tanpa guard) utk semua path mutasi LOKAL langsung (mis.
  /// `returnUnpaidTransactionItems`/`editUnpaidTransactionItem` menghapus
  /// SEMUA item nota dgn sengaja, dalam transaksi DB yang sama, item
  /// kosong di situ SELALU genuine, guard di sini justru akan salah
  /// mempertahankan total lama yang seharusnya jadi 0).
  Future<void> _reconcileTransactionTotals(String txId,
      {bool guardEmptyItems = false}) async {
    final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    if (tx == null || tx.status == 'void') return;
    // Retur bertotal negatif & tidak pernah ditambah item — jangan diutak-atik.
    if (tx.internalNote?.startsWith('RETUR:') ?? false) return;

    final itemRows = await (select(transactionItems)
          ..where((t) => t.transactionId.equals(txId)))
        .get();
    final newTotal = (guardEmptyItems && itemRows.isEmpty)
        ? tx.total
        : itemRows.fold<int>(0, (s, i) => s + i.subtotal);

    final allPayRows = await (select(transactionPayments)
          ..where((t) => t.transactionId.equals(txId)))
        .get();
    // Baris yang dibatalkan ("Batalkan Pembayaran") TETAP tersimpan sbg
    // jejak audit (lihat TransactionPayments.voided) tapi TIDAK ikut
    // dihitung ke paid/status — perlakukan seolah pembayaran itu tak pernah
    // terjadi secara finansial.
    final payRows = allPayRows.where((p) => !p.voided).toList();
    final sumPay = payRows.fold<int>(0, (s, p) => s + p.amount);
    final newPaid = allPayRows.isEmpty ? tx.paid : sumPay;

    // Status HARUS dihitung dari `paid` dikurangi kembalian yang pernah
    // diberikan (bukan `newPaid` mentah) — kalau tidak, kembalian lama yang
    // dipakai ulang sbg pembayaran baru (mis. tambah belanjaan) ke-hitung
    // dobel: uang yang sama masuk `paid` lagi tanpa pernah dikurangi saat
    // keluar sbg kembalian sebelumnya. `paid`/`changeAmount` yang TERSIMPAN
    // sengaja dibiarkan mentah (dipakai struk cetak sbg "Bayar..").
    final sumChangeGiven = payRows.fold<int>(0, (s, p) => s + p.changeGiven);
    final netPaidForStatus = newPaid - sumChangeGiven;

    final isTempo = tx.status == 'tempo' && newPaid == 0;
    final newStatus = isTempo
        ? 'tempo'
        : (netPaidForStatus < newTotal ? 'kurang_bayar' : 'lunas');
    final newChange = newPaid > newTotal ? newPaid - newTotal : 0;

    await (update(transactions)..where((t) => t.id.equals(txId))).write(
      TransactionsCompanion(
        total: Value(newTotal),
        paid: Value(newPaid),
        status: Value(newStatus),
        changeAmount: Value(newChange),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Rekonsiliasi pasca-sync: untuk tiap transaksi hasil merge, hitung ulang
  /// total/paid/status dari child rows. Mengoreksi kasus di mana item/pembayaran
  /// susulan masuk via sync tetapi header transaksi (INSERT OR IGNORE) tidak
  /// ikut terupdate. Aman dipanggil berulang (idempoten).
  Future<void> reconcileSyncedTransactions(
      List<Map<String, Object?>> txRows) async {
    final ids = <String>{};
    for (final r in txRows) {
      final id = r['id'];
      if (id is String) ids.add(id);
    }
    await reconcileTransactionsByIds(ids);
  }

  /// Rekonsiliasi total/paid/status untuk sekumpulan id transaksi.
  /// Id yang tidak ada di DB lokal dilewati dengan aman. HANYA dipakai path
  /// pasca-sync (`LanSyncService.approveSync`/`syncToHost`) — `guardEmptyItems`
  /// diaktifkan (Item 61.2), lihat dok `_reconcileTransactionTotals`.
  Future<void> reconcileTransactionsByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    await transaction(() async {
      for (final id in ids) {
        await _reconcileTransactionTotals(id, guardEmptyItems: true);
      }
    });
  }

  /// Bangun ulang ringkasan harian untuk tanggal-tanggal yang disentuh
  /// sekumpulan id transaksi (dilihat dari `created_at` di DB lokal setelah
  /// merge). Melengkapi [rebuildSummariesForMergedTransactions] untuk kasus
  /// item/pembayaran susulan yang headernya tidak ikut dalam payload.
  Future<void> rebuildSummariesForTxIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final dates = <String>{};
    // Chunk agar aman dari batas jumlah variabel SQLite.
    final list = ids.toList();
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, (i + 500).clamp(0, list.length));
      final rows =
          await (select(transactions)..where((t) => t.id.isIn(chunk))).get();
      for (final t in rows) {
        dates.add(_dateKey(t.createdAt));
      }
    }
    for (final d in dates) {
      await _rebuildDailySummaryFor(d);
    }
  }

  /// Bug dilaporkan user: ubah pelanggan dari "Umum" ke pelanggan terdaftar
  /// DI STRUK (bukan saat checkout) tidak pernah memberi poin loyalitas —
  /// wajar, krn poin cuma dihitung sekali di `_confirm()` (payment_screen.dart)
  /// saat `customerId` masih null. Dipanggil dari `receipt_screen.dart`
  /// `_saveCustomer()` setelah `customerId` transaksi diisi.
  ///
  /// KUMULATIF (bug susulan): hitung ulang poin TARGET dari `tx.total`
  /// terkini, lalu tambahkan SELISIH terhadap `pointsEarned` yang sudah
  /// tersimpan — bukan cuma no-op kalau `pointsEarned > 0`. Ini supaya
  /// "Tambah Belanjaan" (`payment_screen.dart` `_confirmAddItems`, yang
  /// menaikkan `tx.total` lewat item susulan) ikut menambah poin secara
  /// proporsional, bukan cuma dihitung sekali di checkout awal. Aman
  /// dipanggil berkali-kali dgn total yang sama (selisih 0 → no-op).
  Future<void> awardLoyaltyPointsIfEligible({
    required String txId,
    required String customerId,
  }) async {
    final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    if (tx == null) return;

    final threshold =
        int.tryParse(await getSetting('loyalty_point_threshold') ?? '') ?? 0;
    if (threshold <= 0) return;
    final pointsPer =
        int.tryParse(await getSetting('loyalty_points_per') ?? '') ?? 1;
    final targetPoints =
        (tx.total / threshold).floor() * (pointsPer < 1 ? 1 : pointsPer);
    final delta = targetPoints - tx.pointsEarned;
    if (delta <= 0) return;

    final now = DateTime.now();
    await transaction(() async {
      await (update(transactions)..where((t) => t.id.equals(txId))).write(
          TransactionsCompanion(
              pointsEarned: Value(targetPoints), updatedAt: Value(now)));
      await into(loyaltyPointLedger).insert(LoyaltyPointLedgerCompanion.insert(
        id: const Uuid().v4(),
        customerId: customerId,
        type: 'earn',
        points: delta,
        note: Value(tx.localId),
        createdAt: Value(now),
      ));
      await customUpdate(
        'UPDATE customers SET loyalty_points = loyalty_points + ? WHERE id = ?',
        variables: [Variable.withInt(delta), Variable.withString(customerId)],
        updates: {customers},
      );
    });
  }

  /// Ganti pelanggan pada transaksi (dipanggil dari `receipt_screen.dart`
  /// `_saveCustomer` — bisa Umum->pelanggan, pelanggan->Umum, atau
  /// pelanggan A->B). Bug dilaporkan user: poin yang SUDAH diberikan ke
  /// pelanggan LAMA (`tx.pointsEarned`) tidak pernah ditarik balik kalau
  /// pelanggan transaksi diubah ke Umum (`customerId` jadi null) atau ke
  /// pelanggan lain — poin nyangkut selamanya di pelanggan lama walau
  /// transaksinya sudah tidak lagi tercatat atas namanya (`voidTransaction`
  /// butuh `customerId != null` utk bisa menarik baliknya, jadi sekali
  /// customerId di-null-kan, jalur reversal lama itu tidak bisa jalan lagi).
  ///
  /// Fix: kalau pelanggan BERUBAH (bukan cuma nama tanpa ganti id) & tx
  /// sudah pernah dapat poin, tarik balik dari pelanggan LAMA dulu (reset
  /// `pointsEarned` ke 0) — baru kalau pelanggan BARU bukan null, hitung
  /// ulang & beri poin via `awardLoyaltyPointsIfEligible` (dari 0, jadi
  /// otomatis dapat penuh sesuai `tx.total` kalau eligible).
  Future<void> changeTransactionCustomer({
    required String txId,
    String? newCustomerId,
    String? newCustomerName,
  }) async {
    await transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null) return;

      final oldCustomerId = tx.customerId;
      if (oldCustomerId != null &&
          oldCustomerId != newCustomerId &&
          tx.pointsEarned > 0) {
        await customUpdate(
          'UPDATE customers SET loyalty_points = loyalty_points - ? WHERE id = ?',
          variables: [
            Variable.withInt(tx.pointsEarned),
            Variable.withString(oldCustomerId),
          ],
          updates: {customers},
        );
        await into(loyaltyPointLedger)
            .insert(LoyaltyPointLedgerCompanion.insert(
          id: const Uuid().v4(),
          customerId: oldCustomerId,
          type: 'adjust',
          points: -tx.pointsEarned,
          note: Value('Ganti pelanggan ${tx.localId}'),
          createdAt: Value(DateTime.now()),
        ));
        await (update(transactions)..where((t) => t.id.equals(txId))).write(
            TransactionsCompanion(
                pointsEarned: const Value(0),
                updatedAt: Value(DateTime.now())));
      }

      await (update(transactions)..where((t) => t.id.equals(txId))).write(
        TransactionsCompanion(
          customerName: Value(newCustomerName),
          customerId: Value(newCustomerId),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (newCustomerId != null) {
        await awardLoyaltyPointsIfEligible(
            txId: txId, customerId: newCustomerId);
      }
    });
  }

  /// [kasirId] sebetulnya dipakai sbg `deviceCode` audit trail Laci Meja
  /// (lihat di bawah, Item 60) — bukan kasirId nota. [locallyModified]:
  /// Item 40 pattern, device BUKAN owner -> event Laci Meja yang ditulis
  /// di sini menunggu persetujuan owner via sync (sama pola
  /// `laciMejaLocallyModifiedProvider`); device owner selalu `false`.
  Future<void> voidTransaction(String txId, String kasirId,
      {bool locallyModified = false, String? reason}) async {
    await transaction(() async {
      // Baca items untuk reverse stock.
      final items = await (select(transactionItems)
            ..where((t) => t.transactionId.equals(txId)))
          .get();
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return;

      final now = DateTime.now();
      // Reverse stock — ditulis ke satuan dasar.
      for (final item in items) {
        await _appendStock(
          productUnitId: item.productUnitId,
          qtyChange: item.qty,
          type: 'return_in',
          note: 'Void ${tx.localId}',
          now: now,
        );
      }

      // Void atas NOTA RETUR: pulihkan poin loyalty yang tadinya dipotong
      // retur (retur memotong poin nota asal secara proporsional; kalau retur
      // dibatalkan, potongan itu harus dikembalikan — tanpa ini poin pelanggan
      // hilang permanen). Rumus proporsi identik dengan addReturnTransaction.
      final returOrigId = (tx.internalNote?.startsWith('RETUR:') ?? false)
          ? tx.internalNote!.substring('RETUR:'.length)
          : null;
      if (returOrigId != null && tx.total < 0) {
        final orig = await (select(transactions)
              ..where((t) => t.id.equals(returOrigId)))
            .getSingleOrNull();
        if (orig != null &&
            orig.customerId != null &&
            orig.pointsEarned > 0 &&
            orig.total > 0) {
          final refundTotal = -tx.total;
          final proportion = (refundTotal / orig.total).clamp(0.0, 1.0);
          final pointsToRestore = (orig.pointsEarned * proportion)
              .round()
              .clamp(0, orig.pointsEarned);
          if (pointsToRestore > 0) {
            await customUpdate(
              'UPDATE customers SET loyalty_points = loyalty_points + ? WHERE id = ?',
              variables: [
                Variable.withInt(pointsToRestore),
                Variable.withString(orig.customerId!),
              ],
              updates: {customers},
            );
            await into(loyaltyPointLedger)
                .insert(LoyaltyPointLedgerCompanion.insert(
              id: const Uuid().v4(),
              customerId: orig.customerId!,
              type: 'adjust',
              points: pointsToRestore,
              note: Value('Void retur ${tx.localId}'),
              createdAt: Value(now),
            ));
          }
        }
      }

      // Reverse loyalty jika ada.
      if (tx.pointsEarned > 0 && tx.customerId != null) {
        await customUpdate(
          'UPDATE customers SET loyalty_points = loyalty_points - ? WHERE id = ?',
          variables: [
            Variable.withInt(tx.pointsEarned),
            Variable.withString(tx.customerId!),
          ],
          updates: {customers},
        );
        await into(loyaltyPointLedger)
            .insert(LoyaltyPointLedgerCompanion.insert(
          id: const Uuid().v4(),
          customerId: tx.customerId!,
          type: 'adjust',
          points: -tx.pointsEarned,
          note: Value('Void ${tx.localId}'),
          createdAt: Value(now),
        ));
      }

      // Item 60 — void HARUS ikut membatalkan (bukan menghapus) entri Laci
      // Meja yang masih PENDING & tertaut ke nota ini, supaya dashboard/
      // pengingat cart bar tidak lagi menampilkannya seolah masih berlaku.
      // Entri yang sudah SELESAI (diambil/dikembalikan/dipenuhi) sebelum
      // void dibiarkan apa adanya — barangnya sudah pindah tangan secara
      // fisik, tidak relevan lagi dibatalkan.
      //
      // Pre-order SUDAH punya kolom `cancelledAt` (dipakai `PreorderEntries`
      // sejak awal) — reuse `cancelPreorderEntry` apa adanya, konsisten
      // pola & otomatis ikut filter `watchPreorderEntries`/`getLaciMejaPending`
      // yang sudah mengecek `cancelledAt.isNull()`.
      final pendingPreorders = await (select(preorderEntries)
            ..where((t) =>
                t.transactionId.equals(txId) &
                t.fulfilledAt.isNull() &
                t.cancelledAt.isNull()))
          .get();
      for (final p in pendingPreorders) {
        await cancelPreorderEntry(p.id,
            locallyModified: locallyModified, deviceCode: kasirId);
      }

      // Titip/Ketinggalan & Pinjaman TIDAK punya kolom "batal" eksplisit
      // (beda dari pre-order) — sengaja TIDAK ditambah kolom baru/migrasi
      // schema baru utk ini (pendekatan yang paling sedikit mengubah
      // struktur data): baris `laci_meja_events` aksi='batal' tetap ditulis
      // utk audit trail (pola sama pre-order), TAPI status "sembunyi dari
      // dashboard" dicapai lewat query dashboard (`getLaciMejaPending`,
      // `watchLeftBehindItems`, `watchBorrowedItems`) yang sekarang ikut
      // JOIN & filter status transaksi induk != 'void' — lihat query-query
      // itu. Baris tabelnya sendiri TIDAK diubah (tidak ada updated_at baru
      // di sini) krn memang tidak ada kolom yang berubah.
      final pendingLeft = await (select(leftBehindItems)
            ..where(
                (t) => t.transactionId.equals(txId) & t.collectedAt.isNull()))
          .get();
      for (final l in pendingLeft) {
        await recordLaciMejaEvent(
          id: '${l.id}-batal-${now.microsecondsSinceEpoch}',
          entityType: 'titip',
          entryId: l.id,
          aksi: 'batal',
          note: 'Void ${tx.localId}',
          deviceCode: kasirId,
          locallyModified: locallyModified,
        );
      }

      final pendingBorrowed = await (select(borrowedItems)
            ..where((t) =>
                t.transactionId.equals(txId) & t.fullyReturnedAt.isNull()))
          .get();
      for (final b in pendingBorrowed) {
        await recordLaciMejaEvent(
          id: '${b.id}-batal-${now.microsecondsSinceEpoch}',
          entityType: 'pinjaman',
          entryId: b.id,
          aksi: 'batal',
          note: 'Void ${tx.localId}',
          deviceCode: kasirId,
          locallyModified: locallyModified,
        );
      }

      await (update(transactions)..where((t) => t.id.equals(txId))).write(
          TransactionsCompanion(
              status: const Value('void'),
              updatedAt: Value(now),
              voidedBy: Value(kasirId),
              voidReason: Value(reason)));

      // Perbarui ringkasan harian untuk tanggal transaksi yang dibatalkan.
      await _rebuildDailySummaryFor(_dateKey(tx.createdAt));
    });
  }

  // ───────────────────────── Retur ─────────────────────────

  /// Buat transaksi retur (total negatif = refund) dan kembalikan stok.
  /// Ditandai lewat `internalNote = 'RETUR:<originalTxId>'`.
  Future<void> addReturnTransaction({
    required String originalTxId,
    required String localId,
    required List<
            ({
              String productUnitId,
              String productId,
              double qty,
              int price,
              int costPrice,
              String? itemNote,
            })>
        returnItems,
    required String kasirId,
    String refundMethod = 'tunai',
  }) async {
    final now = DateTime.now();
    await transaction(() async {
      // Kembalikan stok — ditulis ke satuan dasar.
      for (final item in returnItems) {
        await _appendStock(
          productUnitId: item.productUnitId,
          qtyChange: item.qty,
          type: 'return_in',
          referenceId: originalTxId,
          kasirId: kasirId,
          note: 'Retur',
          now: now,
        );
      }

      final refundTotal =
          returnItems.fold<int>(0, (s, i) => s + (i.price * i.qty).round());
      final txId = const Uuid().v4();
      await into(transactions).insert(TransactionsCompanion.insert(
        id: txId,
        localId: localId,
        kasirId: Value(kasirId),
        status: 'lunas',
        total: -refundTotal,
        paid: -refundTotal,
        changeAmount: 0,
        paymentMethod: refundMethod,
        internalNote: Value('RETUR:$originalTxId'),
        createdAt: Value(now),
      ));
      for (final item in returnItems) {
        final sub = (item.price * item.qty).round();
        // Qty negatif → revenue, HPP, dan jumlah terjual ternetto dengan benar
        // di laporan. Stok dikembalikan lewat ledger di atas (qtyChange positif).
        await into(transactionItems).insert(TransactionItemsCompanion.insert(
          id: const Uuid().v4(),
          transactionId: txId,
          productId: item.productId,
          productUnitId: item.productUnitId,
          qty: -item.qty,
          priceAtSale: item.price,
          originalPrice: item.price,
          costAtSale: Value(item.costPrice),
          itemNote: Value(item.itemNote),
          subtotal: -sub,
        ));
      }

      // Kembalikan poin loyalty proporsional terhadap nilai refund.
      final orig = await (select(transactions)
            ..where((t) => t.id.equals(originalTxId)))
          .getSingleOrNull();
      if (orig != null &&
          orig.customerId != null &&
          orig.pointsEarned > 0 &&
          orig.total > 0) {
        final proportion = (refundTotal / orig.total).clamp(0.0, 1.0);
        final pointsToReverse = (orig.pointsEarned * proportion)
            .round()
            .clamp(0, orig.pointsEarned);
        if (pointsToReverse > 0) {
          await customUpdate(
            'UPDATE customers SET loyalty_points = loyalty_points - ? WHERE id = ?',
            variables: [
              Variable.withInt(pointsToReverse),
              Variable.withString(orig.customerId!),
            ],
            updates: {customers},
          );
          await into(loyaltyPointLedger)
              .insert(LoyaltyPointLedgerCompanion.insert(
            id: const Uuid().v4(),
            customerId: orig.customerId!,
            type: 'adjust',
            points: -pointsToReverse,
            note: Value('Retur ${orig.localId}'),
            createdAt: Value(now),
          ));
        }
      }

      await _rebuildDailySummaryFor(_dateKey(now));
    });
  }

  /// Retur untuk nota yang BELUM LUNAS (status tempo/kurang_bayar): mengedit
  /// NOTA ASLI langsung — baris item yang diretur dikurangi/dihapus, stok
  /// dikembalikan, lalu total & status direkonsiliasi dari child rows.
  /// TIDAK membuat nota retur terpisah dan TIDAK ada refund tunai, karena
  /// belum ada uang yang benar-benar masuk untuk dikembalikan — yang
  /// berkurang adalah HUTANG-nya. Nota yang sudah LUNAS tetap memakai
  /// [addReturnTransaction] (nota retur terpisah + refund) karena uang
  /// memang sudah berpindah tangan.
  ///
  /// [returns] — pasangan (transactionItemId, qty yang diretur). Qty
  /// otomatis di-clamp ke sisa qty baris tersebut; qty <= 0 diabaikan.
  Future<void> returnUnpaidTransactionItems({
    required String txId,
    required List<({String transactionItemId, double qty})> returns,
    required String kasirId,
  }) async {
    if (returns.isEmpty) return;
    await transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return;
      if (tx.status != 'tempo' && tx.status != 'kurang_bayar') {
        throw StateError(
            'returnUnpaidTransactionItems hanya untuk nota belum lunas '
            '(status saat ini: ${tx.status})');
      }
      final now = DateTime.now();
      var anyReturned = false;
      final paymentId = const Uuid().v4();

      for (final r in returns) {
        if (r.qty <= 0) continue;
        final item = await (select(transactionItems)
              ..where((t) => t.id.equals(r.transactionItemId)))
            .getSingleOrNull();
        if (item == null || item.transactionId != txId) continue;
        final retQty = r.qty.clamp(0.0, item.qty);
        if (retQty <= 0) continue;
        anyReturned = true;

        // Kembalikan stok — sama seperti retur nota lunas.
        await _appendStock(
          productUnitId: item.productUnitId,
          qtyChange: retQty,
          type: 'return_in',
          referenceId: txId,
          kasirId: kasirId,
          note: 'Retur (nota belum lunas)',
          now: now,
        );

        // Rincian per-produk momen ini — WAJIB sebelum item aslinya
        // dikurangi/dihapus di bawah (data ini tidak bisa direkonstruksi
        // lagi setelahnya). Lihat dok `TransactionAdjustmentLines`.
        await _insertAdjustmentLine(
          paymentId: paymentId,
          txId: txId,
          productId: item.productId,
          productUnitId: item.productUnitId,
          qty: retQty,
          priceAtSale: item.priceAtSale,
          now: now,
        );

        final newQty = item.qty - retQty;
        if (newQty <= 0) {
          // Seluruh qty baris ini diretur → baris hilang dari nota, persis
          // seolah barang itu tidak pernah dijual.
          await (delete(transactionItems)..where((t) => t.id.equals(item.id)))
              .go();
        } else {
          final newSubtotal = (item.priceAtSale * newQty).round();
          await (update(transactionItems)..where((t) => t.id.equals(item.id)))
              .write(TransactionItemsCompanion(
            qty: Value(newQty),
            subtotal: Value(newSubtotal),
          ));
        }
      }
      if (!anyReturned) return;

      // Jejak audit ringan di timeline pembayaran (amount 0 → tidak
      // memengaruhi jumlah dibayar, murni catatan "kapan ada retur").
      // `changeGiven`/`sisaAfter` diisi sesuai apakah nilai retur melampaui
      // sisa hutang atau masih menyisakan hutang — lihat dok
      // [_paymentDeltaAfterUnpaidItemChange].
      final delta = await _paymentDeltaAfterUnpaidItemChange(txId);
      await into(transactionPayments)
          .insert(TransactionPaymentsCompanion.insert(
        id: paymentId,
        transactionId: txId,
        amount: 0,
        method: 'retur',
        paidAt: Value(now),
        kasirId: Value(kasirId),
        changeGiven: Value(delta.changeGiven),
        sisaAfter: Value(delta.sisaAfter),
        note: const Value('Retur barang (nota belum lunas)'),
      ));

      // Rekonsiliasi total/paid/status dari child rows yang tersisa — sumber
      // kebenaran tunggal yang sama dipakai tambah-belanjaan & sync.
      await _reconcileTransactionTotals(txId);

      // _reconcileTransactionTotals mempertahankan status 'tempo' selama
      // paid == 0, walau totalnya sudah jadi 0 (seluruh isi nota diretur).
      // Nota tanpa tagihan tersisa seharusnya tidak lagi "menggantung".
      final after = await (select(transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (after != null && after.total <= 0 && after.status != 'lunas') {
        await (update(transactions)..where((t) => t.id.equals(txId))).write(
            TransactionsCompanion(
                status: const Value('lunas'),
                changeAmount: const Value(0),
                updatedAt: Value(DateTime.now())));
      }

      await _rebuildDailySummaryFor(_dateKey(tx.createdAt));
    });
  }

  /// Item 5 — edit baris item di nota BELUM LUNAS langsung (bukan retur
  /// terpisah): ubah harga dan/atau catatan, atau hapus (via [newQty] = 0).
  /// Qty TIDAK BISA dinaikkan lewat sini SELAMA `tx.paid > 0` (cuma
  /// dikurangi/dihapus, sama batasan dgn [returnUnpaidTransactionItems] yang
  /// fungsi ini pinjam pola rekonsiliasinya — menaikkan qty saat sudah ada
  /// uang masuk akan merusak alokasi pembayaran yang sudah tercatat).
  ///
  /// KHUSUS `tx.paid == 0` (belum ada uang berpindah SAMA SEKALI): qty
  /// BOLEH dinaikkan melebihi qty asli — tidak ada risiko rekonsiliasi
  /// pembayaran karena memang belum ada pembayaran sama sekali. Ini beda
  /// dari "Tambah Belanjaan" (yang menambah PRODUK baru) — di sini cuma
  /// menaikkan qty produk yang SAMA yang sudah ada di baris ini.
  /// Tanpa refund tunai (memang belum ada uang masuk).
  Future<void> editUnpaidTransactionItem({
    required String txId,
    required String transactionItemId,
    required double newQty,
    required int newPrice,
    String? newNote,
    required String kasirId,
  }) async {
    await transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return;
      if (tx.status != 'tempo' && tx.status != 'kurang_bayar') {
        throw StateError(
            'editUnpaidTransactionItem hanya untuk nota belum lunas '
            '(status saat ini: ${tx.status})');
      }
      final item = await (select(transactionItems)
            ..where((t) => t.id.equals(transactionItemId)))
          .getSingleOrNull();
      if (item == null || item.transactionId != txId) return;

      final clampedQty = tx.paid == 0
          ? newQty.clamp(0.0, double.infinity)
          : newQty.clamp(0.0, item.qty);
      final now = DateTime.now();

      // Qty berkurang (termasuk ke 0 = hapus) → stok yang tidak jadi
      // terjual dikembalikan, sama seperti retur nota belum lunas. Qty
      // BERTAMBAH (hanya mungkin saat tx.paid == 0) → potong stok
      // tambahan, sama seperti item baru di "Tambah Belanjaan".
      final qtyDelta = clampedQty - item.qty;
      if (qtyDelta < 0) {
        await _appendStock(
          productUnitId: item.productUnitId,
          qtyChange: -qtyDelta,
          type: 'return_in',
          referenceId: txId,
          kasirId: kasirId,
          note: 'Edit item (nota belum lunas)',
          now: now,
        );
      } else if (qtyDelta > 0) {
        await _appendStock(
          productUnitId: item.productUnitId,
          qtyChange: -qtyDelta,
          type: 'sale',
          referenceId: txId,
          kasirId: kasirId,
          note: 'Edit item (nota belum lunas)',
          now: now,
        );
      }

      final newSubtotal = (newPrice * clampedQty).round();
      if (clampedQty <= 0) {
        await (delete(transactionItems)..where((t) => t.id.equals(item.id)))
            .go();
      } else {
        await (update(transactionItems)..where((t) => t.id.equals(item.id)))
            .write(TransactionItemsCompanion(
          qty: Value(clampedQty),
          priceAtSale: Value(newPrice),
          subtotal: Value(newSubtotal),
          itemNote: Value(newNote?.isEmpty ?? true ? null : newNote),
        ));
      }

      final paymentId = const Uuid().v4();
      // Rincian per-produk momen ini — HANYA kalau qty/harga sungguhan
      // berubah (bukan cuma catatan). qtyForLine = qty yang berubah (delta
      // absolut), jatuh ke qty final kalau delta 0 tapi harga berubah
      // (dianggap "harga seluruh baris berubah"). subtotalForLine = nilai
      // Rupiah delta-nya (SELALU eksak); priceForLine diturunkan dari situ
      // supaya qty*harga tetap ≈ subtotal — pendekatan ini bisa sedikit
      // approksimasi kalau qty & harga SAMA-SAMA berubah dalam satu edit
      // (kasus jarang), tapi totalnya (yang dipakai header "Rp x" di kartu
      // Riwayat Pembayaran) tetap eksak.
      final qtyDeltaAbs = qtyDelta.abs();
      if (qtyDeltaAbs > 0 || newPrice != item.priceAtSale) {
        final qtyForLine = qtyDeltaAbs > 0 ? qtyDeltaAbs : clampedQty;
        final subtotalForLine = (item.subtotal - newSubtotal).abs();
        final priceForLine =
            qtyForLine > 0 ? (subtotalForLine / qtyForLine).round() : newPrice;
        await _insertAdjustmentLine(
          paymentId: paymentId,
          txId: txId,
          productId: item.productId,
          productUnitId: item.productUnitId,
          qty: qtyForLine,
          priceAtSale: priceForLine,
          now: now,
        );
      }

      // Jejak audit ringan (amount 0 → tidak memengaruhi dibayar).
      // `changeGiven`/`sisaAfter` diisi sesuai apakah item dihapus/
      // diturunkan sampai total nota jatuh di bawah/di atas uang yang
      // sudah disetor — lihat dok [_paymentDeltaAfterUnpaidItemChange].
      // Jalur ini kena pola yang SAMA dgn retur (bug dilaporkan user
      // menyoal retur, tapi hapus/edit item menghasilkan kelebihan bayar
      // yang identik).
      final delta = await _paymentDeltaAfterUnpaidItemChange(txId);
      await into(transactionPayments)
          .insert(TransactionPaymentsCompanion.insert(
        id: paymentId,
        transactionId: txId,
        amount: 0,
        method: 'edit',
        paidAt: Value(now),
        kasirId: Value(kasirId),
        changeGiven: Value(delta.changeGiven),
        sisaAfter: Value(delta.sisaAfter),
        note: Value(clampedQty <= 0
            ? 'Item dihapus (nota belum lunas)'
            : 'Item diubah (nota belum lunas)'),
      ));

      await _reconcileTransactionTotals(txId);

      // Sama seperti returnUnpaidTransactionItems: nota tanpa tagihan
      // tersisa (mis. item terakhir dihapus) tidak boleh tetap "menggantung".
      final after = await (select(transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (after != null && after.total <= 0 && after.status != 'lunas') {
        await (update(transactions)..where((t) => t.id.equals(txId))).write(
            TransactionsCompanion(
                status: const Value('lunas'),
                changeAmount: const Value(0),
                updatedAt: Value(DateTime.now())));
      }

      await _rebuildDailySummaryFor(_dateKey(tx.createdAt));
    });
  }

  /// Item 49g — qty yang sudah diretur (baris `qty` NEGATIF) per
  /// productUnitId DALAM transaksi yang SAMA. Retur nota lunas TIDAK bikin
  /// nota terpisah lagi (beda dari [getReturnedQtyByUnit] lama yang match
  /// by `internalNote 'RETUR:txId'` pada nota LAIN) — cukup jumlah baris
  /// `qty<0` pada tx yang sama.
  Future<Map<String, double>> getReturnedQtyInTx(String txId) async {
    final rows = await (select(transactionItems)
          ..where((t) =>
              t.transactionId.equals(txId) & t.qty.isSmallerThanValue(0)))
        .get();
    final out = <String, double>{};
    for (final r in rows) {
      out[r.productUnitId] = (out[r.productUnitId] ?? 0) + (-r.qty);
    }
    return out;
  }

  /// Item 49g — retur nota SUDAH LUNAS: TIDAK bikin nota baru (beda dari
  /// [addReturnTransaction] lama, dipertahankan tapi tidak lagi dipanggil
  /// dari sheet retur in-app). Insert baris item BARU ber-qty NEGATIF (item
  /// ASLI tidak pernah dihapus/diubah) ditandai `returnedAt` — dikelompokkan
  /// render-nya via separator "--- Retur HH:MM ---", pola sama dgn
  /// `addedAt`/"Tambahan" — plus baris `transactionPayments` refund NEGATIF
  /// SUNGGUHAN (uang fisik keluar, method dipilih user, BUKAN marker Rp0
  /// spt nota belum-lunas) supaya Tutup Kasir bisa rekonsiliasi kas dgn
  /// benar. [_reconcileTransactionTotals] (dipanggil di akhir) otomatis
  /// menghitung ulang total/paid NET dari SUM seluruh item/payment (positif
  /// & negatif tercampur) — tidak perlu logic manual terpisah utk itu.
  Future<void> returnPaidTransactionItems({
    required String txId,
    required List<({String transactionItemId, double qty})> returns,
    required String kasirId,
    required String refundMethod,
    String? refundMethodName,
  }) async {
    if (returns.isEmpty) return;
    await transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return;
      if (tx.status != 'lunas') {
        throw StateError(
            'returnPaidTransactionItems hanya untuk nota LUNAS (status saat '
            'ini: ${tx.status})');
      }
      final now = DateTime.now();
      final alreadyReturned = await getReturnedQtyInTx(txId);
      var refundTotal = 0;
      var anyReturned = false;
      final paymentId = const Uuid().v4();

      for (final r in returns) {
        if (r.qty <= 0) continue;
        final item = await (select(transactionItems)
              ..where((t) => t.id.equals(r.transactionItemId)))
            .getSingleOrNull();
        // Hanya boleh meretur baris PENJUALAN (qty positif) — baris retur
        // lama (qty negatif) bukan target retur ulang.
        if (item == null || item.transactionId != txId || item.qty <= 0) {
          continue;
        }

        // "Sudah dibeli" bersih utk unit ini — bisa gabungan baris asli +
        // susulan Tambah Belanjaan, semua baris qty positif unit yang sama.
        final boughtRows = await (select(transactionItems)
              ..where((t) =>
                  t.transactionId.equals(txId) &
                  t.productUnitId.equals(item.productUnitId) &
                  t.qty.isBiggerThanValue(0)))
            .get();
        final bought = boughtRows.fold<double>(0, (s, i) => s + i.qty);
        final returnedSoFar = alreadyReturned[item.productUnitId] ?? 0;
        final maxReturnable =
            (bought - returnedSoFar).clamp(0.0, double.infinity);
        final retQty = r.qty.clamp(0.0, maxReturnable);
        if (retQty <= 0) continue;
        anyReturned = true;
        // Lacak supaya retur MULTI-BARIS (beberapa productUnitId sekaligus
        // dlm satu panggilan) tidak saling melebihi batas masing-masing.
        alreadyReturned[item.productUnitId] = returnedSoFar + retQty;

        final subtotal = (item.priceAtSale * retQty).round();
        refundTotal += subtotal;

        await into(transactionItems).insert(TransactionItemsCompanion.insert(
          id: const Uuid().v4(),
          transactionId: txId,
          productId: item.productId,
          productUnitId: item.productUnitId,
          qty: -retQty,
          priceAtSale: item.priceAtSale,
          originalPrice: item.originalPrice,
          subtotal: -subtotal,
          returnedAt: Value(now),
        ));

        await _appendStock(
          productUnitId: item.productUnitId,
          qtyChange: retQty,
          type: 'return_in',
          referenceId: txId,
          kasirId: kasirId,
          note: 'Retur (nota lunas)',
          now: now,
        );

        // Rincian per-produk momen ini — nilai EKSAK (retQty/priceAtSale/
        // subtotal), tidak perlu pendekatan spt jalur edit (baris retur di
        // atas TIDAK mengubah data lama in-place, jadi nilainya sudah pasti).
        await _insertAdjustmentLine(
          paymentId: paymentId,
          txId: txId,
          productId: item.productId,
          productUnitId: item.productUnitId,
          qty: retQty,
          priceAtSale: item.priceAtSale,
          now: now,
        );
      }
      if (!anyReturned) return;

      // Refund SUNGGUHAN (uang fisik keluar) — beda dari marker Rp0 nota
      // belum-lunas, method dipilih user (tunai/transfer/dst).
      await into(transactionPayments)
          .insert(TransactionPaymentsCompanion.insert(
        id: paymentId,
        transactionId: txId,
        amount: -refundTotal,
        method: refundMethod,
        methodName: Value(refundMethodName),
        paidAt: Value(now),
        kasirId: Value(kasirId),
        note: const Value('Refund retur (nota lunas)'),
      ));

      // Poin loyalty direverse proporsional thd nilai refund (pola sama
      // dgn addReturnTransaction lama).
      if (tx.customerId != null && tx.pointsEarned > 0 && tx.total > 0) {
        final proportion = (refundTotal / tx.total).clamp(0.0, 1.0);
        final pointsToReverse =
            (tx.pointsEarned * proportion).round().clamp(0, tx.pointsEarned);
        if (pointsToReverse > 0) {
          await customUpdate(
            'UPDATE customers SET loyalty_points = loyalty_points - ? WHERE id = ?',
            variables: [
              Variable.withInt(pointsToReverse),
              Variable.withString(tx.customerId!),
            ],
            updates: {customers},
          );
          await into(loyaltyPointLedger)
              .insert(LoyaltyPointLedgerCompanion.insert(
            id: const Uuid().v4(),
            customerId: tx.customerId!,
            type: 'adjust',
            points: -pointsToReverse,
            note: Value('Retur ${tx.localId}'),
            createdAt: Value(now),
          ));
        }
      }

      await _reconcileTransactionTotals(txId);
      await _rebuildDailySummaryFor(_dateKey(tx.createdAt));
    });
  }

  /// Item 49g — edit baris item nota SUDAH LUNAS langsung DI TEMPAT (bukan
  /// separator+baris terpisah spt retur — user pilih "update langsung",
  /// konsisten visual dgn [editUnpaidTransactionItem]). Constraint SAMA
  /// dgn nota belum-lunas: qty cuma boleh BERKURANG/dihapus (menaikkan qty
  /// di nota yg uangnya sudah settled akan merusak alokasi pembayaran).
  /// Kalau nilai baris turun (harga/qty berkurang), sisipkan refund NEGATIF
  /// SUNGGUHAN (beda dari nota belum-lunas yg cukup marker Rp0, krn di sini
  /// uangnya memang sudah pernah masuk).
  Future<void> editPaidTransactionItem({
    required String txId,
    required String transactionItemId,
    required double newQty,
    required int newPrice,
    String? newNote,
    required String kasirId,
    required String refundMethod,
  }) async {
    await transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return;
      if (tx.status != 'lunas') {
        throw StateError(
            'editPaidTransactionItem hanya untuk nota LUNAS (status saat '
            'ini: ${tx.status})');
      }
      final item = await (select(transactionItems)
            ..where((t) => t.id.equals(transactionItemId)))
          .getSingleOrNull();
      if (item == null || item.transactionId != txId || item.qty <= 0) return;

      final clampedQty = newQty.clamp(0.0, item.qty);
      final now = DateTime.now();
      final newSubtotal = (newPrice * clampedQty).round();
      final delta = item.subtotal - newSubtotal; // > 0 = nilai turun -> refund
      // Cuma boleh nilai turun/tetap, tidak boleh naik (qty SUDAH di-clamp
      // ke item.qty, jadi ini menangkap kasus harga dinaikkan juga). delta
      // == 0 tetap DIIZINKAN (mis. cuma catatan yang diubah, harga/qty
      // sama) — jangan return lebih awal, baris item tetap perlu diupdate.
      if (newSubtotal > item.subtotal) return;

      final qtyDelta = clampedQty - item.qty; // selalu <= 0 di sini
      if (qtyDelta < 0) {
        await _appendStock(
          productUnitId: item.productUnitId,
          qtyChange: -qtyDelta,
          type: 'return_in',
          referenceId: txId,
          kasirId: kasirId,
          note: 'Edit item (nota lunas)',
          now: now,
        );
      }

      if (clampedQty <= 0) {
        await (delete(transactionItems)..where((t) => t.id.equals(item.id)))
            .go();
      } else {
        await (update(transactionItems)..where((t) => t.id.equals(item.id)))
            .write(TransactionItemsCompanion(
          qty: Value(clampedQty),
          priceAtSale: Value(newPrice),
          subtotal: Value(newSubtotal),
          itemNote: Value(newNote?.isEmpty ?? true ? null : newNote),
        ));
      }

      // Refund SUNGGUHAN (beda dari marker Rp0 nota belum-lunas — di sini
      // uangnya memang sudah masuk sebelumnya) — cuma kalau NILAINYA
      // beneran turun (delta > 0). Edit yang cuma ubah catatan (delta == 0)
      // tidak butuh refund sama sekali — dan tanpa refund, tidak ada baris
      // pembayaran utk ditautkan rincian per-produknya, jadi juga dilewati.
      if (delta > 0) {
        final paymentId = const Uuid().v4();
        // qtyForLine: qty yang berkurang, fallback ke qty final kalau qty
        // tidak berubah (delta murni dari penurunan harga) — pola sama dgn
        // editUnpaidTransactionItem, tapi subtotalForLine di sini EKSAK
        // (langsung `delta`, bukan diturunkan dari selisih).
        final qtyDeltaAbs = qtyDelta.abs();
        final qtyForLine = qtyDeltaAbs > 0 ? qtyDeltaAbs : clampedQty;
        final priceForLine =
            qtyForLine > 0 ? (delta / qtyForLine).round() : newPrice;
        await _insertAdjustmentLine(
          paymentId: paymentId,
          txId: txId,
          productId: item.productId,
          productUnitId: item.productUnitId,
          qty: qtyForLine,
          priceAtSale: priceForLine,
          now: now,
        );
        await into(transactionPayments)
            .insert(TransactionPaymentsCompanion.insert(
          id: paymentId,
          transactionId: txId,
          amount: -delta,
          method: refundMethod,
          paidAt: Value(now),
          kasirId: Value(kasirId),
          note: Value(clampedQty <= 0
              ? 'Refund: item dihapus (nota lunas)'
              : 'Refund: item diubah (nota lunas)'),
        ));
      }

      await _reconcileTransactionTotals(txId);
      await _rebuildDailySummaryFor(_dateKey(tx.createdAt));
    });
  }

  // ───────────────────────── Customer debt ─────────────────────────

  /// Buku hutang: pelanggan dengan nota belum lunas, diurut dari yang paling
  /// lama menunggak (nota tertua yang belum lunas). Diturunkan dari tabel
  /// transactions (lebih akurat dari kolom cache `customers.outstandingDebt`).
  ///
  /// Item 56 — `total - paid` MENTAH salah: `paid` SENGAJA boleh melebihi
  /// `total` (kembalian dipakai ulang, lihat dok `netRemainingOwed` di
  /// `receipt_screen.dart`). `SUM(total-paid)` per pelanggan bisa jadi
  /// NEGATIF kalau ada nota LAIN milik pelanggan yang sama yang overpay
  /// begitu — menutupi nota tempo asli, `HAVING debt > 0` gagal, SELURUH
  /// pelanggan hilang dari Buku Hutang walau tiap nota individual
  /// `status`-nya tetap benar. Fix: net dari `change_given` (LEFT JOIN
  /// subquery per transaksi), pola SQL sepadan `netRemainingOwed`.
  Future<List<DebtBookEntry>> getDebtBook() async {
    final rows = await customSelect(
      'SELECT c.id AS cid, c.name AS name, c.phone AS phone, '
      'SUM((t.total - t.paid) + COALESCE(cg.total_cg, 0)) AS debt, '
      'MIN(t.created_at) AS oldest, COUNT(*) AS cnt '
      'FROM transactions t JOIN customers c ON c.id = t.customer_id '
      'LEFT JOIN (SELECT transaction_id, SUM(change_given) AS total_cg '
      '  FROM transaction_payments WHERE NOT voided GROUP BY transaction_id) cg '
      '  ON cg.transaction_id = t.id '
      "WHERE t.status IN ('kurang_bayar', 'tempo') "
      'GROUP BY c.id HAVING debt > 0 ORDER BY oldest ASC',
      readsFrom: {transactions, customers, transactionPayments},
    ).get();
    return rows.map((r) {
      final oldest = r.data['oldest'] as int;
      return DebtBookEntry(
        customerId: r.data['cid'] as String,
        name: r.data['name'] as String,
        phone: r.data['phone'] as String?,
        debt: (r.data['debt'] as num).toInt(),
        oldest: DateTime.fromMillisecondsSinceEpoch(oldest * 1000),
        count: r.data['cnt'] as int,
      );
    }).toList();
  }

  /// ID nota belum lunas milik pelanggan, terlama dulu (untuk pelunasan FIFO
  /// via [settleMergedDebt]).
  Future<List<String>> getUnpaidTxIds(String customerId) async {
    final rows = await (select(transactions)
          ..where((t) =>
              t.customerId.equals(customerId) &
              t.status.isIn(['kurang_bayar', 'tempo']))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map((t) => t.id).toList();
  }

  /// Nota belum lunas milik pelanggan, LENGKAP (nomor, tanggal, sisa),
  /// terlama dulu — dipakai Buku Hutang untuk menampilkan daftar nota
  /// individual (Item baru: "lihat nota mana saja yang belum lunas").
  ///
  /// Item 56 — `sisa` net dari `change_given` (pola sama `netRemainingOwed`
  /// di `receipt_screen.dart`), bukan `total - paid` mentah.
  Future<List<UnpaidTxEntry>> getUnpaidTxDetails(String customerId) async {
    final rows = await (select(transactions)
          ..where((t) =>
              t.customerId.equals(customerId) &
              t.status.isIn(['kurang_bayar', 'tempo']))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final paymentsByTx =
        await getPaymentsForTxs(rows.map((t) => t.id).toList());
    return rows.map((t) {
      final sumChangeGiven = (paymentsByTx[t.id] ?? const [])
          .where((p) => !p.voided)
          .fold<int>(0, (s, p) => s + p.changeGiven);
      final sisa = t.total - t.paid + sumChangeGiven;
      return UnpaidTxEntry(
        id: t.id,
        localId: t.localId,
        createdAt: t.createdAt,
        sisa: sisa > 0 ? sisa : 0,
      );
    }).toList();
  }

  /// Total hutang akumulatif pelanggan + jumlah nota yang belum lunas.
  ///
  /// Item 56 — net dari `change_given`, pola sama [getDebtBook]/
  /// `netRemainingOwed`, walau `debtCount` (gerbang tampil cart bar) tidak
  /// kena bug lama krn `COUNT(*)`, bukan `SUM`.
  Future<(int debtTotal, int debtCount)> getCustomerOutstandingDebt(
      String customerId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM((t.total - t.paid) + COALESCE(cg.total_cg, 0)), 0) '
      '  AS total, COUNT(*) AS cnt '
      'FROM transactions t '
      'LEFT JOIN (SELECT transaction_id, SUM(change_given) AS total_cg '
      '  FROM transaction_payments WHERE NOT voided GROUP BY transaction_id) cg '
      '  ON cg.transaction_id = t.id '
      "WHERE t.customer_id = ? AND t.status IN ('kurang_bayar', 'tempo')",
      variables: [Variable.withString(customerId)],
      readsFrom: {transactions, transactionPayments},
    ).getSingleOrNull();
    final total = (row?.data['total'] as int?) ?? 0;
    final cnt = (row?.data['cnt'] as int?) ?? 0;
    return (total, cnt);
  }

  /// Sisa tagihan NET per transaksi (dikurangi kembalian yang sudah
  /// diberikan/dipakai ulang) — pola SQL sama persis [getDebtBook]/
  /// [getCustomerOutstandingDebt], batched (hindari N+1) supaya aman dipakai
  /// utk daftar (Riwayat Transaksi) yang bisa berisi puluhan/ratusan baris
  /// hutang sekaligus.
  ///
  /// Bug dilaporkan user: layar Riwayat Transaksi (`tx_history_sheet.dart`)
  /// menampilkan "Sisa" dari `tx.total - tx.paid` MENTAH — beda dari struk
  /// (`receipt_screen.dart`'s `netRemainingOwed`) yang sudah benar net dari
  /// `change_given`. Kalau kembalian dari pembayaran sebelumnya dipakai ulang
  /// sbg pembayaran baru (`paid` naik lagi tanpa pernah dikurangi saat keluar
  /// sbg kembalian), raw `total-paid` bisa NEGATIF padahal net-nya masih
  /// positif (nota masih ada sisa) — sama akar dgn Item 56 (Buku Hutang),
  /// beda lokasi (Buku Hutang sudah dibenerin, Riwayat Transaksi belum).
  Future<Map<String, int>> getNetSisaForTxIds(Iterable<String> txIds) async {
    final ids = txIds.toSet().toList();
    if (ids.isEmpty) return {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await customSelect(
      'SELECT t.id AS id, '
      '  (t.total - t.paid + COALESCE(cg.total_cg, 0)) AS sisa '
      'FROM transactions t '
      'LEFT JOIN (SELECT transaction_id, SUM(change_given) AS total_cg '
      '  FROM transaction_payments WHERE NOT voided GROUP BY transaction_id) cg '
      '  ON cg.transaction_id = t.id '
      'WHERE t.id IN ($placeholders)',
      variables: [for (final id in ids) Variable.withString(id)],
      readsFrom: {transactions, transactionPayments},
    ).get();
    return {
      for (final r in rows)
        r.data['id'] as String: () {
          final raw = ((r.data['sisa'] as num?) ?? 0).toInt();
          return raw > 0 ? raw : 0;
        }(),
    };
  }

  // ───────────────────────── Pembayaran (buku pembayaran) ─────────────────────────

  /// Riwayat pembayaran satu transaksi, urut waktu (terlama dulu). Sumber
  /// timeline pembayaran di struk — kapan tiap cicilan/pelunasan masuk.
  Future<List<TransactionPayment>> getPaymentsForTx(String txId) =>
      (select(transactionPayments)
            ..where((t) => t.transactionId.equals(txId))
            ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
          .get();

  /// Rincian per-produk retur/edit satu nota, dikelompokkan per `paymentId`
  /// (satu momen retur/edit bisa punya beberapa produk) — dipakai kartu
  /// "Riwayat Pembayaran" in-app utk menampilkan baris produk di bawah
  /// momen retur/edit terkait. Lihat dok `TransactionAdjustmentLines`.
  Future<Map<String, List<TransactionAdjustmentLine>>> getAdjustmentLinesForTx(
      String txId) async {
    final rows = await (select(transactionAdjustmentLines)
          ..where((t) => t.transactionId.equals(txId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final out = <String, List<TransactionAdjustmentLine>>{};
    for (final r in rows) {
      (out[r.paymentId] ??= []).add(r);
    }
    return out;
  }

  /// Riwayat pembayaran untuk beberapa transaksi (gabung nota), dikelompokkan
  /// per transactionId, masing-masing urut waktu.
  Future<Map<String, List<TransactionPayment>>> getPaymentsForTxs(
      List<String> txIds) async {
    if (txIds.isEmpty) return {};
    final rows = await (select(transactionPayments)
          ..where((t) => t.transactionId.isIn(txIds))
          ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
        .get();
    final out = <String, List<TransactionPayment>>{};
    for (final r in rows) {
      (out[r.transactionId] ??= []).add(r);
    }
    return out;
  }

  /// Catat pembayaran susulan ("Tambah Bayar") pada satu nota.
  ///
  /// `paid` dicatat PENUH (boleh melebihi total → selisihnya jadi kembalian),
  /// konsisten dengan perilaku layar kasir (tunai berlebih tercatat utuh) dan
  /// dengan `_reconcileTransactionTotals` yang menurunkan `change_amount`
  /// dari `paid - total`. Kalau paid di-cap di total sementara kembalian
  /// disimpan terpisah, rekonsiliasi mana pun (sync, tambah belanjaan, retur)
  /// akan menimpa kembalian itu kembali ke 0 dan info "Kembali Rp X" hilang.
  ///
  /// Mengembalikan kembalian (0 bila pas/kurang). Nota void / tidak ditemukan
  /// → tidak melakukan apa pun dan mengembalikan 0.
  Future<int> addPaymentToTransaction({
    required String txId,
    required int amount,
    required String method,
    required String kasirId,
    String? methodName,
    String? note,
    DateTime? now,
  }) async {
    if (amount <= 0) return 0;
    final ts = now ?? DateTime.now();
    return transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return 0;
      final delta = await _computePaymentDelta(
        txId: txId,
        newPaymentAmount: amount,
        currentTotal: tx.total,
      );
      await into(transactionPayments)
          .insert(TransactionPaymentsCompanion.insert(
        id: const Uuid().v4(),
        transactionId: txId,
        amount: amount,
        method: method,
        methodName: Value(methodName),
        paidAt: Value(ts),
        kasirId: Value(kasirId),
        note: Value(note),
        changeGiven: Value(delta.changeGiven),
        sisaAfter: Value(delta.sisaAfter),
      ));
      // Status dari `paid` dikurangi TOTAL kembalian yang pernah diberikan
      // (termasuk baris ini) — sama alasannya seperti di
      // `_reconcileTransactionTotals`: kembalian lama yang dipakai ulang
      // sbg pembayaran ini jangan sampai ke-hitung dobel di `paid`.
      final changeSum = transactionPayments.changeGiven.sum();
      final sumRow = await (selectOnly(transactionPayments)
            ..addColumns([changeSum])
            ..where(transactionPayments.transactionId.equals(txId) &
                transactionPayments.voided.equals(false)))
          .getSingle();
      final sumChangeGiven = sumRow.read(changeSum) ?? 0;
      final newPaid = tx.paid + amount;
      final netPaidForStatus = newPaid - sumChangeGiven;
      final change = newPaid > tx.total ? newPaid - tx.total : 0;
      await (update(transactions)..where((t) => t.id.equals(txId))).write(
        TransactionsCompanion(
          paid: Value(newPaid),
          status:
              Value(netPaidForStatus >= tx.total ? 'lunas' : 'kurang_bayar'),
          changeAmount: Value(change),
          updatedAt: Value(ts),
        ),
      );
      return delta.changeGiven;
    });
  }

  /// "Batalkan Pembayaran" — membatalkan SATU baris pembayaran. Baris TETAP
  /// tersimpan (jejak audit "pernah dibayar, lalu dibatalkan"), tapi
  /// `paid`/status nota dihitung ulang seolah baris itu tidak pernah ada.
  /// Item & stok TIDAK disentuh (beda dari void transaksi/`voidTransaction`
  /// yang membatalkan SELURUH nota). Nota `void` / baris sudah dibatalkan /
  /// tidak ditemukan → tidak melakukan apa pun.
  ///
  /// Bug ditemukan saat review logika retur/kembalian (permintaan user):
  /// baris refund retur (`amount` negatif, uang fisik SUDAH keluar & stok
  /// SUDAH dikembalikan lewat `returnPaidTransactionItems`/
  /// `editPaidTransactionItem`) atau marker retur nota belum-lunas
  /// (`method` 'retur'/'edit') TIDAK BOLEH ikut dibatalkan di sini — asumsi
  /// "item & stok TIDAK disentuh" di atas SALAH untuk baris itu (sudah
  /// berubah PERMANEN sbg bagian dari retur, di baris/tabel lain yang tidak
  /// ikut dibatalkan kalau baris ini yang dibatalkan). Efeknya kalau
  /// dibiarkan: `paid` balik naik tanpa `total`/item ikut balik → kembalian
  /// HANTU (dihitung ulang seolah harus diserahkan lagi, padahal sudah
  /// pernah). Guard di sini (bukan cuma sembunyikan tombol UI) supaya
  /// caller lain di masa depan tidak bisa kena bug yang sama.
  /// Item 61 — pembayaran DP/jaminan pre-order (note persis
  /// `_kPreorderDepositNote`, dipakai `collectPreorderDeposit`) dibatalkan
  /// via jalur ini SEBELUMNYA hanya membalik nominal `paid`/status nota
  /// dgn benar (`_reconcileTransactionTotals`, tidak ada uang hilang scr
  /// nominal), TAPI tidak pernah membalik efek `collectPreorderDeposit`
  /// yang lain: `transactionItems.priceAtSale`/`subtotal` baris pre-order
  /// yang tadinya dinaikkan dari Rp0 ke harga asli TETAP di harga asli, dan
  /// `preorderEntries.paid` tetap `true` — status "DP sudah dibayar"
  /// nyangkut walau pembayarannya sudah dibatalkan.
  ///
  /// Fix: kalau baris yang dibatalkan adalah DP pre-order, REVERSE eksplisit
  /// (kebalikan PERSIS dari `collectPreorderDeposit`) — item balik ke Rp0,
  /// `preorderEntries.paid` balik `false`. Tidak ada tautan `entryId`
  /// langsung dari baris pembayaran ke `preorder_entries` (kolom itu tidak
  /// ada) — dicocokkan lewat `transactionId` + `paid=true` + `updatedAt`
  /// TERDEKAT dgn `paidAt` pembayaran ini (keduanya dicap dlm SATU
  /// `transaction()` di `collectPreorderDeposit`, jaraknya cuma milidetik).
  /// Kasus nota dgn LEBIH DARI SATU entri pre-order yang masing² py DP
  /// terpisah: heuristik ini pilih SATU entri paling dekat waktunya,
  /// bukan sempurna utk skenario itu (jarang terjadi di praktik toko) —
  /// dicatat sbg batasan yang diketahui, bukan diabaikan diam-diam.
  Future<void> voidPayment(String paymentId) async {
    await transaction(() async {
      final pay = await (select(transactionPayments)
            ..where((t) => t.id.equals(paymentId)))
          .getSingleOrNull();
      if (pay == null || pay.voided) return;
      if (pay.amount < 0 || pay.method == 'retur' || pay.method == 'edit') {
        return;
      }
      final tx = await (select(transactions)
            ..where((t) => t.id.equals(pay.transactionId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return;

      await (update(transactionPayments)..where((t) => t.id.equals(paymentId)))
          .write(const TransactionPaymentsCompanion(voided: Value(true)));
      await _reconcileTransactionTotals(pay.transactionId);

      if (pay.note == _kPreorderDepositNote) {
        final candidates = await (select(preorderEntries)
              ..where((t) =>
                  t.transactionId.equals(pay.transactionId) &
                  t.paid.equals(true) &
                  t.transactionItemId.isNotNull()))
            .get();
        if (candidates.isNotEmpty) {
          candidates.sort((a, b) => (a.updatedAt.difference(pay.paidAt))
              .abs()
              .compareTo((b.updatedAt.difference(pay.paidAt)).abs()));
          final entry = candidates.first;
          final item = await (select(transactionItems)
                ..where((t) => t.id.equals(entry.transactionItemId!)))
              .getSingleOrNull();
          if (item != null) {
            await (update(transactionItems)
                  ..where((t) => t.id.equals(item.id)))
                .write(const TransactionItemsCompanion(
              priceAtSale: Value(0),
              subtotal: Value(0),
            ));
            await _reconcileTransactionTotals(pay.transactionId);
          }
          final now = DateTime.now();
          await (update(preorderEntries)..where((t) => t.id.equals(entry.id)))
              .write(PreorderEntriesCompanion(
            paid: const Value(false),
            updatedAt: Value(now),
          ));
          await recordLaciMejaEvent(
            id: '${entry.id}-batal-dp-${now.microsecondsSinceEpoch}',
            entityType: 'preorder',
            entryId: entry.id,
            aksi: 'batal',
            note: 'DP dibatalkan (voidPayment)',
            deviceCode: pay.kasirId,
          );
        }
      }
    });
  }

  /// Note persis yang ditulis `collectPreorderDeposit` — dibagi ke konstanta
  /// supaya `voidPayment` tidak diam-diam meleset kalau salah satu diketik
  /// ulang beda.
  static const _kPreorderDepositNote = 'DP/jaminan pre-order';

  // ───────────────────────── Expenses (pengeluaran) ────────────────────────

  /// Jenis expense yang dihitung sebagai pengurang Laba Bersih.
  /// `daily_expense` = biaya operasional; `change_given` = uang keluar laci
  /// tanpa transaksi. `owner_withdrawal` (ambil laba pribadi) &
  /// `supplier_payment` (modal barang — SUDAH terhitung di HPP lewat
  /// cost_at_sale) SENGAJA tidak dihitung agar Laba Bersih tidak dobel/salah.
  static const netProfitExpenseTypes = ['daily_expense', 'change_given'];

  Future<void> addExpense({
    required String type,
    required int amount,
    String? note,
    String? kasirId,
    DateTime? createdAt,
  }) async {
    final id = const Uuid().v4();
    await into(expenses).insert(ExpensesCompanion.insert(
      id: id,
      localId: id,
      type: type,
      amount: amount,
      note: Value(note),
      kasirId: Value(kasirId),
      createdAt: createdAt == null ? const Value.absent() : Value(createdAt),
    ));
  }

  /// Item 61.5 — soft-delete (UPDATE `deleted_at`, bukan hard DELETE):
  /// `expenses` sync-nya append-only (cuma kirim baris BARU) — hard DELETE
  /// TIDAK PERNAH propagate ke device lain yang sudah menerima baris itu,
  /// laba bersih antar-device beda permanen. UPDATE ini ikut ter-sync sbg
  /// baris "diupdate" (lihat dok `dumpSince`/`mergeRows` bagian `expenses`).
  Future<void> deleteExpense(String id) =>
      (update(expenses)..where((t) => t.id.equals(id)))
          .write(ExpensesCompanion(deletedAt: Value(DateTime.now())));

  /// Semua pengeluaran dalam rentang [from]..[to], terbaru dulu. Yang
  /// soft-deleted (Item 61.5) tidak ikut tampil.
  Stream<List<Expense>> watchExpenses(DateTime from, DateTime to) {
    return (select(expenses)
          ..where((t) =>
              t.createdAt.isBiggerOrEqualValue(from) &
              t.createdAt.isSmallerOrEqualValue(to) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Total pengeluaran yang mengurangi Laba Bersih (daily_expense +
  /// change_given) dalam rentang. Yang soft-deleted dikecualikan.
  Future<int> getNetProfitExpenseTotal(DateTime from, DateTime to) async {
    final amountSum = expenses.amount.sum();
    final row = await (selectOnly(expenses)
          ..addColumns([amountSum])
          ..where(expenses.type.isIn(netProfitExpenseTypes) &
              expenses.createdAt.isBiggerOrEqualValue(from) &
              expenses.createdAt.isSmallerOrEqualValue(to) &
              expenses.deletedAt.isNull()))
        .getSingle();
    return row.read(amountSum) ?? 0;
  }

  /// Item 49d — breakdown pengeluaran per JENIS (`type`) dalam rentang, utk
  /// tab Laporan Pengeluaran (rincian + grafik). SEMUA jenis (daily_expense/
  /// owner_withdrawal/supplier_payment/change_given) — beda dari
  /// [getNetProfitExpenseTotal] yang cuma hitung subset [netProfitExpenseTypes]
  /// yang mengurangi Laba Bersih. Tab ini murni "ke mana saja uang mengalir",
  /// bukan P&L. Yang soft-deleted dikecualikan.
  Future<Map<String, int>> getExpenseBreakdownByType(
      DateTime from, DateTime to) async {
    final amountSum = expenses.amount.sum();
    final rows = await (selectOnly(expenses)
          ..addColumns([expenses.type, amountSum])
          ..where(expenses.createdAt.isBiggerOrEqualValue(from) &
              expenses.createdAt.isSmallerOrEqualValue(to) &
              expenses.deletedAt.isNull())
          ..groupBy([expenses.type]))
        .get();
    return {
      for (final r in rows) r.read(expenses.type)!: r.read(amountSum) ?? 0,
    };
  }

  /// Item 49d — total pengeluaran (SEMUA jenis digabung) per HARI (lokal)
  /// dalam rentang, utk grafik tren tab Laporan Pengeluaran. Pola query sama
  /// dgn `rebuildStaleSummariesInRange` (strftime unixepoch→localtime). Yang
  /// soft-deleted dikecualikan.
  Future<Map<DateTime, int>> getExpenseDailyTotals(
      DateTime from, DateTime to) async {
    final fromSec = from.millisecondsSinceEpoch ~/ 1000;
    final toSec = to.millisecondsSinceEpoch ~/ 1000;
    final rows = await customSelect(
      "SELECT strftime('%Y-%m-%d', datetime(created_at,'unixepoch','localtime')) AS d, "
      'COALESCE(SUM(amount),0) AS total '
      'FROM expenses WHERE created_at >= ? AND created_at <= ? '
      'AND deleted_at IS NULL GROUP BY d',
      variables: [Variable.withInt(fromSec), Variable.withInt(toSec)],
      readsFrom: {expenses},
    ).get();
    final out = <DateTime, int>{};
    for (final r in rows) {
      final parts = (r.data['d'] as String).split('-').map(int.parse).toList();
      out[DateTime(parts[0], parts[1], parts[2])] =
          (r.data['total'] as num).round();
    }
    return out;
  }

  /// Lunasi beberapa nota sekaligus (gabung nota) dengan distribusi FIFO:
  /// nota terlama dilunasi lebih dulu, sisa uang mengalir ke nota berikutnya.
  /// Setiap nota mendapat satu entri pembayaran ber-`paidAt` sama → jejak
  /// audit pelunasan gabungan. Nota yang sudah lunas dilewati.
  ///
  /// Tidak menyentuh ringkasan harian: omzet/HPP dihitung dari `total` &
  /// item, bukan `paid`, jadi pelunasan tidak mengubah laporan.
  ///
  /// Mengembalikan (jumlah teralokasi ke tagihan, kembalian/kelebihan).
  Future<(int applied, int change)> settleMergedDebt({
    required List<String> txIds,
    required int amount,
    required String method,
    required String kasirId,
    String? methodName,
  }) async {
    if (txIds.isEmpty || amount <= 0) return (0, 0);
    return transaction(() async {
      final txs = await (select(transactions)
            ..where((t) => t.id.isIn(txIds))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
      // Item 56 — `sisa` net dari `change_given` (pola `netRemainingOwed`),
      // bukan `total - paid` mentah: nota di batch ini bisa saja sudah
      // pernah overpay sebagian (kembalian dipakai ulang), jadi `paid`
      // mentahnya BUKAN sisa hutang yang sebenarnya.
      final paymentsByTx = await getPaymentsForTxs(txIds);
      final now = DateTime.now();
      final label = txs.map((t) => t.localId).join(', ');
      var remaining = amount;
      var totalApplied = 0;
      // Baris pembayaran TERAKHIR yang dibuat di batch ini — kembalian sisa
      // (kalau ada, setelah semua nota di batch ini terlunasi) nempel ke
      // baris ini, bukan dihitung per-nota (tiap nota di loop ini tidak
      // pernah overpay sendiri, `applied` selalu di-cap di `sisa`).
      String? lastPaymentId;
      for (final tx in txs) {
        if (remaining <= 0) break;
        final sumChangeGiven = (paymentsByTx[tx.id] ?? const [])
            .where((p) => !p.voided)
            .fold<int>(0, (s, p) => s + p.changeGiven);
        final sisa = tx.total - tx.paid + sumChangeGiven;
        if (sisa <= 0) continue; // sudah lunas → lewati
        final applied = remaining < sisa ? remaining : sisa;
        final paymentId = const Uuid().v4();
        await into(transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
            id: paymentId,
            transactionId: tx.id,
            amount: applied,
            method: method,
            methodName: Value(methodName),
            paidAt: Value(now),
            kasirId: Value(kasirId),
            note: Value('Gabung: $label'),
            // Nota INI blm tentu lunas total dari pelunasan gabungan
            // (uangnya bisa habis dialokasikan ke nota lebih lama duluan,
            // FIFO) — sisa yang masih menggantung utk nota ini dicatat
            // eksak di sini (bukan lewat `_computePaymentDelta`, `sisa`
            // sudah dihitung tepat di atas).
            sisaAfter: Value(sisa - applied),
          ),
        );
        lastPaymentId = paymentId;
        final newPaid = tx.paid + applied;
        final netPaidForStatus = newPaid - sumChangeGiven;
        await (update(transactions)..where((t) => t.id.equals(tx.id))).write(
          TransactionsCompanion(
            paid: Value(newPaid),
            status:
                Value(netPaidForStatus >= tx.total ? 'lunas' : 'kurang_bayar'),
            updatedAt: Value(now),
          ),
        );
        remaining -= applied;
        totalApplied += applied;
      }
      if (remaining > 0 && lastPaymentId != null) {
        await (update(transactionPayments)
              ..where((t) => t.id.equals(lastPaymentId!)))
            .write(TransactionPaymentsCompanion(changeGiven: Value(remaining)));
      }
      return (totalApplied, remaining);
    });
  }

  /// Backfill buku pembayaran: buat entri untuk nota lama yang punya `paid`
  /// tapi belum punya baris di `transaction_payments` (data dari versi sebelum
  /// buku pembayaran terisi, atau hasil import). Waktu bayar diasumsikan =
  /// `createdAt`. Idempotent & ringan — hanya menyentuh nota tanpa pembayaran.
  /// `paid > 0` sengaja mengecualikan retur (paid negatif) dan tempo (paid 0).
  Future<void> backfillMissingPayments() async {
    final rows = await customSelect(
      'SELECT t.id AS id, t.paid AS paid, t.total AS total, '
      't.payment_method AS method, t.method_name AS method_name, '
      't.kasir_id AS kasir, t.created_at AS created, '
      't.change_amount AS change_amount, t.change_taken AS change_taken '
      'FROM transactions t '
      "WHERE t.paid > 0 AND t.status != 'void' "
      'AND NOT EXISTS (SELECT 1 FROM transaction_payments p '
      'WHERE p.transaction_id = t.id)',
      readsFrom: {transactions, transactionPayments},
    ).get();
    if (rows.isEmpty) return;
    await batch((b) {
      for (final r in rows) {
        final created = r.data['created'];
        final paidAt = created is int
            ? DateTime.fromMillisecondsSinceEpoch(created * 1000)
            : DateTime.now();
        final paid = r.data['paid'] as int;
        final total = (r.data['total'] as int?) ?? paid;
        b.insert(
          transactionPayments,
          TransactionPaymentsCompanion.insert(
            id: const Uuid().v4(),
            transactionId: r.data['id'] as String,
            amount: paid,
            method: (r.data['method'] as String?) ?? 'tunai',
            methodName: Value(r.data['method_name'] as String?),
            paidAt: Value(paidAt),
            kasirId: Value(r.data['kasir'] as String?),
            note: const Value('Migrasi data lama'),
            // Satu-satunya pembayaran nota lama → warisi kembalian &
            // status ambil dari header transaksi (sumber lama), supaya
            // Ringkasan (sekarang baca dari baris pembayaran) tidak
            // mendadak kosong untuk nota yang sudah ada sebelum migrasi ini.
            changeGiven: Value((r.data['change_amount'] as int?) ?? 0),
            changeTaken: Value((r.data['change_taken'] as int?) == 1),
            sisaAfter: Value(total > paid ? total - paid : 0),
          ),
        );
      }
    });
  }

  // ───────────────────────── History filter ─────────────────────────

  /// Cari id produk dengan nama mengandung [q] — dipakai bersama oleh
  /// [findTxIdsWithProduct] & [findProductMatchesForQuery].
  ///
  /// SENGAJA cari di tabel `products` dulu (kecil, proporsional ke jumlah SKU
  /// katalog) sebelum menyentuh `transaction_items` (bisa jutaan baris kalau
  /// riwayat toko sudah lama). Sebelumnya kedua fungsi ini melakukan
  /// `JOIN transaction_items+products` lalu filter `LIKE` pada nama produk —
  /// karena `LIKE '%...%'` tidak bisa pakai indeks, itu efektif menyisir
  /// SELURUH riwayat transaksi setiap kali pencarian diketik, makin lambat
  /// makin lama toko beroperasi. Dengan cari product id dulu, langkah kedua
  /// bisa pakai `idx_ti_product` (sudah ada) untuk lompat langsung ke baris
  /// yang relevan — biaya pencarian jadi lepas dari volume riwayat transaksi.
  Future<List<String>> _matchingProductIds(String q) =>
      (select(products)..where((p) => p.name.lower().contains(q.toLowerCase())))
          .map((p) => p.id)
          .get();

  /// Set id transaksi yang memuat produk dengan nama mengandung [q].
  Future<Set<String>> findTxIdsWithProduct(String q) async {
    if (q.trim().isEmpty) return <String>{};
    final productIds = await _matchingProductIds(q);
    if (productIds.isEmpty) return <String>{};
    final rows = await (select(transactionItems)
          ..where((ti) => ti.productId.isIn(productIds)))
        .map((ti) => ti.transactionId)
        .get();
    return rows.toSet();
  }

  /// Detail produk yang cocok per transaksi — untuk tampilan di riwayat saat
  /// filter produk aktif.
  Future<Map<String, List<({String name, double qty, int price})>>>
      findProductMatchesForQuery(String q) async {
    if (q.trim().isEmpty) return {};
    final productIds = await _matchingProductIds(q);
    if (productIds.isEmpty) return {};
    final query = select(transactionItems).join([
      innerJoin(products, products.id.equalsExp(transactionItems.productId)),
    ])
      ..where(transactionItems.productId.isIn(productIds));
    final rows = await query.get();
    final result = <String, List<({String name, double qty, int price})>>{};
    for (final r in rows) {
      final ti = r.readTable(transactionItems);
      final p = r.readTable(products);
      (result[ti.transactionId] ??= []).add((
        name: p.name,
        qty: ti.qty,
        price: ti.priceAtSale,
      ));
    }
    return result;
  }

  // ───────────────────────── Daily summary ─────────────────────────

  static String _dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static int _paymentBucket(String method, Map<int, int> buckets, int total) {
    // 0=tunai 1=qris 2=transfer(bank) 3=lainnya
    //
    // Bug nyata (ditemukan lewat audit tab Ringkasan): nilai `type` yang
    // BENAR-BENAR tersimpan di `transactions.paymentMethod` untuk transfer
    // bank adalah 'bank' (lihat dropdown `payment_methods_screen.dart`) —
    // string 'transfer' TIDAK PERNAH ada di data nyata. Case ini dulu
    // salah cocok, jadi SETIAP transaksi Transfer Bank jatuh ke bucket
    // "lainnya" & `pembayaranTransfer` selalu 0 walau toko rutin terima
    // transfer. E-wallet/tempo TETAP sengaja masuk "lainnya" (lihat dok
    // `DailySummaries` — bucket cuma 4, bukan tabel baru).
    final idx = switch (method) {
      'tunai' => 0,
      'qris' => 1,
      'bank' => 2,
      _ => 3,
    };
    buckets[idx] = (buckets[idx] ?? 0) + total;
    return idx;
  }

  /// Hitung ulang ringkasan satu hari dari data mentah lalu simpan (upsert).
  /// Dipanggil di dalam transaksi penulisan agar atomik.
  Future<void> _rebuildDailySummaryFor(String date) async {
    final parts = date.split('-').map(int.parse).toList();
    final start = DateTime(parts[0], parts[1], parts[2]);
    final end = DateTime(parts[0], parts[1], parts[2], 23, 59, 59, 999);

    final txRows = await (select(transactions)
          ..where((t) =>
              t.status.isNotValue('void') &
              t.createdAt.isBiggerOrEqualValue(start) &
              t.createdAt.isSmallerOrEqualValue(end)))
        .get();

    if (txRows.isEmpty) {
      // Tidak ada transaksi valid → hapus baris ringkasan bila ada.
      await (delete(dailySummaries)..where((t) => t.date.equals(date))).go();
      return;
    }

    var omzet = 0;
    final buckets = <int, int>{};
    for (final t in txRows) {
      // Retur (internalNote 'RETUR:...') bertotal negatif → omzet & bucket
      // sengaja NET (refund mengurangi). Konsisten dgn denominator omzet di
      // ringkasan_tab; bucket harian negatif sudah disaring `> 0` di sana.
      omzet += t.total;
      _paymentBucket(t.paymentMethod, buckets, t.total);
    }

    final txIds = txRows.map((t) => t.id).toList();
    final itemRows = await (select(transactionItems)
          ..where((t) => t.transactionId.isIn(txIds)))
        .get();
    var hpp = 0;
    var jumlahItem = 0;
    for (final i in itemRows) {
      hpp += (i.costAtSale * i.qty).round();
      jumlahItem += i.qty.round();
    }

    await into(dailySummaries).insertOnConflictUpdate(
      DailySummariesCompanion.insert(
        date: date,
        omzet: Value(omzet),
        hpp: Value(hpp),
        labaKotor: Value(omzet - hpp),
        jumlahTransaksi: Value(txRows.length),
        jumlahItem: Value(jumlahItem),
        pembayaranTunai: Value(buckets[0] ?? 0),
        pembayaranQris: Value(buckets[1] ?? 0),
        pembayaranTransfer: Value(buckets[2] ?? 0),
        pembayaranLainnya: Value(buckets[3] ?? 0),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Catch-up: bangun ringkasan untuk tanggal yang punya transaksi tapi belum
  /// ada entri di [dailySummaries]. Dipanggil sekali saat app init — ringan
  /// karena hanya memindai daftar tanggal unik.
  Future<void> backfillMissingSummaries() async {
    final rows = await customSelect(
      "SELECT DISTINCT strftime('%Y-%m-%d', datetime(created_at, 'unixepoch', 'localtime')) AS d "
      "FROM transactions WHERE status != 'void'",
      readsFrom: {transactions},
    ).get();
    final allDates =
        rows.map((r) => r.data['d'] as String?).whereType<String>().toSet();

    final existing = await (selectOnly(dailySummaries)
          ..addColumns([dailySummaries.date]))
        .get();
    final have = existing.map((r) => r.read(dailySummaries.date)!).toSet();

    for (final d in allDates.difference(have)) {
      await _rebuildDailySummaryFor(d);
    }
  }

  /// Bangun ulang ringkasan untuk tanggal yang tersentuh oleh transaksi hasil
  /// sync. Dipanggil SETELAH semua tabel (termasuk transaction_items) di-merge,
  /// agar HPP terhitung benar. `created_at` pada baris mentah = unix detik.
  Future<void> rebuildSummariesForMergedTransactions(
      List<Map<String, Object?>> txRows) async {
    final dates = <String>{};
    for (final r in txRows) {
      final ca = r['created_at'];
      if (ca is int) {
        dates.add(_dateKey(DateTime.fromMillisecondsSinceEpoch(ca * 1000)));
      }
    }
    for (final d in dates) {
      await _rebuildDailySummaryFor(d);
    }
  }

  /// Perbaiki-sendiri ringkasan harian yang BASI di rentang [from]..[to].
  ///
  /// Laporan Ringkasan membaca cache `daily_summaries` (cepat, O(hari)), yang
  /// TIDAK ikut disinkron antar-device melainkan dihitung ulang lokal tiap
  /// merge. Bila sebuah tanggal menerima transaksi lewat sync/merge tapi
  /// entri ringkasannya TIDAK ikut ter-rebuild (mis. build lama tanpa
  /// wiring, restore, atau jalur merge yang terlewat), angka laporan jadi
  /// lebih kecil dari transaksi sebenarnya — walau baris transaksinya sudah
  /// sama di kedua HP. Beda dari [backfillMissingSummaries] yang hanya
  /// menambal tanggal yang BELUM punya entri, ini juga mendeteksi entri yang
  /// JUMLAH/omzet-nya tak cocok dgn transaksi nyata lalu membangunnya ulang.
  ///
  /// Murah: 1 query agregat + rebuild HANYA tanggal yang tidak cocok
  /// (umumnya nol). Dipanggil provider laporan sebelum membaca ringkasan,
  /// jadi laporan selalu cermin transaksi nyata di device ini.
  Future<void> rebuildStaleSummariesInRange(DateTime from, DateTime to) async {
    final fromSec =
        DateTime(from.year, from.month, from.day).millisecondsSinceEpoch ~/
            1000;
    final toSec = DateTime(to.year, to.month, to.day, 23, 59, 59)
            .millisecondsSinceEpoch ~/
        1000;
    // Jumlah & omzet transaksi valid AKTUAL per tanggal (lokal).
    final actualRows = await customSelect(
      "SELECT strftime('%Y-%m-%d', datetime(created_at,'unixepoch','localtime')) AS d, "
      "COUNT(*) AS c, COALESCE(SUM(total),0) AS s "
      "FROM transactions WHERE status != 'void' "
      "AND created_at >= ? AND created_at <= ? GROUP BY d",
      variables: [Variable.withInt(fromSec), Variable.withInt(toSec)],
      readsFrom: {transactions},
    ).get();
    final actual = <String, (int, int)>{
      for (final r in actualRows)
        (r.data['d'] as String): (
          (r.data['c'] as int),
          (r.data['s'] as num).round(),
        ),
    };

    final fromKey = _dateKey(from);
    final toKey = _dateKey(to);
    final summaries = await (select(dailySummaries)
          ..where((t) => t.date.isBetweenValues(fromKey, toKey)))
        .get();
    final cached = <String, (int, int)>{
      for (final sm in summaries) sm.date: (sm.jumlahTransaksi, sm.omzet),
    };

    final toRebuild = <String>{};
    // Tanggal berisi transaksi tapi entri hilang / jumlah / omzet beda.
    actual.forEach((d, v) {
      if (cached[d] != v) toRebuild.add(d);
    });
    // Tanggal beromzet-nol tapi masih punya entri ringkasan (phantom).
    for (final d in cached.keys) {
      if (!actual.containsKey(d)) toRebuild.add(d);
    }
    for (final d in toRebuild) {
      await _rebuildDailySummaryFor(d);
    }
  }

  /// Ringkasan harian untuk rentang tanggal (inklusif). Sumber cepat untuk
  /// laporan — maksimum 1 baris per hari.
  Future<List<DailySummary>> getDailySummaries(
      DateTime from, DateTime to) async {
    final fromKey = _dateKey(from);
    final toKey = _dateKey(to);
    return (select(dailySummaries)
          ..where((t) => t.date.isBetweenValues(fromKey, toKey))
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
  }

  // ───────────── Laporan agregat (JOIN, bukan N+1) ─────────────

  /// Top produk berdasarkan revenue dalam rentang waktu — satu query JOIN.
  Future<List<ProductRevenueStat>> getTopProductsByRevenue(
    DateTime from,
    DateTime to, {
    int limit = 50,
  }) async {
    final revenue = transactionItems.subtotal.sum();
    final qtySold = transactionItems.qty.sum();
    const cogs = CustomExpression<double>(
        'SUM(transaction_items.cost_at_sale * transaction_items.qty)');

    final query = select(transactionItems).join([
      innerJoin(transactions,
          transactions.id.equalsExp(transactionItems.transactionId)),
      innerJoin(products, products.id.equalsExp(transactionItems.productId)),
    ])
      ..addColumns([products.id, products.name, revenue, qtySold, cogs])
      ..where(transactions.status.isNotValue('void') &
          transactions.createdAt.isBiggerOrEqualValue(from) &
          transactions.createdAt.isSmallerOrEqualValue(to))
      ..groupBy([transactionItems.productId])
      ..orderBy([OrderingTerm.desc(revenue)])
      ..limit(limit);

    final rows = await query.get();
    return rows.map((r) {
      return ProductRevenueStat(
        productId: r.read(products.id) ?? '',
        name: r.read(products.name) ?? '',
        revenue: (r.read(revenue) ?? 0),
        qtySold: r.read(qtySold) ?? 0,
        cogs: (r.read(cogs) ?? 0).round(),
      );
    }).toList();
  }

  /// Top pelanggan terdaftar berdasarkan total belanja — satu query JOIN.
  Future<List<CustomerRevenueStat>> getTopCustomersByRevenue(
    DateTime from,
    DateTime to, {
    int limit = 50,
  }) async {
    final spent = transactions.total.sum();
    final txCount = transactions.id.count();

    final query = select(transactions).join([
      innerJoin(customers, customers.id.equalsExp(transactions.customerId)),
    ])
      ..addColumns([
        customers.id,
        customers.name,
        customers.loyaltyPoints,
        spent,
        txCount,
      ])
      ..where(transactions.status.isNotValue('void') &
          transactions.customerId.isNotNull() &
          transactions.createdAt.isBiggerOrEqualValue(from) &
          transactions.createdAt.isSmallerOrEqualValue(to))
      ..groupBy([transactions.customerId])
      ..orderBy([OrderingTerm.desc(spent)])
      ..limit(limit);

    final rows = await query.get();
    return rows.map((r) {
      return CustomerRevenueStat(
        customerId: r.read(customers.id) ?? '',
        name: r.read(customers.name) ?? '',
        loyaltyPoints: r.read(customers.loyaltyPoints) ?? 0,
        totalSpent: r.read(spent) ?? 0,
        txCount: r.read(txCount) ?? 0,
      );
    }).toList();
  }

  // ───────────────────────── Arus Kas ─────────────────────────
  //
  // BEDA MENDASAR dari "Selisih Kas Operasional" di tab Ringkasan (Omzet -
  // Pengeluaran), yang bukan arus kas sungguhan karena:
  //   (a) Omzet memuat nota TEMPO yang belum dibayar sepeser pun, dan
  //   (b) pelunasan hutang nota lama TIDAK terhitung sbg kas masuk di
  //       periode uangnya benar-benar diterima (omzetnya sudah tercatat di
  //       periode nota dibuat).
  // Query di bawah memakai `transaction_payments` (kapan uang BENAR-BENAR
  // berpindah) sbg sumber kas masuk, bukan `transactions` — sehingga kedua
  // masalah di atas hilang sekaligus, dan cicilan/pelunasan susulan
  // otomatis jatuh di tanggal yang benar.

  /// Kas MASUK per metode bayar dalam rentang (berdasar `paid_at`).
  ///
  /// NET dari `change_given`: uang yang diserahkan balik ke pembeli
  /// (kembalian, termasuk kelebihan bayar akibat retur nota belum lunas)
  /// tidak pernah benar-benar mengendap di laci. Baris pembayaran yang
  /// DIBATALKAN (`voided`) dilewati, dan refund retur nota lunas otomatis
  /// ikut terhitung karena `amount`-nya memang NEGATIF.
  Future<Map<String, int>> getCashInByMethod(DateTime from, DateTime to) async {
    final rows = await customSelect(
      'SELECT method, COALESCE(SUM(amount),0) AS amt, '
      '  COALESCE(SUM(change_given),0) AS chg '
      'FROM transaction_payments '
      'WHERE NOT voided AND paid_at >= ? AND paid_at <= ? '
      'GROUP BY method',
      variables: [
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {transactionPayments},
    ).get();
    final out = <String, int>{};
    for (final r in rows) {
      final net =
          (r.data['amt'] as num).toInt() - (r.data['chg'] as num).toInt();
      if (net == 0) continue;
      out[r.data['method'] as String] = net;
    }
    return out;
  }

  /// Tren harian arus kas: kas masuk & kas keluar per tanggal LOKAL.
  /// Dua query terpisah (pembayaran & pengeluaran) digabung di Dart —
  /// UNION di SQL akan menyulitkan pembacaan tanpa keuntungan berarti pada
  /// ukuran data app ini.
  Future<List<CashFlowDaily>> getCashFlowDaily(
      DateTime from, DateTime to) async {
    final fromSec = from.millisecondsSinceEpoch ~/ 1000;
    final toSec = to.millisecondsSinceEpoch ~/ 1000;
    final inRows = await customSelect(
      "SELECT strftime('%Y-%m-%d', datetime(paid_at,'unixepoch','localtime')) AS d, "
      '  COALESCE(SUM(amount),0) - COALESCE(SUM(change_given),0) AS net '
      'FROM transaction_payments '
      'WHERE NOT voided AND paid_at >= ? AND paid_at <= ? GROUP BY d',
      variables: [Variable.withInt(fromSec), Variable.withInt(toSec)],
      readsFrom: {transactionPayments},
    ).get();
    final outRows = await customSelect(
      "SELECT strftime('%Y-%m-%d', datetime(created_at,'unixepoch','localtime')) AS d, "
      '  COALESCE(SUM(amount),0) AS total '
      'FROM expenses WHERE created_at >= ? AND created_at <= ? '
      'AND deleted_at IS NULL GROUP BY d',
      variables: [Variable.withInt(fromSec), Variable.withInt(toSec)],
      readsFrom: {expenses},
    ).get();

    DateTime parse(String s) {
      final p = s.split('-').map(int.parse).toList();
      return DateTime(p[0], p[1], p[2]);
    }

    final cashIn = <DateTime, int>{
      for (final r in inRows)
        parse(r.data['d'] as String): (r.data['net'] as num).toInt(),
    };
    final cashOut = <DateTime, int>{
      for (final r in outRows)
        parse(r.data['d'] as String): (r.data['total'] as num).toInt(),
    };
    final days = {...cashIn.keys, ...cashOut.keys}.toList()..sort();
    return [
      for (final d in days)
        (date: d, cashIn: cashIn[d] ?? 0, cashOut: cashOut[d] ?? 0),
    ];
  }

  /// Ringkasan arus kas satu rentang: kas masuk (dipecah tunai vs non-tunai)
  /// dan kas keluar (dari `expenses`, semua jenis — ini "ke mana uang
  /// mengalir", bukan P&L, jadi TIDAK memakai [netProfitExpenseTypes]).
  Future<CashFlowSummary> getCashFlowSummary(DateTime from, DateTime to) async {
    final byMethod = await getCashInByMethod(from, to);
    // 'tempo' = penanda nota berhutang, BUKAN uang yang berpindah. Kalau
    // pun muncul sbg method di baris pembayaran, nilainya tidak boleh
    // dianggap kas masuk.
    var cash = 0;
    var nonCash = 0;
    byMethod.forEach((method, net) {
      if (method == 'tempo') return;
      if (method == 'tunai') {
        cash += net;
      } else {
        nonCash += net;
      }
    });
    final outByType = await getExpenseBreakdownByType(from, to);
    final totalOut = outByType.values.fold<int>(0, (s, v) => s + v);
    return (
      cashIn: cash,
      nonCashIn: nonCash,
      cashOut: totalOut,
      outByType: outByType,
      inByMethod: byMethod,
    );
  }

  // ─────────── Statistik detail per produk / per pelanggan (drill-down) ───────────
  //
  // Permintaan user: tab Produk & Pelanggan di Laporan sebelumnya BUNTU
  // (barisnya tidak bisa diketuk). Query di bawah menyuplai layar detail
  // yang bisa dibuka dari sana + dari layar pelanggan. Semua menerima
  // rentang tanggal & memfilter `status != 'void'` — konsisten dgn
  // [getTopProductsByRevenue]/[getTopCustomersByRevenue] yang jadi
  // pintu masuknya, supaya angka ringkas & detail tidak pernah berbeda.

  /// Nama satuan DASAR sebuah produk (mis. "pcs"), fallback "satuan" kalau
  /// produk tak punya baris `product_units` sama sekali atau tak ada yang
  /// ditandai `isBaseUnit` (pakai satuan pertama sbg dasar, sama pola
  /// [stockBreakdownText]).
  Future<String> _baseUnitNameOf(String productId) async {
    final units = await (select(productUnits)
          ..where((t) => t.productId.equals(productId)))
        .get();
    if (units.isEmpty) return 'satuan';
    var base = units.first;
    for (final u in units) {
      if (u.isBaseUnit) {
        base = u;
        break;
      }
    }
    if (base.unitTypeId == null) return 'satuan';
    final type = await (select(unitTypes)
          ..where((t) => t.id.equals(base.unitTypeId!)))
        .getSingleOrNull();
    return type?.name ?? 'satuan';
  }

  /// Ringkasan satu produk dalam rentang: qty terjual, omzet, HPP, dan
  /// jumlah NOTA yang memuatnya (bukan jumlah baris — satu nota bisa punya
  /// beberapa baris produk yang sama dgn satuan berbeda).
  ///
  /// Item 63 (permintaan user) — `qtySold` dulu cuma `SUM(ti.qty)` MENTAH
  /// digabung lintas SEMUA satuan produk tanpa konversi (2 dus + 20 pcs
  /// tampil sbg "22", padahal 1 dus bisa = puluhan pcs) — menyesatkan utk
  /// produk yang dijual dlm >1 satuan. Fix: `qtySold` sekarang dikonversi
  /// ke satuan DASAR (`ti.qty * ratioToBase`, satuan dasar sendiri ratio
  /// 1.0), plus `unitBreakdown` mendaftar satuan NON-dasar yang ikut
  /// terjual (qty MENTAH apa adanya dlm satuan itu, bukan dikonversi) —
  /// dipakai UI utk keterangan "dari itu: 3 dus" di samping total.
  Future<ProductStatsSummary> getProductStatsSummary(
      String productId, DateTime from, DateTime to) async {
    final unitName = await _baseUnitNameOf(productId);
    const ratioExpr = 'CASE WHEN pu.is_base_unit = 1 '
        'OR pu.ratio_to_base IS NULL OR pu.ratio_to_base <= 0 '
        'THEN 1.0 ELSE pu.ratio_to_base END';
    final row = await customSelect(
      'SELECT COALESCE(SUM(ti.qty * $ratioExpr),0) AS qty, '
      '  COALESCE(SUM(ti.subtotal),0) AS revenue, '
      '  COALESCE(SUM(ti.cost_at_sale * ti.qty),0) AS cogs, '
      '  COUNT(DISTINCT ti.transaction_id) AS tx_count '
      'FROM transaction_items ti '
      'JOIN transactions t ON t.id = ti.transaction_id '
      'LEFT JOIN product_units pu ON pu.id = ti.product_unit_id '
      "WHERE ti.product_id = ? AND t.status != 'void' "
      'AND t.created_at >= ? AND t.created_at <= ?',
      variables: [
        Variable.withString(productId),
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {transactionItems, transactions, productUnits},
    ).getSingle();

    final breakdownRows = await customSelect(
      'SELECT ut.name AS unit_name, COALESCE(SUM(ti.qty),0) AS qty '
      'FROM transaction_items ti '
      'JOIN transactions t ON t.id = ti.transaction_id '
      'JOIN product_units pu ON pu.id = ti.product_unit_id '
      'LEFT JOIN unit_types ut ON ut.id = pu.unit_type_id '
      "WHERE ti.product_id = ? AND t.status != 'void' "
      'AND t.created_at >= ? AND t.created_at <= ? '
      'AND pu.is_base_unit = 0 '
      'GROUP BY pu.id ORDER BY qty DESC',
      variables: [
        Variable.withString(productId),
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {transactionItems, transactions, productUnits, unitTypes},
    ).get();

    return (
      qtySold: (row.data['qty'] as num).toDouble(),
      unitName: unitName,
      unitBreakdown: [
        for (final r in breakdownRows)
          (
            unitName: r.data['unit_name'] as String? ?? 'satuan',
            qty: (r.data['qty'] as num).toDouble(),
          ),
      ],
      revenue: (row.data['revenue'] as num).toInt(),
      cogs: (row.data['cogs'] as num).round(),
      txCount: (row.data['tx_count'] as num).toInt(),
    );
  }

  /// Tren harian satu produk (qty & omzet per tanggal LOKAL) — pola strftime
  /// sama [getExpenseDailyTotals]. `qty` dikonversi ke satuan dasar produk
  /// (lihat dok [getProductStatsSummary]) supaya garis tren tidak menjumlah
  /// mentah lintas satuan yang tidak sepadan.
  Future<List<ProductDailySales>> getProductDailySales(
      String productId, DateTime from, DateTime to) async {
    const ratioExpr = 'CASE WHEN pu.is_base_unit = 1 '
        'OR pu.ratio_to_base IS NULL OR pu.ratio_to_base <= 0 '
        'THEN 1.0 ELSE pu.ratio_to_base END';
    final rows = await customSelect(
      "SELECT strftime('%Y-%m-%d', datetime(t.created_at,'unixepoch','localtime')) AS d, "
      '  COALESCE(SUM(ti.qty * $ratioExpr),0) AS qty, '
      '  COALESCE(SUM(ti.subtotal),0) AS revenue '
      'FROM transaction_items ti '
      'JOIN transactions t ON t.id = ti.transaction_id '
      'LEFT JOIN product_units pu ON pu.id = ti.product_unit_id '
      "WHERE ti.product_id = ? AND t.status != 'void' "
      'AND t.created_at >= ? AND t.created_at <= ? '
      'GROUP BY d ORDER BY d',
      variables: [
        Variable.withString(productId),
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {transactionItems, transactions, productUnits},
    ).get();
    return rows.map((r) {
      final p = (r.data['d'] as String).split('-').map(int.parse).toList();
      return (
        date: DateTime(p[0], p[1], p[2]),
        qty: (r.data['qty'] as num).toDouble(),
        revenue: (r.data['revenue'] as num).toInt(),
      );
    }).toList();
  }

  /// Pembeli teratas satu produk. HANYA pelanggan TERDAFTAR (`customer_id`
  /// tidak null) — keputusan user: pembeli umum/ad-hoc diabaikan, karena
  /// nota begitu cuma menyimpan nama bebas yang tidak bisa dijamin merujuk
  /// orang yang sama.
  Future<List<ProductBuyerStat>> getProductTopBuyers(
      String productId, DateTime from, DateTime to,
      {int limit = 20}) async {
    final rows = await customSelect(
      'SELECT c.id AS cid, c.name AS cname, '
      '  COALESCE(SUM(ti.qty),0) AS qty, COALESCE(SUM(ti.subtotal),0) AS revenue '
      'FROM transaction_items ti '
      'JOIN transactions t ON t.id = ti.transaction_id '
      'JOIN customers c ON c.id = t.customer_id '
      "WHERE ti.product_id = ? AND t.status != 'void' "
      'AND t.created_at >= ? AND t.created_at <= ? '
      'GROUP BY c.id ORDER BY revenue DESC LIMIT $limit',
      variables: [
        Variable.withString(productId),
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {transactionItems, transactions, customers},
    ).get();
    return rows
        .map((r) => (
              customerId: r.data['cid'] as String,
              name: r.data['cname'] as String,
              qty: (r.data['qty'] as num).toDouble(),
              revenue: (r.data['revenue'] as num).toInt(),
            ))
        .toList();
  }

  /// Ringkasan belanja satu pelanggan dalam rentang. `totalSpent` dari
  /// `transactions.total` (nilai nota), BUKAN `paid` — nota tempo yang belum
  /// dibayar TETAP dihitung sbg belanja, konsisten dgn
  /// [getTopCustomersByRevenue] yang jadi pintu masuknya.
  Future<CustomerStatsSummary> getCustomerStatsSummary(
      String customerId, DateTime from, DateTime to) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(t.total),0) AS spent, COUNT(*) AS tx_count, '
      '  COALESCE(SUM((SELECT COALESCE(SUM(ti.qty),0) FROM transaction_items ti '
      '     WHERE ti.transaction_id = t.id)),0) AS item_qty '
      "FROM transactions t WHERE t.customer_id = ? AND t.status != 'void' "
      'AND t.created_at >= ? AND t.created_at <= ?',
      variables: [
        Variable.withString(customerId),
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {transactions, transactionItems},
    ).getSingle();
    final txCount = (row.data['tx_count'] as num).toInt();
    final spent = (row.data['spent'] as num).toInt();
    return (
      totalSpent: spent,
      txCount: txCount,
      itemQty: (row.data['item_qty'] as num).toDouble(),
      avgPerTx: txCount == 0 ? 0 : (spent / txCount).round(),
    );
  }

  /// Produk yang paling sering/banyak dibeli satu pelanggan dalam rentang.
  Future<List<ProductRevenueStat>> getCustomerTopProducts(
      String customerId, DateTime from, DateTime to,
      {int limit = 20}) async {
    final rows = await customSelect(
      'SELECT p.id AS pid, p.name AS pname, '
      '  COALESCE(SUM(ti.qty),0) AS qty, COALESCE(SUM(ti.subtotal),0) AS revenue, '
      '  COALESCE(SUM(ti.cost_at_sale * ti.qty),0) AS cogs '
      'FROM transaction_items ti '
      'JOIN transactions t ON t.id = ti.transaction_id '
      'JOIN products p ON p.id = ti.product_id '
      "WHERE t.customer_id = ? AND t.status != 'void' "
      'AND t.created_at >= ? AND t.created_at <= ? '
      'GROUP BY p.id ORDER BY revenue DESC LIMIT $limit',
      variables: [
        Variable.withString(customerId),
        Variable.withInt(from.millisecondsSinceEpoch ~/ 1000),
        Variable.withInt(to.millisecondsSinceEpoch ~/ 1000),
      ],
      readsFrom: {transactionItems, transactions, products},
    ).get();
    return rows
        .map((r) => ProductRevenueStat(
              productId: r.data['pid'] as String,
              name: r.data['pname'] as String,
              revenue: (r.data['revenue'] as num).toInt(),
              qtySold: (r.data['qty'] as num).toDouble(),
              cogs: (r.data['cogs'] as num).round(),
            ))
        .toList();
  }

  /// Daftar nota satu pelanggan dalam rentang (terbaru dulu) — dipakai
  /// layar statistik pelanggan supaya bisa langsung dibuka ke struknya.
  Future<List<Transaction>> getCustomerTransactions(
          String customerId, DateTime from, DateTime to,
          {int limit = 200}) =>
      (select(transactions)
            ..where((t) =>
                t.customerId.equals(customerId) &
                t.status.isNotValue('void') &
                t.createdAt.isBiggerOrEqualValue(from) &
                t.createdAt.isSmallerOrEqualValue(to))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .get();

  /// Total ringkas laporan (revenue, COGS, jumlah transaksi) dalam rentang —
  /// query agregat satu-baris, tidak memuat seluruh transaksi/item ke memori
  /// (mencegah Out of Memory saat ekspor periode besar).
  Future<({int revenue, int cogs, int txCount})> getReportTotals(
      DateTime from, DateTime to) async {
    final revenueExpr = transactions.total.sum();
    final countExpr = transactions.id.count();
    final headRow = await (selectOnly(transactions)
          ..addColumns([revenueExpr, countExpr])
          ..where(transactions.status.isNotValue('void') &
              transactions.createdAt.isBiggerOrEqualValue(from) &
              transactions.createdAt.isSmallerOrEqualValue(to)))
        .getSingle();

    const cogsExpr = CustomExpression<double>(
        'SUM(transaction_items.cost_at_sale * transaction_items.qty)');
    final cogsRow = await (select(transactionItems).join([
      innerJoin(transactions,
          transactions.id.equalsExp(transactionItems.transactionId)),
    ])
          ..addColumns([cogsExpr])
          ..where(transactions.status.isNotValue('void') &
              transactions.createdAt.isBiggerOrEqualValue(from) &
              transactions.createdAt.isSmallerOrEqualValue(to)))
        .getSingle();

    return (
      revenue: headRow.read(revenueExpr) ?? 0,
      cogs: (cogsRow.read(cogsExpr) ?? 0).round(),
      txCount: headRow.read(countExpr) ?? 0,
    );
  }

  // ───────────────────────── Laporan queries ─────────────────────────

  /// `includeVoid: false` (default) menjaga perilaku LAMA — transaksi void
  /// dikecualikan, SEMUA pemanggil existing (ekspor, dll) tidak berubah.
  /// `includeVoid: true` dipakai Laporan → Transaksi (Item 63) supaya nota
  /// void tetap terlihat (badge VOID di `_TxTile` yang sudah ada).
  Stream<List<Transaction>> watchTransactions({
    required DateTime from,
    required DateTime to,
    bool includeVoid = false,
  }) =>
      (select(transactions)
            ..where((t) =>
                (includeVoid ? const Constant(true) : t.status.isNotValue('void')) &
                t.createdAt.isBiggerOrEqualValue(from) &
                t.createdAt.isSmallerOrEqualValue(to))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  /// Transaksi dalam rentang (sekali ambil, dibatasi) untuk ekspor laporan —
  /// terbaru dulu. Batas mencegah Out of Memory pada periode besar.
  Future<List<Transaction>> getTransactionsInRange(
    DateTime from,
    DateTime to, {
    int limit = 2000,
  }) =>
      (select(transactions)
            ..where((t) =>
                t.status.isNotValue('void') &
                t.createdAt.isBiggerOrEqualValue(from) &
                t.createdAt.isSmallerOrEqualValue(to))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .get();

  Future<List<Customer>> searchCustomers(String q) {
    final query = (select(customers)..where((t) => t.isActive.equals(true)));
    if (q.isNotEmpty) {
      query.where((t) => t.name.lower().contains(q.toLowerCase()));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.get();
  }

  /// Peta id→nama SEMUA pelanggan, TERMASUK yang sudah di-soft-delete
  /// (`isActive=false`). Beda dari `searchCustomers()` (khusus daftar aktif
  /// utk dropdown/autocomplete pilih pelanggan) — dipakai utk label riwayat
  /// transaksi HISTORIS, yang menurut desain `deactivateCustomer()` memang
  /// harus tetap tampil nama aslinya walau pelanggannya sudah dihapus. Bug
  /// dilaporkan user: transaksi lama nyangkut nama generik "Pelanggan"
  /// begitu pelanggannya dihapus, krn kode lama pakai `searchCustomers('')`
  /// yang diam-diam menyaring `isActive=true` saja.
  Future<Map<String, String>> getAllCustomerNamesIncludingInactive() async {
    final rows = await select(customers).get();
    return {for (final c in rows) c.id: c.name};
  }

  Stream<List<Customer>> watchCustomers({String query = ''}) {
    final q = (select(customers)..where((t) => t.isActive.equals(true)));
    if (query.isNotEmpty) {
      q.where((t) => t.name.lower().contains(query.toLowerCase()));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
  }

  // ───────────────────────── Pegawai toko ─────────────────────────

  /// Daftar pegawai aktif, diurut nama. Dipakai di picker pembayaran & struk.
  Future<List<Employee>> getEmployees({bool activeOnly = true}) {
    final q = select(employees);
    if (activeOnly) q.where((t) => t.isActive.equals(true));
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.get();
  }

  Stream<List<Employee>> watchEmployees({bool activeOnly = true}) {
    final q = select(employees);
    if (activeOnly) q.where((t) => t.isActive.equals(true));
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
  }

  Future<void> upsertEmployee(EmployeesCompanion entry) =>
      into(employees).insertOnConflictUpdate(entry);

  /// Hapus pegawai dari master. Nota lama tetap menyimpan snapshot nama,
  /// sehingga riwayat "siapa yang melayani" tidak hilang.
  Future<void> deleteEmployee(String id) =>
      (delete(employees)..where((t) => t.id.equals(id))).go();

  /// Soft-delete pelanggan (set isActive=false). Transaksi & riwayat historis
  /// tetap utuh karena hanya menyembunyikan dari daftar aktif.
  Future<void> deactivateCustomer(String id) =>
      (update(customers)..where((t) => t.id.equals(id))).write(
        CustomersCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );

  // ───────────────────────── Held orders ─────────────────────────

  Stream<List<HeldOrder>> watchHeldOrders() =>
      (select(heldOrders)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<void> holdOrder({
    required String id,
    required String label,
    required String cartJson,
  }) =>
      into(heldOrders).insert(HeldOrdersCompanion.insert(
        id: id,
        label: label,
        cartJson: cartJson,
      ));

  Future<void> deleteHeldOrder(String id) =>
      (delete(heldOrders)..where((t) => t.id.equals(id))).go();

  /// Item 24b — update payload pesanan ditahan (dipakai buat persist
  /// centangan verifikasi tanpa ganti id/createdAt-nya).
  Future<void> updateHeldOrder(String id, String cartJson) =>
      (update(heldOrders)..where((t) => t.id.equals(id)))
          .write(HeldOrdersCompanion(cartJson: Value(cartJson)));

  // ───────────────────────── Sync upload queue (Item 17 Fase 2) ─────────

  /// Antrian approval sync sisi HOST, sekarang PERSISTEN — dulu
  /// `_pendingQueue` di `LanSyncService` cuma hidup di RAM, hilang total
  /// kalau app owner di-restart sebelum sempat approve. "1 slot per
  /// PENGIRIM" dipertahankan (hapus entri lama dari pengirim yang sama
  /// SEBELUM insert baru, dalam satu transaksi) — aman krn klien selalu
  /// kirim data superset dari upload sebelumnya (lihat dok watermark upload
  /// di lan_sync_service.dart).
  ///
  /// Bug nyata dilaporkan user (sama persis dgn `_pendingProposals` yang
  /// sudah diperbaiki 25 Juli): slot dulu dikunci `fromIp` MENTAH — dua
  /// device BERBEDA yang kebetulan tersambung dari alamat IP yang SAMA
  /// (hotspot HP dgn pool DHCP kecil, setup umum toko kecil) saling
  /// menimpa antrian satu sama lain sebelum owner sempat approve. Kunci
  /// slot sekarang preferensi [deviceCode] (dikirim klien via
  /// `syncToHost`), fallback ke [fromIp] kalau klien lama belum kirim itu.
  ///
  /// Susulan (bug KRITIS lain, dilaporkan lewat audit sesi ini): DELETE+
  /// INSERT ini SENGAJA masih menimpa isi slot lama, TAPI [tablesJson] yang
  /// dioper ke sini WAJIB SUDAH di-gabung (union) oleh pemanggil
  /// (`LanSyncService._handleRequest`, lihat `_unionSyncTables`) dgn isi
  /// slot lama kalau ada — BUKAN payload delta mentah dari klien. Dulu
  /// asumsinya "payload klien per-sync selalu superset dari watermark
  /// upload klien" — TERBUKTI SALAH sejak watermark upload dimajukan
  /// begitu HTTP 200 diterima (Item 17 Fase 2), BUKAN setelah owner
  /// approve: sync kedua yang menyusul cepat (kebiasaan umum kasir tap
  /// sync 2x, atau sync otomatis) cuma bawa DELTA kecil/kosong, dan tanpa
  /// union, slot lama yang bisa berisi puluhan transaksi BELUM di-approve
  /// hilang permanen tanpa jejak — cuma bisa pulih via "Sync Ulang Penuh"
  /// manual yang tidak ada yang tahu harus dipakai.
  Future<void> enqueueSyncUpload({
    required String id,
    required String fromIp,
    String? deviceCode,
    required String tablesJson,
    required DateTime since,
    required String tablesSummary,
  }) =>
      transaction(() async {
        final slotKey =
            (deviceCode != null && deviceCode.isNotEmpty) ? deviceCode : fromIp;
        await (delete(syncUploadQueue)
              ..where((t) => (deviceCode != null && deviceCode.isNotEmpty
                  ? t.deviceCode.equals(slotKey)
                  : t.fromIp.equals(slotKey) & t.deviceCode.isNull())))
            .go();
        await into(syncUploadQueue).insert(SyncUploadQueueCompanion.insert(
          id: id,
          fromIp: fromIp,
          deviceCode: Value(deviceCode),
          tablesJson: tablesJson,
          since: since,
          tablesSummary: tablesSummary,
        ));
      });

  Future<List<SyncUploadQueueData>> listSyncUploadQueue() =>
      (select(syncUploadQueue)..orderBy([(t) => OrderingTerm.asc(t.arrivedAt)]))
          .get();

  /// Cari item antrian upload yang MASIH menunggu approve owner utk slot
  /// pengirim ini (kunci sama persis dgn `enqueueSyncUpload`) — dipakai
  /// `LanSyncService._handleRequest` utk GABUNGKAN (union) payload baru dgn
  /// yang lama, bukan menimpanya. Lihat dok panjang di `enqueueSyncUpload`.
  Future<SyncUploadQueueData?> getSyncUploadQueueItemForSlot({
    required String fromIp,
    String? deviceCode,
  }) =>
      (select(syncUploadQueue)
            ..where((t) => (deviceCode != null && deviceCode.isNotEmpty
                ? t.deviceCode.equals(deviceCode)
                : t.fromIp.equals(fromIp) & t.deviceCode.isNull())))
          .getSingleOrNull();

  Future<SyncUploadQueueData?> getSyncUploadQueueItem(String id) =>
      (select(syncUploadQueue)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Dipanggil setelah approve ATAU reject — baik disetujui maupun ditolak,
  /// item ini selesai diproses & tidak perlu tersimpan lagi (lihat dok
  /// "tolak = permanen" di lan_sync_service.dart).
  Future<void> deleteSyncUploadQueueItem(String id) =>
      (delete(syncUploadQueue)..where((t) => t.id.equals(id))).go();

  // ───────────────────────── Backup / Restore ─────────────────────────

  // Bug nyata dilaporkan user: restore gagal total dgn "FOREIGN KEY
  // constraint failed ... DELETE FROM product_groups" utk toko mana pun yg
  // pernah pakai kategori-tambahan (Item 54). Akar masalah: `product_groups`
  // (skema Drift, `@DriftDatabase` di atas) ditambah setelahnya TAPI daftar
  // ini (dipakai backup DAN restore) lupa diperbarui — baris lama di
  // `product_group_tags` tidak pernah ikut dihapus di awal restore krn
  // tabelnya tidak ada di daftar ini, jadi masih menunjuk ke `product_groups`
  // lama saat `DELETE FROM "product_groups"` dijalankan → SQLite menolak.
  // Sekalian dampak lain yg SAMA (tapi diam-diam, tanpa error krn tabelnya
  // sendiri tanpa FK): `reserved_order_numbers` (Item 55) juga tidak pernah
  // ikut ter-backup/restore. `product_group_tags` WAJIB disebut SETELAH
  // `products` & `product_groups` (FK ke keduanya) — urutan list ini dipakai
  // apa adanya utk INSERT (parent dulu) & REVERSED utk DELETE (anak dulu).
  // `sync_upload_queue` SENGAJA TIDAK dimasukkan — itu antrian approval host
  // yang sifatnya transient/proses-saat-ini, bukan data bisnis; me-restore
  // antrian lama dari backup lama tidak masuk akal (bisa duplikat/konflik
  // dgn antrian yg sedang berjalan).
  static const _allTables = [
    'app_settings',
    'products',
    'product_groups',
    'product_group_tags',
    'unit_types',
    'product_units',
    'product_barcodes',
    'price_tiers',
    'alt_prices',
    'customer_groups',
    'customer_group_prices',
    'customers',
    'transactions',
    'transaction_items',
    'transaction_payments',
    // Rincian per-produk retur/edit (lihat dok `TransactionAdjustmentLines`)
    // — ditaruh SETELAH `transaction_payments` (FK logis ke `paymentId`,
    // walau bukan FK fisik Drift) supaya urutan insert (parent dulu) benar.
    'transaction_adjustment_lines',
    // Item 52 "Laci Meja" (susulan fix 28 Juli): 3 tabel ini SEBELUMNYA
    // terlewat di list ini — sync LAN (`dumpSince`/`dumpLaciMejaProposals`)
    // sudah benar menyertakannya sejak awal, tapi backup penuh/Alihkan Owner
    // (`dumpAllTables`/`restoreFromDump`, dipakai `DbExportService`) diam-diam
    // TIDAK membawa serta catatan titip/ketinggalan, pinjaman belum kembali,
    // & pre-order belum terpenuhi. Ditaruh SETELAH `transactions`/`customers`
    // (parent-nya via FK) supaya urutan delete (reversed list, children dulu)
    // & insert (forward, parent dulu) tetap benar.
    'left_behind_items',
    'borrowed_items',
    'preorder_entries',
    // Log kejadian Laci Meja (PLAN.md Item 54) — SETELAH ketiga tabel di atas
    // (induknya via `entry_id`, walau bukan FK fisik) supaya urutan insert
    // tetap parent-dulu.
    'laci_meja_events',
    // Kamus belajar penerimaan barang — ikut backup/Alihkan Owner supaya
    // pemetaan yang sudah dipelajari tidak hilang saat pindah device.
    'product_aliases',
    'held_orders',
    'reserved_order_numbers',
    'stock_ledger',
    'expenses',
    'loyalty_point_ledger',
    'suppliers',
    'purchases',
    'purchase_items',
    'kasir_permissions',
    'payment_methods',
    'daily_summaries',
    'employees',
    'cash_closings',
  ];

  Future<Map<String, List<Map<String, Object?>>>> dumpAllTables() async {
    final dump = <String, List<Map<String, Object?>>>{};
    for (final name in _allTables) {
      final rows = await customSelect('SELECT * FROM "$name"').get();
      dump[name] = rows.map((r) => r.data).toList();
    }
    return dump;
  }

  Future<void> restoreFromDump(
      Map<String, List<Map<String, Object?>>> dump) async {
    // customStatement/customInsert lewat raw SQL tidak diketahui Drift tabel
    // mana yang berubah, jadi StreamProvider (mis. daftar produk/pelanggan)
    // yang bergantung pada .watch() TIDAK auto-refresh walau data sungguhan
    // sudah ganti total — restore terlihat "tidak berdampak" di UI padahal DB
    // sudah benar. Param `updates:` memberi tahu Drift tabel yang terpengaruh.
    final tablesByName = {for (final t in allTables) t.entityName: t};
    await transaction(() async {
      // Delete children before parents to avoid FK violations.
      for (final tableName in _allTables.reversed) {
        final table = tablesByName[tableName];
        await customUpdate('DELETE FROM "$tableName"',
            updates: table == null ? null : {table},
            updateKind: UpdateKind.delete);
      }
      // Insert in forward (parent-first) order.
      for (final tableName in _allTables) {
        final table = tablesByName[tableName];
        final rows = dump[tableName] ?? [];
        for (final row in rows) {
          if (row.isEmpty) continue;
          final cols = row.keys.map((k) => '"$k"').join(', ');
          final placeholders = row.values.map((_) => '?').join(', ');
          final variables = _rowToVars(row);
          await customInsert(
            'INSERT OR REPLACE INTO "$tableName" ($cols) VALUES ($placeholders)',
            variables: variables,
            updates: table == null ? null : {table},
          );
        }
      }
    });
  }

  /// Rekey fisik file SQLCipher ke [newKeyHex] (hex 64-char, hasil
  /// `deriveDatabaseKey`). Dipakai "Alihkan Owner" (Item 27) saat device yang
  /// SUDAH ada datanya menerima transfer identitas toko lain — koneksi ini
  /// dibuka dgn key LAMA, tapi identitas device (storeKey) akan diganti ke
  /// yang BARU setelah ini. Tanpa rekey, file fisik tetap terenkripsi dgn key
  /// lama sementara device "mengira" key-nya sudah baru — app tidak akan bisa
  /// membuka DB lagi sama sekali setelah restart (deadlock, tidak ada jalan
  /// pulih tanpa key lama). WAJIB dipanggil SEBELUM identitas device diganti,
  /// dgn koneksi yang MASIH pakai key lama (`PRAGMA rekey` butuh DB yg sudah
  /// terbuka dgn key yang benar).
  Future<void> rekey(String newKeyHex) async {
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(newKeyHex)) {
      throw ArgumentError(
          'Encryption key harus hex murni; nilai tidak valid ditolak.');
    }
    await customStatement("PRAGMA rekey = '$newKeyHex';");
  }

  // ───────────────────────── Sync helpers ─────────────────────────

  /// Dump only syncable rows since [since] for WiFi sync.
  ///
  /// [includeMasterData] mengontrol arah data master (produk, harga, barcode,
  /// pelanggan, izin kasir). Master data hanya boleh mengalir SATU ARAH dari
  /// host (owner) ke perangkat bawahan. Maka:
  ///   • Host mengirim ke bawah  → includeMasterData = true (default).
  ///   • Klien mengirim ke atas  → includeMasterData = false, supaya perubahan
  ///     harga di perangkat asisten/kasir TIDAK menimpa data owner.
  /// Data append-only (transaksi, stok, pembayaran, dll) selalu ikut.
  Future<Map<String, List<Map<String, Object?>>>> dumpSince(DateTime since,
      {bool includeMasterData = true}) async {
    const appendOnly = [
      'transactions',
      'transaction_items',
      'transaction_payments',
      'transaction_adjustment_lines',
      'stock_ledger',
      'loyalty_point_ledger',
      'expenses',
    ];
    const masterData = [
      'products',
      // Bug nyata dilaporkan user: kategori (create/rename/delete/reorder
      // KATEGORI ITU SENDIRI, beda dari penugasan produk ke kategori yang
      // sudah benar via `products.productGroupId`/`product_group_tags`)
      // tidak pernah tersinkron ke klien sama sekali — `product_groups`
      // lupa dimasukkan ke daftar ini sejak awal. Full-dump tiap sync
      // (tidak ada kolom `updated_at` di tabel ini) sudah AMAN krn baris
      // kategori tidak pernah benar² dihapus — `deleteProductGroup`
      // menombstone `name=null` (slot id dipakai ulang), bukan DELETE baris,
      // jadi INSERT OR REPLACE polos (tanpa cleanup orphan spt
      // `product_group_tags`) sudah cukup merefleksikan state kategori host
      // ke klien apa adanya.
      'product_groups',
      'product_units',
      'price_tiers',
      'alt_prices',
      'product_barcodes',
      'product_group_tags',
      'customers',
      'customer_groups',
      'customer_group_prices',
      // Item 52 ("Laci Meja") — auto-merge host->klien, pola sama persis
      // spt products/customers (delta by updated_at, bukan full-dump: bisa
      // menumpuk banyak baris seiring waktu, beda dari price_tiers dkk).
      'left_behind_items',
      'borrowed_items',
      'preorder_entries',
      // Log kejadian Laci Meja (PLAN.md Item 54) — append-only BENTUKNYA
      // (baris tidak pernah di-update), tapi jalur sync-nya sengaja ikut
      // master data + antrian persetujuan owner spt 3 tabel induknya, BUKAN
      // auto-merge klien->host ala `appendOnly`. Delta-nya by `created_at`
      // saja krn tabel ini memang tidak punya `updated_at`.
      'laci_meja_events',
      // Metode bayar & pegawai: master data owner yang selama ini TIDAK
      // pernah menyebar — owner menambah rekening/QRIS atau pegawai baru,
      // device kasir tidak pernah mendapatkannya.
      'payment_methods',
      'employees',
    ];
    // Tabel yang mengalir DUA ARAH (klien->host maupun host->klien),
    // last-write-wins by `updated_at`. Beda dari [masterData] yang sengaja
    // satu arah (host = sumber kebenaran) DAN dari [appendOnly] yang tidak
    // pernah meng-update baris yang sudah ada. Kamus penerimaan barang
    // masuk sini atas permintaan user: pemetaan teks->produk yang
    // dipelajari device kasir HARUS ikut sampai ke owner, bukan cuma
    // sebaliknya. Lihat juga `LanSyncService.sharedTables`.
    const shared = ['product_aliases'];

    final dump = <String, List<Map<String, Object?>>>{};
    // Drift stores DateTimeColumn as unix seconds; raw SQL must compare in the same unit.
    final sinceSec = since.millisecondsSinceEpoch ~/ 1000;

    for (final t in appendOnly) {
      // Tidak semua tabel append-only punya kolom `created_at`:
      //  • transaction_items  → tanpa timestamp; ikut waktu transaksi induk.
      //  • transaction_payments→ pakai `paid_at` (cicilan bisa masuk belakangan).
      //  • sisanya             → `created_at`.
      final String sql;
      var varCount = 1;
      switch (t) {
        case 'transactions':
          // Item 62 — nota bukan append-only murni: `status` (void),
          // `customer_name`/`customer_id`, `points_earned` bisa berubah
          // SETELAH nota pertama kali tersinkron (lihat dok kolom
          // `updated_at`) — tanpa OR ini, perubahan itu tidak pernah
          // ke-dump lagi begitu `created_at`-nya sudah lewat watermark.
          sql = 'SELECT * FROM "transactions" WHERE created_at >= ? '
              'OR updated_at >= ?';
          varCount = 2;
        case 'transaction_items':
          // Item susulan (fitur tambah belanjaan) bisa menempel pada transaksi
          // lama — ikutkan juga berdasarkan added_at agar tidak tertinggal.
          sql = 'SELECT * FROM "transaction_items" WHERE transaction_id IN '
              '(SELECT id FROM "transactions" WHERE created_at >= ?) '
              'OR added_at >= ?';
          varCount = 2;
        case 'transaction_payments':
          sql = 'SELECT * FROM "transaction_payments" WHERE paid_at >= ?';
        case 'expenses':
          // Item 61.5 — soft-delete (`deleted_at`) ditulis via UPDATE,
          // TIDAK mengubah `created_at` — tanpa OR ini, baris yang baru
          // dihapus tidak akan pernah ikut re-dump, penghapusannya tidak
          // pernah sampai ke device lain (persis bug Item 57 tapi utk
          // delete, bukan pelunasan/item susulan).
          sql = 'SELECT * FROM "expenses" WHERE created_at >= ? '
              'OR deleted_at >= ?';
          varCount = 2;
        default:
          sql = 'SELECT * FROM "$t" WHERE created_at >= ?';
      }
      final rows = await customSelect(
        sql,
        variables: [
          for (var i = 0; i < varCount; i++) Variable.withInt(sinceSec)
        ],
      ).get();
      dump[t] = rows.map((r) => r.data).toList();
    }
    // Master data & izin kasir hanya disertakan saat mengalir ke bawah (host
    // → bawahan). Saat klien mengirim ke atas, dilewati agar tidak menimpa.
    // Susulan (permintaan user) — atribut Laci Meja (titip/pinjaman/
    // pre-order) milik transaksi yang SUDAH di-void tidak boleh ikut
    // tersinkron ke host: kewajibannya sudah tidak relevan lagi begitu
    // nota induknya dibatalkan. `voidTransaction` SENGAJA tidak menghapus
    // baris-baris ini secara lokal (jejak audit tetap ada, pola soft-delete
    // yang konsisten di seluruh app) — jadi filternya di SINI, di titik
    // keluarnya data, bukan dengan menghapus data lokal. Baris dgn
    // `transaction_id` NULL (mis. titip wadah tanpa membeli apa pun) tetap
    // lolos apa adanya, tidak pernah terkait transaksi jadi tidak mungkin
    // "void". TIDAK menutup celah data yg SUDAH kadung tersinkron SEBELUM
    // notanya di-void (di luar cakupan — laci-meja belum punya mekanisme
    // retract/tombstone).
    const excludeVoidTx = 'AND (transaction_id IS NULL OR transaction_id '
        "NOT IN (SELECT id FROM transactions WHERE status = 'void'))";
    if (includeMasterData) {
      for (final t in masterData) {
        final laciMejaWithTx = t == 'left_behind_items' ||
            t == 'borrowed_items' ||
            t == 'preorder_entries';
        final hasUpdated = t == 'products' ||
            t == 'customers' ||
            laciMejaWithTx ||
            t == 'employees';
        if (laciMejaWithTx) {
          final rows = await customSelect(
            'SELECT * FROM "$t" WHERE (updated_at >= ? OR created_at >= ?) '
            '$excludeVoidTx',
            variables: [Variable.withInt(sinceSec), Variable.withInt(sinceSec)],
          ).get();
          dump[t] = rows.map((r) => r.data).toList();
        } else if (hasUpdated) {
          final rows = await customSelect(
            'SELECT * FROM "$t" WHERE updated_at >= ? OR created_at >= ?',
            variables: [Variable.withInt(sinceSec), Variable.withInt(sinceSec)],
          ).get();
          dump[t] = rows.map((r) => r.data).toList();
        } else if (t == 'laci_meja_events') {
          // Baris log tidak pernah di-update, jadi `created_at` (waktu
          // kejadian fisik) sendiri sudah cukup jadi delta UNTUK EVENT YANG
          // BELUM PERNAH DIUSULKAN — full-dump TIDAK boleh dipakai di sini
          // (tabel ini tumbuh terus seiring waktu, beda dari price_tiers dkk
          // yang ukurannya terikat jumlah produk). TAPI event yang klien
          // buat SEBELUM watermark sync berikutnya, lalu baru disetujui host
          // SETELAHNYA, tidak akan pernah lolos filter `created_at` itu lagi
          // — `locally_modified` klien nyangkut selamanya & payload usulan
          // tumbuh tanpa akhir (Item 57). `applied_at` (dicap host saat
          // `applyLaciMejaProposals` menyetujui) jadi filter TAMBAHAN supaya
          // event yang baru disetujui dijamin ikut, kapan pun disetujuinya.
          // `entryId` polimorfik (dok di atas) — kecualikan baris yang entri
          // induknya (di salah satu dari 3 tabel sesuai `entityType`)
          // barusan ikut dikecualikan di atas krn milik transaksi void,
          // supaya log tidak jadi yatim menunjuk entri yang tidak pernah
          // sampai ke host.
          final rows = await customSelect(
            'SELECT * FROM "$t" WHERE (created_at >= ? OR applied_at >= ?) '
            'AND NOT ('
            "(entity_type = 'titip' AND entry_id IN "
            '(SELECT id FROM left_behind_items WHERE transaction_id IN '
            "(SELECT id FROM transactions WHERE status = 'void'))) OR "
            "(entity_type = 'pinjaman' AND entry_id IN "
            '(SELECT id FROM borrowed_items WHERE transaction_id IN '
            "(SELECT id FROM transactions WHERE status = 'void'))) OR "
            "(entity_type = 'preorder' AND entry_id IN "
            '(SELECT id FROM preorder_entries WHERE transaction_id IN '
            "(SELECT id FROM transactions WHERE status = 'void')))"
            ')',
            variables: [
              Variable.withInt(sinceSec),
              Variable.withInt(sinceSec),
            ],
          ).get();
          dump[t] = rows.map((r) => r.data).toList();
        } else {
          final rows = await customSelect('SELECT * FROM "$t"').get();
          dump[t] = rows.map((r) => r.data).toList();
        }
      }
      // kasir_permissions — hanya punya updated_at (tanpa created_at).
      // Ikut tersinkron agar perubahan izin dari owner langsung berlaku di
      // HP kasir/asisten.
      final rows = await customSelect(
        'SELECT * FROM "kasir_permissions" WHERE updated_at >= ?',
        variables: [Variable.withInt(sinceSec)],
      ).get();
      dump['kasir_permissions'] = rows.map((r) => r.data).toList();

      // Setting toko — HANYA key di [syncableSettingKeys]. Lihat dok di
      // sana kenapa tabel ini tidak boleh di-dump bulat-bulat.
      final keyPlaceholders =
          List.filled(syncableSettingKeys.length, '?').join(',');
      final settingRows = await customSelect(
        'SELECT * FROM "app_settings" WHERE updated_at >= ? '
        'AND key IN ($keyPlaceholders)',
        variables: [
          Variable.withInt(sinceSec),
          for (final k in syncableSettingKeys) Variable.withString(k),
        ],
      ).get();
      dump['app_settings'] = settingRows.map((r) => r.data).toList();
    }
    // SELALU disertakan — termasuk saat klien mengirim ke atas
    // (`includeMasterData: false`), justru itu tujuannya.
    for (final t in shared) {
      final rows = await customSelect(
        'SELECT * FROM "$t" WHERE updated_at >= ? OR created_at >= ?',
        variables: [Variable.withInt(sinceSec), Variable.withInt(sinceSec)],
      ).get();
      dump[t] = rows.map((r) => r.data).toList();
    }
    return dump;
  }

  /// Set produk sbg "diedit lokal" (Item 40 — usulan harga/produk dari
  /// device non-owner). Dipanggil UI setelah simpan produk/varian/harga di
  /// device yang BUKAN owner. TIDAK pernah dipanggil dari device owner
  /// (owner adalah sumber kebenaran, tidak perlu mengusulkan ke diri
  /// sendiri) — pemanggil (UI) yang jaga itu via `device.isOwner`.
  Future<void> markProductLocallyModified(String productId) async {
    await (update(products)..where((t) => t.id.equals(productId))).write(
      ProductsCompanion(
        locallyModified: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Kumpulkan seluruh baris (produk + satuan + tier harga + harga
  /// alternatif + barcode) utk produk yang ditandai `locallyModified` di
  /// device ini — dikirim sbg "usulan harga/produk" ke owner via sync
  /// (Item 40). BEDA dari [dumpSince]: bukan delta by-timestamp, tapi
  /// SEMUA baris terkait produk yang ditandai, supaya owner terima paket
  /// utuh (produk baru dgn banyak satuan/varian/harga tidak "kepotong").
  /// TIDAK menghapus flag di sini — flag baru hilang otomatis saat baris
  /// ini ditimpa push resmi dari host (lihat dok kolom `locallyModified`).
  Future<Map<String, List<Map<String, Object?>>>> dumpLocalProposals() async {
    final productRows = await customSelect(
      'SELECT * FROM "products" WHERE locally_modified = 1',
    ).get();
    if (productRows.isEmpty) return {};

    final productIds = productRows.map((r) => r.data['id'] as String).toList();
    final placeholders = List.filled(productIds.length, '?').join(', ');
    final vars = [for (final id in productIds) Variable.withString(id)];

    final unitRows = await customSelect(
      'SELECT * FROM "product_units" WHERE product_id IN ($placeholders)',
      variables: vars,
    ).get();
    final unitIds = unitRows.map((r) => r.data['id'] as String).toList();

    Future<List<Map<String, Object?>>> byUnitIds(String table) async {
      if (unitIds.isEmpty) return [];
      final ph = List.filled(unitIds.length, '?').join(', ');
      final rows = await customSelect(
        'SELECT * FROM "$table" WHERE product_unit_id IN ($ph)',
        variables: [for (final id in unitIds) Variable.withString(id)],
      ).get();
      return rows.map((r) => r.data).toList();
    }

    return {
      'products': productRows.map((r) => r.data).toList(),
      'product_units': unitRows.map((r) => r.data).toList(),
      'price_tiers': await byUnitIds('price_tiers'),
      'alt_prices': await byUnitIds('alt_prices'),
      'product_barcodes': await byUnitIds('product_barcodes'),
    };
  }

  /// Terapkan usulan produk/harga yang DISETUJUI owner (Item 40) — tulis
  /// langsung ke tabel master (INSERT OR REPLACE, sama seperti [mergeRows]
  /// versi master data) HANYA utk produk dgn id di [approvedProductIds].
  /// `locallyModified` DIPAKSA false di sini (host adalah sumber kebenaran
  /// resmi sekarang) — saat baris ini nanti di-push ke device asisten via
  /// sync normal, flag `false` ini ikut menimpa flag lokal asisten,
  /// menutup "usulan" itu tanpa perlu tracking status terpisah.
  Future<int> applyProductProposals(
      Map<String, List<Map<String, Object?>>> proposals,
      Set<String> approvedProductIds) async {
    if (approvedProductIds.isEmpty) return 0;
    var count = 0;
    // Item 53 (permintaan user) — "ikut harga satuan dasar" sebelumnya
    // cuma tersambung ke `saveProduct` (form Edit Produk biasa), TIDAK ke
    // jalur approve-usulan-sync ini. Ditemukan (productId -> satuan DASAR-
    // nya) sambil memproses `product_units`, harga barunya (kalau ikut
    // di-approve) sambil memproses `price_tiers` — cascade ke varian
    // dijalankan SETELAH transaction() commit (butuh state akhir yg utuh,
    // termasuk kemungkinan varian itu sendiri baru di-approve di batch yg
    // sama).
    final baseUnitOfProduct = <String, ({String unitId, int? unitTypeId})>{};
    final baseUnitNewPrice = <String, int>{};
    // Urutan TETAP (bukan `proposals.entries` mentah — urutan Map hasil
    // decode JSON tidak boleh diasumsikan): product_units WAJIB diproses
    // sebelum tabel anak-satuan, supaya `approvedUnitIds` sudah terisi.
    const order = [
      'products',
      'product_units',
      'price_tiers',
      'alt_prices',
      'product_barcodes',
    ];
    await transaction(() async {
      final approvedUnitIds = <String>{};
      for (final table in order) {
        final rows = proposals[table] ?? const [];
        // Replace PENUH baris anak per satuan yang di-approve: hapus tier
        // harga & harga-alternatif LAMA milik owner utk satuan itu SEBELUM
        // menuliskan baris dari usulan. Tanpa ini, id tier yang diregenerasi
        // tiap edit di form (produk_form_screen) menumpuk jadi tier duplikat
        // `min_qty=1` di owner → harga owner "tak berubah" & saat sync balik
        // ke asisten, tier lama ikut ter-dump lalu menimpa harga terbaru
        // asisten. Satuan (product_unit_id) stabil, jadi cukup di-scope per
        // unit. Barcode SENGAJA tidak di-clear di sini: UNIQUE(barcode) sudah
        // menangani replace, dan mekanisme rilis barcode (RELEASED:) tak boleh
        // terganggu. Aman thd gagal di tengah: SELURUH fungsi dalam satu
        // transaction() — error apa pun me-rollback semuanya.
        if ((table == 'price_tiers' || table == 'alt_prices') &&
            approvedUnitIds.isNotEmpty) {
          final ph = List.filled(approvedUnitIds.length, '?').join(', ');
          await customStatement(
            'DELETE FROM "$table" WHERE product_unit_id IN ($ph)',
            approvedUnitIds.toList(),
          );
        }
        if (rows.isEmpty) continue;
        final localColumns =
            (await customSelect('PRAGMA table_info("$table")').get())
                .map((r) => r.data['name'] as String)
                .toSet();
        for (final row in rows) {
          if (table == 'products') {
            if (!approvedProductIds.contains(row['id'])) continue;
          } else if (table == 'product_units') {
            if (!approvedProductIds.contains(row['product_id'])) continue;
            approvedUnitIds.add(row['id'] as String);
            final isBase =
                row['is_base_unit'] == 1 || row['is_base_unit'] == true;
            if (isBase) {
              baseUnitOfProduct[row['product_id'] as String] = (
                unitId: row['id'] as String,
                unitTypeId: row['unit_type_id'] as int?,
              );
            }
          } else {
            if (!approvedUnitIds.contains(row['product_unit_id'])) continue;
          }
          var cleaned = Map<String, Object?>.from(row)
            ..removeWhere((k, _) => !localColumns.contains(k));
          if (cleaned.isEmpty) continue;
          if (table == 'products') {
            cleaned['locally_modified'] = 0;
            // Bug nyata dilaporkan user: usulan harga yang SUDAH diterapkan
            // owner tetap muncul lagi terus-menerus di sync berikutnya.
            // Akar masalah: baris ini disalin APA ADANYA dari usulan klien,
            // termasuk `updated_at` LAMA (waktu klien mengedit, BUKAN waktu
            // owner menerapkan). `dumpSince` (host→klien) memfilter master
            // data produk dgn `WHERE updated_at >= since` — begitu watermark
            // klien maju melewati timestamp lama itu (sync-sync berikutnya),
            // baris hasil approve ini TIDAK PERNAH lagi ikut terkirim balik
            // ke klien, jadi `locally_modified` di device klien TIDAK PERNAH
            // ke-reset ke false (lihat dok kolom di product_tables.dart yang
            // mengasumsikan baris SELALU "ditimpa oleh push resmi dari host"
            // — asumsi itu gagal persis di sini). Fix: cap `updated_at` ke
            // SAAT INI supaya baris yang baru di-approve ini pasti lolos
            // filter watermark pada sync berikutnya & benar-benar sampai
            // balik ke klien (unix detik, format sama seperti dumpSince).
            cleaned['updated_at'] =
                DateTime.now().millisecondsSinceEpoch ~/ 1000;
          }
          if (table == 'price_tiers') {
            final minQty = cleaned['min_qty'];
            if (minQty == 1) {
              baseUnitNewPrice[cleaned['product_unit_id'] as String] =
                  cleaned['price'] as int;
            }
          }
          final cols = cleaned.keys.map((k) => '"$k"').join(', ');
          final placeholders = cleaned.values.map((_) => '?').join(', ');
          await customInsert(
            'INSERT OR REPLACE INTO "$table" ($cols) VALUES ($placeholders)',
            variables: _rowToVars(cleaned),
          );
          count++;
        }
      }
    });

    // Item 53 — cascade "ikut harga satuan dasar" ke varian, SETELAH commit
    // (butuh state akhir yg utuh). Hanya produk yg SATUAN DASARNYA benar²
    // ikut ter-approve DAN harga tier dasarnya (minQty=1) ada di batch ini —
    // usulan yg sama sekali tidak menyentuh harga satuan dasar (mis. cuma
    // ganti barcode) tidak memicu cascade apa pun.
    for (final entry in baseUnitOfProduct.entries) {
      final newPrice = baseUnitNewPrice[entry.value.unitId];
      final unitTypeId = entry.value.unitTypeId;
      if (newPrice != null && unitTypeId != null) {
        await _cascadeVariantPricesForUnit(
          parentProductId: entry.key,
          anchorUnitTypeId: unitTypeId,
          newBasePrice: newPrice,
        );
      }
    }
    return count;
  }

  /// Buang produk dari usulan [rows] (payload `dumpLocalProposals` dari
  /// klien) yang isinya SUDAH IDENTIK dgn data owner saat ini di HOST ini
  /// (nama, satuan, tier harga, harga alternatif, barcode) — dipanggil host
  /// SEBELUM produk itu masuk antrian `_pendingProposals`. Tanpa filter ini,
  /// produk yang flag `locally_modified` klien-nya "macet" true (mis. form
  /// disimpan ulang tanpa perubahan nilai apa pun, `updated_at` klien ikut
  /// maju & terus "menang" last-write-wins thd baris balikan resmi dari
  /// host — lihat dok kolom `locallyModified`) akan terus-menerus diusulkan
  /// ulang ke owner SETIAP sync, menumpuk di layar review walau tidak ada
  /// apa pun yang perlu diputuskan — laporan nyata user. Produk BARU (belum
  /// ada di DB owner) SELALU lolos filter (tidak ada pembanding).
  ///
  /// Perbandingan tier/harga-alternatif/barcode pakai SET isi (bukan id) —
  /// id tier/alt-harga diregenerasi tiap simpan form produk (lihat dok
  /// `applyProductProposals`), jadi id TIDAK bisa dipakai sbg pembanding.
  Future<Map<String, List<Map<String, Object?>>>> filterUnchangedProposals(
      Map<String, List<Map<String, Object?>>> rows) async {
    final productRows = rows['products'] ?? const [];
    if (productRows.isEmpty) return rows;

    final unitRows = rows['product_units'] ?? const [];
    final tierRows = rows['price_tiers'] ?? const [];
    final altRows = rows['alt_prices'] ?? const [];
    final barcodeRows = rows['product_barcodes'] ?? const [];

    final unitsByProduct = <String, List<Map<String, Object?>>>{};
    for (final u in unitRows) {
      unitsByProduct.putIfAbsent(u['product_id'] as String, () => []).add(u);
    }
    final tiersByUnit = <String, List<Map<String, Object?>>>{};
    for (final t in tierRows) {
      tiersByUnit.putIfAbsent(t['product_unit_id'] as String, () => []).add(t);
    }
    final altsByUnit = <String, List<Map<String, Object?>>>{};
    for (final a in altRows) {
      altsByUnit.putIfAbsent(a['product_unit_id'] as String, () => []).add(a);
    }
    final barcodesByUnit = <String, List<Map<String, Object?>>>{};
    for (final b in barcodeRows) {
      barcodesByUnit
          .putIfAbsent(b['product_unit_id'] as String, () => [])
          .add(b);
    }

    String productSig(Map<String, Object?> p) => '${p['name']}'
        '|${p['product_group_id']}|${p['is_active']}|${p['marked_out_of_stock']}';
    String unitSig(Map<String, Object?> u) => '${u['unit_type_id']}'
        '|${u['is_base_unit']}|${u['ratio_to_base']}|${u['is_non_stock']}'
        '|${u['min_stock']}';
    // Dart `Set`/`List` TIDAK overload `==` sbg pembanding ISI (identity-based
    // spt `Object` default) — dua instance beda dgn isi identik akan SELALU
    // `!=`. Bandingkan sbg STRING kanonik (elemen di-sort dulu, urutan
    // himpunan asal tak relevan di sini) supaya `!=` sungguhan bandingkan isi.
    String tierSigs(List<Map<String, Object?>> tiers) => (tiers
            .map((t) => '${t['min_qty']}|${t['price']}|${t['cost_price']}')
            .toSet()
            .toList()
          ..sort())
        .join(',');
    String altSigs(List<Map<String, Object?>> alts) =>
        (alts.map((a) => '${a['label']}|${a['price']}').toSet().toList()
              ..sort())
            .join(',');
    String barcodeSigs(List<Map<String, Object?>> codes) =>
        (codes.map((b) => '${b['barcode']}').toSet().toList()..sort())
            .join(',');

    final changedProductIds = <String>{};
    for (final p in productRows) {
      final id = p['id'] as String;
      final existingRows = await customSelect(
        'SELECT * FROM "products" WHERE id = ?',
        variables: [Variable.withString(id)],
      ).get();
      if (existingRows.isEmpty) {
        changedProductIds.add(id); // Produk baru — tidak ada pembanding.
        continue;
      }
      if (productSig(existingRows.single.data) != productSig(p)) {
        changedProductIds.add(id);
        continue;
      }

      final proposedUnits = unitsByProduct[id] ?? const [];
      final existingUnitRows = await customSelect(
        'SELECT * FROM "product_units" WHERE product_id = ?',
        variables: [Variable.withString(id)],
      ).get();
      final existingUnitById = {
        for (final r in existingUnitRows) r.data['id'] as String: r.data,
      };

      var changed = proposedUnits.length != existingUnitRows.length;
      for (final u in proposedUnits) {
        if (changed) break;
        final uid = u['id'] as String;
        final existingUnit = existingUnitById[uid];
        if (existingUnit == null || unitSig(existingUnit) != unitSig(u)) {
          changed = true;
          break;
        }
        final existingTierRows = await customSelect(
          'SELECT * FROM "price_tiers" WHERE product_unit_id = ?',
          variables: [Variable.withString(uid)],
        ).get();
        if (tierSigs(existingTierRows.map((r) => r.data).toList()) !=
            tierSigs(tiersByUnit[uid] ?? const [])) {
          changed = true;
          break;
        }
        final existingAltRows = await customSelect(
          'SELECT * FROM "alt_prices" WHERE product_unit_id = ?',
          variables: [Variable.withString(uid)],
        ).get();
        if (altSigs(existingAltRows.map((r) => r.data).toList()) !=
            altSigs(altsByUnit[uid] ?? const [])) {
          changed = true;
          break;
        }
        final existingBarcodeRows = await customSelect(
          'SELECT * FROM "product_barcodes" WHERE product_unit_id = ?',
          variables: [Variable.withString(uid)],
        ).get();
        if (barcodeSigs(existingBarcodeRows.map((r) => r.data).toList()) !=
            barcodeSigs(barcodesByUnit[uid] ?? const [])) {
          changed = true;
          break;
        }
      }
      if (changed) changedProductIds.add(id);
    }

    if (changedProductIds.length == productRows.length) return rows;

    final keptUnitIds = <String>{};
    for (final u in unitRows) {
      if (changedProductIds.contains(u['product_id'])) {
        keptUnitIds.add(u['id'] as String);
      }
    }
    return {
      'products': [
        for (final p in productRows)
          if (changedProductIds.contains(p['id'])) p,
      ],
      'product_units': [
        for (final u in unitRows)
          if (keptUnitIds.contains(u['id'])) u,
      ],
      'price_tiers': [
        for (final t in tierRows)
          if (keptUnitIds.contains(t['product_unit_id'])) t,
      ],
      'alt_prices': [
        for (final a in altRows)
          if (keptUnitIds.contains(a['product_unit_id'])) a,
      ],
      'product_barcodes': [
        for (final b in barcodeRows)
          if (keptUnitIds.contains(b['product_unit_id'])) b,
      ],
    };
  }

  /// Item 41 A.1 — hitung ulang rantai `stock_after` per satuan (dasar)
  /// secara kronologis dari `qty_change`. WAJIB dipanggil setelah merge
  /// `stock_ledger` dari device lain (sync LAN, kedua arah): baris kiriman
  /// membawa `stock_after` hasil hitungan saldo LOKAL device asal — bisa
  /// beda dari saldo di device ini — dan [currentStock] membaca saldo dari
  /// baris "terbaru", jadi tanpa rebuild saldo di sini diam-diam melompat
  /// ke pandangan device lain (mis. host 10, klien yang mengira stok 5
  /// jual 2 → baris klien `stock_after=3` menimpa pandangan host; yang
  /// benar 10-2=8). Σ`qty_change` menghitung tiap pergerakan tepat sekali
  /// (dedup PK oleh INSERT OR IGNORE), jadi rantai hasil rebuild adalah
  /// interpretasi konsisten gabungan kedua device.
  ///
  /// Urutan pakai (created_at ASC, id ASC) — tie-break id utk baris pada
  /// detik yang sama memang tidak kronologis-sejati (uuid acak, Item 38),
  /// tapi saldo AKHIR tidak terpengaruh urutan (penjumlahan komutatif);
  /// hanya nilai `stock_after` antara di detik itu yang kosmetik.
  Future<void> rebuildStockAfterForUnits(Set<String> unitIds) async {
    if (unitIds.isEmpty) return;
    await transaction(() async {
      for (final uid in unitIds) {
        // Item 61.3 — tie-break kedua HARUS `rowid` (bukan `id`/UUID acak),
        // SAMA PERSIS dgn `_rawBaseStock` (yang order DESC) — kalau tidak,
        // utk baris² pada detik yang SAMA, pembaca (`_rawBaseStock`, ambil
        // baris "terakhir") & penulis-ulang saldo (fungsi ini) bisa memilih
        // baris "terakhir" yang BERBEDA, bikin saldo stok berbeda permanen
        // antar host/client stlh sync (total akhir sama krn penjumlahan
        // komutatif, tapi baris mana yang dianggap "terbaru" oleh
        // `_rawBaseStock` bisa beda dari urutan yang dipakai di sini).
        final rows = await customSelect(
          'SELECT id, qty_change, stock_after FROM stock_ledger '
          'WHERE product_unit_id = ? ORDER BY created_at ASC, rowid ASC',
          variables: [Variable.withString(uid)],
        ).get();
        var running = 0.0;
        for (final r in rows) {
          running += (r.data['qty_change'] as num?)?.toDouble() ?? 0;
          final current = (r.data['stock_after'] as num?)?.toDouble();
          if (current == running) continue; // sudah benar — hemat tulis
          await customUpdate(
            'UPDATE stock_ledger SET stock_after = ? WHERE id = ?',
            variables: [
              Variable.withReal(running),
              Variable.withString(r.data['id'] as String),
            ],
            updates: {stockLedger},
            updateKind: UpdateKind.update,
          );
        }
      }
    });
  }

  /// Item 60 — hitung ulang `customers.loyalty_points` per pelanggan dari
  /// SUM `loyalty_point_ledger.points` (pola PERSIS `rebuildStockAfterForUnits`
  /// di atas). WAJIB dipanggil setelah merge `loyalty_point_ledger` dari
  /// device lain (sync LAN, kedua arah): `customers` adalah master data yang
  /// sync-nya last-write-wins berdasar `updated_at`, sementara 7 tempat tulis
  /// `loyalty_points` yang ada (increment/decrement mentah, ditulis atomik
  /// bareng baris ledger di device ASAL) TIDAK menyentuh `updated_at` sama
  /// sekali — poin yang baru didapat device lain bisa KETIMPA BALIK begitu
  /// host push versi lama pelanggan itu. Ledger-nya sendiri sinkron dengan
  /// benar (append-only, PK dedup); rebuild ini menurunkan kolom saldo yang
  /// dipakai di layar langsung dari ledger, bukan dari `updated_at` LWW.
  Future<void> rebuildLoyaltyPointsForCustomers(Set<String> customerIds) async {
    if (customerIds.isEmpty) return;
    await transaction(() async {
      for (final cid in customerIds) {
        final row = await customSelect(
          'SELECT COALESCE(SUM(points), 0) AS total FROM loyalty_point_ledger '
          'WHERE customer_id = ?',
          variables: [Variable.withString(cid)],
        ).getSingle();
        final total = (row.data['total'] as num?)?.toInt() ?? 0;
        await customUpdate(
          'UPDATE customers SET loyalty_points = ? WHERE id = ?',
          variables: [Variable.withInt(total), Variable.withString(cid)],
          updates: {customers},
          updateKind: UpdateKind.update,
        );
      }
    });
  }

  /// Merge rows from sync payload (INSERT OR IGNORE for ledger, last-write-wins for master).
  Future<int> mergeRows(String tableName, List<Map<String, Object?>> rows,
      bool isAppendOnly) async {
    // Item 41 B.3 — nama tabel disisipkan ke SQL sbg identifier; payload
    // sync datang dari luar device, jadi kunci ke bentuk identifier wajar
    // (huruf kecil/underscore/digit) sebelum menyentuh PRAGMA/INSERT.
    // Pemanggil sah selalu lolos (semua nama tabel app berpola ini).
    if (!RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(tableName)) {
      throw ArgumentError('Nama tabel sync tidak valid: $tableName');
    }
    // Guard KEY-level utk `app_settings`: tabel ini bercampur setting toko
    // (boleh seragam) dgn identitas/state device (`store_uuid`, `store_key`,
    // `device_code`, watermark sync...). Disaring di SINI — titik masuk data
    // dari luar device — supaya payload yang menyelundupkan key lain tetap
    // ditolak walau dump pengirimnya tidak bisa dipercaya. Lihat dok
    // [syncableSettingKeys].
    if (tableName == 'app_settings') {
      rows = rows.where((r) => syncableSettingKeys.contains(r['key'])).toList();
      if (rows.isEmpty) return 0;
    }
    // customStatement/customInsert lewat raw SQL tidak diketahui Drift tabel
    // mana yang berubah, jadi StreamProvider (mis. daftar produk/pelanggan)
    // yang bergantung pada .watch() TIDAK auto-refresh walau data sungguhan
    // sudah berubah lewat sync — data DI DB sudah benar (mis. produk yang
    // dinonaktifkan owner), tapi UI klien tetap terlihat "tidak berubah"
    // sampai dipaksa reload manual (restart app dll). Param `updates:`
    // memberi tahu Drift tabel yang terpengaruh — pola sama spt
    // `restoreFromDump`, ketinggalan dipasang di sini sebelumnya.
    final table = {for (final t in allTables) t.entityName: t}[tableName];
    var count = 0;
    // Perangkat berbeda (owner/kasir) bisa update app tidak serentak — dump
    // dari pengirim yang schemanya lebih baru bisa membawa kolom yang belum
    // ada secara fisik di tabel lokal penerima (mis. kolom baru dari migrasi
    // yang belum sempat ter-install di device itu). Tanpa filter ini, satu
    // kolom baru saja bikin SELURUH sync gagal ("no column named ..."),
    // bukan cuma baris/kolom itu. Baca kolom fisik via PRAGMA (bukan definisi
    // tabel Drift yang statis di kode) supaya benar-benar mencerminkan skema
    // SQLite yang sungguhan berjalan di device ini saat ini.
    final localColumns =
        (await customSelect('PRAGMA table_info("$tableName")').get())
            .map((r) => r.data['name'] as String)
            .toSet();

    // Bug nyata dilaporkan user (audit "sync harga di tab produk, aman
    // bolak-balik?"): kalau asisten edit harga (products.locallyModified
    // =true, usulan belum di-review owner) lalu sync lagi utk hal LAIN
    // sebelum owner sempat approve, editnya TERTIMPA BALIK (price_tiers)
    // atau DUPLIKAT (alt_prices)/tertimpa (product_units) oleh data lama
    // owner — akar: 4 tabel ini disinkron full-dump TANPA `updated_at`
    // sama sekali (beda dari `products`), jadi last-write-wins di atas
    // tidak berlaku, INSERT OR REPLACE/dedup-by-key selalu menang tanpa
    // syarat. Fix: skip baris yang unit-nya milik produk yang MASIH
    // `locally_modified=true` di device INI — biarkan edit lokal yang
    // belum-di-approve tetap utuh sampai owner benar² approve/reject
    // (flag baru bersih setelah baris resmi ditimpa push dari host, lihat
    // dok `Products.locallyModified`). SATU query di awal (bukan per-baris)
    // supaya biaya performa nyaris nol — 4 tabel ini bisa berisi ribuan
    // baris per sync (full-dump tanpa filter).
    const guardedUnitTables = {
      'price_tiers',
      'alt_prices',
      'product_barcodes',
    };
    Set<String>? protectedUnitIds;
    if (!isAppendOnly &&
        (tableName == 'product_units' ||
            guardedUnitTables.contains(tableName))) {
      final protectedRows = await customSelect(
        'SELECT pu.id AS unit_id FROM product_units pu '
        'JOIN products p ON p.id = pu.product_id '
        'WHERE p.locally_modified = 1',
      ).get();
      protectedUnitIds =
          protectedRows.map((r) => r.data['unit_id'] as String).toSet();
    }

    await transaction(() async {
      for (var row in rows) {
        if (row.isEmpty) continue;
        row = Map<String, Object?>.from(row)
          ..removeWhere((k, _) => !localColumns.contains(k));
        if (row.isEmpty) continue;

        if (protectedUnitIds != null) {
          final unitId =
              tableName == 'product_units' ? row['id'] : row['product_unit_id'];
          if (unitId is String && protectedUnitIds.contains(unitId)) continue;
        }

        if (isAppendOnly) {
          // Append-only: skip if PK already exists.
          final pkVal = row['id'];
          if (pkVal != null) {
            final selectCols = tableName == 'expenses' ? 'deleted_at' : '1';
            final exists = await customSelect(
              'SELECT $selectCols FROM "$tableName" WHERE id = ?',
              variables: [Variable<Object>(pkVal)],
            ).getSingleOrNull();
            if (exists != null) {
              // Item 61.5 — `expenses` KHUSUS: baris yang isinya sendiri
              // tidak pernah berubah (append-only-nya sungguhan), TAPI
              // status soft-delete (`deleted_at`) satu-arah aktif→dihapus
              // WAJIB tetap bisa propagate walau PK sudah ada di sisi ini —
              // beda dari tabel append-only lain yang genuinely skip total.
              if (tableName == 'expenses' &&
                  row['deleted_at'] != null &&
                  exists.data['deleted_at'] == null) {
                await customUpdate(
                  'UPDATE expenses SET deleted_at = ? WHERE id = ?',
                  variables: [
                    Variable<Object>(row['deleted_at']!),
                    Variable<Object>(pkVal),
                  ],
                  updates: {expenses},
                  updateKind: UpdateKind.update,
                );
              }
              // Item 62 — `transactions` KHUSUS: baris yang sudah ada
              // (`INSERT OR IGNORE` di bawah akan no-op) masih bisa punya
              // field yang genuinely berubah setelah tersinkron pertama kali
              // (status void, ganti pelanggan, poin) — TIDAK bisa
              // direkonstruksi dari `transaction_items`/`transaction_payments`
              // (beda dari total/paid/changeAmount yang direkonsiliasi ulang
              // otomatis pasca-merge, lihat `reconcileTransactionsByIds`).
              // Last-write-wins by `updated_at`, sama pola dgn tabel master.
              // Field per-device (`checked_item_ids`, `change_taken`,
              // `synced_at`) SENGAJA tidak ikut — lihat dok kolomnya.
              if (tableName == 'transactions') {
                final incomingUpdatedAt = row['updated_at'];
                if (incomingUpdatedAt is int) {
                  final existingFull = await customSelect(
                    'SELECT updated_at FROM "transactions" WHERE id = ?',
                    variables: [Variable<Object>(pkVal)],
                  ).getSingleOrNull();
                  final existingUpdatedAt =
                      existingFull?.data['updated_at'] as int?;
                  if (existingUpdatedAt == null ||
                      incomingUpdatedAt > existingUpdatedAt) {
                    await customUpdate(
                      'UPDATE transactions SET status = ?, customer_id = ?, '
                      'customer_name = ?, points_earned = ?, updated_at = ? '
                      'WHERE id = ?',
                      variables: [
                        Variable<Object>(row['status'] ?? ''),
                        Variable<Object>(row['customer_id']),
                        Variable<Object>(row['customer_name']),
                        Variable<Object>(row['points_earned'] ?? 0),
                        Variable<Object>(incomingUpdatedAt),
                        Variable<Object>(pkVal),
                      ],
                      updates: {transactions},
                      updateKind: UpdateKind.update,
                    );
                  }
                }
              }
              continue;
            }
          }
          // Transactions & expenses have UNIQUE(local_id). Two devices with
          // the same kasir code produce identical local_ids for different
          // transactions. Rename the incoming local_id to avoid silent drops.
          if (row.containsKey('local_id')) {
            final localId = row['local_id'];
            if (localId is String && localId.isNotEmpty) {
              Future<bool> taken(String cand) async =>
                  (await customSelect(
                    'SELECT 1 FROM "$tableName" WHERE local_id = ?',
                    variables: [Variable<Object>(cand)],
                  ).getSingleOrNull()) !=
                  null;
              if (await taken(localId)) {
                // Cari suffix bebas — '-S' statis bisa tabrakan lagi saat
                // 3+ perangkat memakai kode kasir yang sama, dan INSERT OR
                // IGNORE akan mem-drop transaksinya diam-diam.
                var candidate = '$localId-S';
                var n = 2;
                while (await taken(candidate)) {
                  candidate = '$localId-S$n';
                  n++;
                }
                row = Map<String, Object?>.from(row);
                row['local_id'] = candidate;
              }
            }
          }
        } else {
          // Last-write-wins for master tables with updated_at.
          if (row.containsKey('updated_at')) {
            final incomingTs = row['updated_at'];
            final pkCol = row.containsKey('id')
                ? 'id'
                : row.containsKey('permission_key')
                    ? 'permission_key'
                    : null;
            final pkVal = pkCol != null ? row[pkCol] : null;
            if (pkVal != null && incomingTs is int) {
              final existing = await customSelect(
                'SELECT updated_at FROM "$tableName" WHERE "$pkCol" = ?',
                variables: [Variable<Object>(pkVal)],
              ).getSingleOrNull();
              if (existing != null) {
                final existingTs = existing.data['updated_at'];
                if (existingTs is int && incomingTs < existingTs) continue;
              }
            }
          }
          // price_tiers: cegah duplikat tier (product_unit_id, min_qty).
          if (tableName == 'price_tiers') {
            final unitId = row['product_unit_id'];
            final minQty = row['min_qty'];
            final incomingId = row['id'];
            if (unitId != null && minQty != null && incomingId != null) {
              final existing = await customSelect(
                'SELECT id FROM price_tiers '
                'WHERE product_unit_id = ? AND min_qty = ? AND id != ?',
                variables: [
                  Variable<Object>(unitId),
                  Variable<Object>(minQty),
                  Variable<Object>(incomingId),
                ],
              ).get();
              for (final e in existing) {
                await customUpdate(
                  'DELETE FROM price_tiers WHERE id = ?',
                  variables: [Variable<Object>(e.data['id']!)],
                  updates: {priceTiers},
                  updateKind: UpdateKind.delete,
                );
              }
            }
          }
        }

        final cols = row.keys.map((k) => '"$k"').join(', ');
        final placeholders = row.values.map((_) => '?').join(', ');
        final variables = _rowToVars(row);
        final mode = isAppendOnly ? 'INSERT OR IGNORE' : 'INSERT OR REPLACE';
        // Bug nyata dilaporkan user: struk yang diterima lewat sync tampil
        // TANPA daftar item sama sekali (header & pembayaran normal). Akar
        // masalah: `INSERT OR IGNORE` HANYA menekan pelanggaran UNIQUE/PK —
        // pelanggaran FOREIGN KEY (mis. baris `transaction_items` yatim,
        // transaction_id-nya tidak ada di device pengirim maupun penerima)
        // TETAP throw, dan exception itu keluar dari callback `transaction()`
        // di atas → Drift rollback SELURUH baris dalam SATU panggilan
        // `mergeRows` ini (bukan cuma baris yang salah) — satu baris korup
        // milik SATU transaksi meracuni item transaksi LAIN yang valid dalam
        // batch sync yang sama, konsisten dgn tiap sync berikutnya (klien
        // selalu full-dump) selama baris korup itu masih ada di device
        // pengirim. Tangkap per-baris di sini supaya SATU baris gagal cuma
        // di-skip (dicatat ke CrashLogService utk diagnosis), baris lain
        // dalam batch yang sama tetap ter-merge.
        try {
          final inserted = await customInsert(
            '$mode INTO "$tableName" ($cols) VALUES ($placeholders)',
            variables: variables,
            updates: table == null ? null : {table},
          );
          if (inserted > 0) count++;
        } catch (e, st) {
          await CrashLogService.record(e, st,
              context: 'app_database_merge_rows_row table=$tableName');
        }
      }

      // Item 54 — `product_group_tags` SELALU dikirim full-dump (lihat
      // `dumpSince`, sama seperti `customer_groups`), beda dari tabel
      // master lain yang cuma bertambah/berganti isi (tidak pernah benar²
      // hilang barisnya). Untag kategori (hapus baris) adalah aksi
      // sehari-hari di sini — tanpa cleanup ini, baris yang sudah di-untag
      // di owner akan MENETAP SELAMANYA di klien (INSERT OR REPLACE saja
      // tidak pernah menghapus baris yang tidak lagi ada di payload).
      // Payload yang diterima = kebenaran LENGKAP saat ini, jadi aman
      // hapus semua baris lokal yang TIDAK ada di dalamnya.
      if (!isAppendOnly && tableName == 'product_group_tags') {
        final incomingKeys =
            rows.map((r) => '${r['product_id']}|${r['group_id']}').toSet();
        final existing = await customSelect(
          'SELECT product_id, group_id FROM product_group_tags',
        ).get();
        for (final e in existing) {
          final pid = e.data['product_id'];
          final gid = e.data['group_id'];
          if (!incomingKeys.contains('$pid|$gid')) {
            await customUpdate(
              'DELETE FROM product_group_tags WHERE product_id = ? AND group_id = ?',
              variables: [Variable<Object>(pid!), Variable<Object>(gid!)],
              updates: {productGroupTags},
              updateKind: UpdateKind.delete,
            );
          }
        }
      }

      // Bug nyata dilaporkan user: owner edit barcode produk -> setelah sync
      // ke klien, barcode LAMA masih ada (bisa di-scan) BERDAMPINGAN dgn yg
      // baru. Akar: `saveProduct` HAPUS baris lama + INSERT baris baru (id
      // UUID baru) saat barcode diedit, bukan update in-place — dan tabel ini
      // (sama seperti price_tiers/alt_prices) SELALU full-dump tanpa
      // `updated_at` (lihat `dumpSince`), jadi `INSERT OR REPLACE` di atas
      // tidak pernah menghapus baris yang sudah tak ada di payload. Payload
      // full-dump = kebenaran LENGKAP host saat ini, jadi aman hapus baris
      // lokal yang id-nya tak ada di dalamnya — KECUALI baris milik unit yang
      // sedang diproteksi (`protectedUnitIds`, usulan lokal blm di-approve),
      // supaya edit lokal yang belum di-review owner tidak ikut kehapus.
      const orphanCleanupTables = {
        'product_barcodes',
        'price_tiers',
        'alt_prices'
      };
      if (!isAppendOnly && orphanCleanupTables.contains(tableName)) {
        final incomingIds =
            rows.map((r) => r['id']).whereType<String>().toSet();
        final existing = await customSelect(
          'SELECT id, product_unit_id FROM "$tableName"',
        ).get();
        for (final e in existing) {
          final id = e.data['id'] as String?;
          if (id == null || incomingIds.contains(id)) continue;
          final unitId = e.data['product_unit_id'] as String?;
          if (protectedUnitIds != null &&
              unitId != null &&
              protectedUnitIds.contains(unitId)) {
            continue;
          }
          await customUpdate(
            'DELETE FROM "$tableName" WHERE id = ?',
            variables: [Variable<Object>(id)],
            updates: {table!},
            updateKind: UpdateKind.delete,
          );
        }
      }
    });
    return count;
  }

  // ───────────────────────── Laci Meja (Item 52) ─────────────────────────
  //
  // Titip/Ketinggalan, Pinjaman Barang, Pre-order. Rancangan lengkap &
  // keputusan bisnis: PLAN.md Item 52. `locallyModified` mengikuti pola
  // Item 40 (usulan produk): UI yang memanggil create/update di sini WAJIB
  // set true kalau device BUKAN owner (lihat `device.isOwner`) — device
  // owner tidak pernah set true (sumber kebenaran, tidak perlu mengusulkan
  // ke diri sendiri).

  // ── Titip/Ketinggalan ──

  Future<void> addLeftBehindItem({
    required String id,
    required String transactionId,
    required String itemName,
    required String jenis,
    String? transactionItemId,
    String? customerId,
    String? customerNameText,
    String? note,
    double? qty,
    bool locallyModified = false,
  }) =>
      into(leftBehindItems).insert(LeftBehindItemsCompanion.insert(
        id: id,
        transactionId: transactionId,
        itemName: itemName,
        jenis: jenis,
        transactionItemId: Value(transactionItemId),
        customerId: Value(customerId),
        customerNameText: Value(customerNameText),
        note: Value(note),
        qty: Value(qty),
        locallyModified: Value(locallyModified),
      ));

  /// Baris nota mana saja yang ditandai titip/ketinggalan — dipakai struk
  /// in-app utk memberi penanda per-item (pola sama dgn badge "Habis" di
  /// katalog kasir). Key = `transaction_items.id`, value = jenis + qty
  /// (SEBAGIAN dari qty baris nota, bisa null utk entri lama = seluruh
  /// qty). Entri tanpa `transactionItemId` (dibuat sebelum kolom itu ada)
  /// otomatis terlewat — memang tidak bisa dipetakan ke baris tertentu.
  Future<Map<String, ({String jenis, double? qty})>>
      getLeftBehindMarksForTransaction(String transactionId) async {
    final rows = await (select(leftBehindItems)
          ..where((t) =>
              t.transactionId.equals(transactionId) &
              t.collectedAt.isNull() &
              t.transactionItemId.isNotNull()))
        .get();
    return {
      for (final r in rows) r.transactionItemId!: (jenis: r.jenis, qty: r.qty)
    };
  }

  /// Item 52 susulan (permintaan user) — qty+satuan per baris nota yang
  /// ditandai titip/ketinggalan, dipakai dashboard Laci Meja supaya kasir
  /// tahu PERSIS berapa banyak & satuan apa tanpa buka nota. Satu query
  /// JOIN (bukan N+1) utk sekumpulan `transaction_items.id` sekaligus.
  Future<Map<String, ({double qty, String unitName})>>
      getQtyUnitForTransactionItems(List<String> transactionItemIds) async {
    if (transactionItemIds.isEmpty) return {};
    final rows = await (select(transactionItems).join([
      leftOuterJoin(productUnits,
          productUnits.id.equalsExp(transactionItems.productUnitId)),
      leftOuterJoin(unitTypes, unitTypes.id.equalsExp(productUnits.unitTypeId)),
    ])
          ..where(transactionItems.id.isIn(transactionItemIds)))
        .get();
    return {
      for (final row in rows)
        row.readTable(transactionItems).id: (
          qty: row.readTable(transactionItems).qty,
          unitName: row.readTableOrNull(unitTypes)?.name ?? '',
        ),
    };
  }

  /// Item 52 redesain pre-order — jumlah jaminan (wadah kosong) yang dititip
  /// utk tiap BARIS item di SATU nota, dipakai struk in-app/share/ESC-POS
  /// memberi label "Titip [qty]" di samping nama barang (persis pola
  /// qty+satuan di atas). Baca peta ini LEWAT `preorderDepositForLine`
  /// (`core/utils/preorder_calc.dart`), jangan akses key-nya langsung.
  ///
  /// Dua jenis key dalam SATU peta:
  ///   • `transaction_item_id` (= `item.id`) — entri yang tertaut PRESISI ke
  ///     baris nota (`PreorderEntries.transactionItemId`, diisi checkout &
  ///     tambah belanjaan sejak v36). Nilai = jaminan entri ITU saja.
  ///   • `'$productId|$productUnitId'` — fallback utk entri LAMA tanpa
  ///     tautan (`transactionItemId` null); kalau ada beberapa, DIJUMLAHKAN
  ///     (bukan ditimpa).
  /// Bug nyata dilaporkan user: versi lama HANYA keyed produk+satuan &
  /// entri kedua utk produk yg sama MENIMPA yg pertama — nota dgn 2 baris
  /// LPG (asli + "Tambahan", masing-masing punya entri pre-order sendiri)
  /// menampilkan "Titip 1" di KEDUA baris, padahal kartu Pre-order (benar)
  /// menampilkan 2 + 1. Komentar lama "cukup presisi krn pre-order dibuat via
  /// SATU baris cart per produk+satuan per nota" SALAH — "Tambahan" bisa
  /// menambah baris produk yang sama ke nota yang sama.
  ///
  /// Nilainya jaminan SISA (`sisaDeposit`: dikurangi qty yang sudah
  /// dipenuhi sebagian), konsisten dgn dashboard & laporan salin-teks —
  /// bukan `depositQty` mentah. Entri yang sisanya 0 tidak masuk peta.
  /// Penanda ini TEMPORARY (keputusan user, susulan) — hilang begitu
  /// pre-order-nya dipenuhi/dibatalkan (`fulfilledAt`/`cancelledAt` diisi)
  /// di dashboard Laci Meja. Difilter di query ini, bukan cuma di UI.
  Future<Map<String, double>> getPreorderDepositForTransaction(
      String transactionId) async {
    final rows = await (select(preorderEntries)
          ..where((t) =>
              t.transactionId.equals(transactionId) &
              t.depositQty.isBiggerThanValue(0) &
              t.fulfilledAt.isNull() &
              t.cancelledAt.isNull()))
        .get();
    if (rows.isEmpty) return {};
    final taken = await getLaciMejaTakenQty(rows.map((r) => r.id).toList());
    final out = <String, double>{};
    for (final r in rows) {
      final sisa = sisaDeposit(r, taken[r.id] ?? 0);
      if (sisa <= 0) continue;
      final key = r.transactionItemId ?? '${r.productId}|${r.productUnitId}';
      out[key] = (out[key] ?? 0) + sisa;
    }
    return out;
  }

  /// Susulan (permintaan user) — pre-order TERBUKA milik pelanggan yang SAMA
  /// tapi dicatat di NOTA LAIN, dikelompokkan per `productId`. Dipakai struk
  /// in-app: baris item yang produknya cocok dgn pre-order terbuka pelanggan
  /// ini jadi bisa DIKLIK, merujuk balik ke nota tempat pre-order itu
  /// dibuat — berguna kalau kasir/owner sewaktu-waktu ingin cek momen nota
  /// asli (mis. pelanggan pre-order tanpa DP, lalu belanja lagi di nota
  /// terpisah beberapa hari kemudian).
  ///
  /// Item 58 (audit sesi sebelumnya, lihat PLAN.md) — pelanggan TERDAFTAR
  /// ([customerId] terisi) dicocokkan MURNI lewat `PreorderEntries.
  /// customerId`, BUKAN nama: dua pelanggan terdaftar beda id yang kebetulan
  /// namanya sama (mis. dua "Budi") sebelumnya bisa saling tertaut
  /// pre-order-nya kalau cuma lewat nama. Pembeli ad-hoc ([customerId] null)
  /// TETAP lewat nama seperti sebelumnya — satu-satunya identitas yang
  /// tersedia utk kasus itu, pola sama dgn [getLaciMejaPending].
  ///
  /// [excludeTransactionId] — nota yang SEDANG dilihat, supaya pre-order
  /// milik nota itu sendiri tidak "merujuk ke dirinya sendiri". Baris tanpa
  /// `transactionId` (titip wadah tanpa beli apa pun) tidak ada nota utk
  /// dirujuk, otomatis tersaring lewat `isNotNull()`. Kalau satu produk
  /// punya BEBERAPA pre-order terbuka, yang PALING LAMA (FIFO, konsisten dgn
  /// urutan dashboard) yang dipakai sbg rujukan.
  Future<Map<String, ({String transactionId, DateTime createdAt})>>
      getOpenPreorderRefsForCustomer({
    String? customerId,
    required String customerName,
    required String excludeTransactionId,
  }) async {
    final id = customerId?.trim() ?? '';
    final nama = customerName.trim();
    if (id.isEmpty && nama.isEmpty) return {};
    final rows = await (select(preorderEntries)
          ..where((t) =>
              (id.isNotEmpty
                  ? t.customerId.equals(id)
                  : t.customerName.equals(nama)) &
              t.fulfilledAt.isNull() &
              t.cancelledAt.isNull() &
              t.transactionId.isNotNull() &
              t.transactionId.equals(excludeTransactionId).not())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final out = <String, ({String transactionId, DateTime createdAt})>{};
    for (final r in rows) {
      // `orderBy` asc + `putIfAbsent` -> baris PERTAMA per productId (paling
      // lama) yang menang, entri berikutnya utk produk yang sama diabaikan.
      out.putIfAbsent(r.productId,
          () => (transactionId: r.transactionId!, createdAt: r.createdAt));
    }
    return out;
  }

  /// Item 52 redesain — nama produk+satuan utk sekumpulan `product_unit_id`
  /// (dipakai dashboard Laci Meja tab Pre-order menampilkan "qty produk -
  /// jaminan" per baris). Satu JOIN, bukan N+1.
  Future<Map<String, ({String productName, String unitName})>>
      getProductUnitLabelsFor(List<String> productUnitIds) async {
    if (productUnitIds.isEmpty) return {};
    final rows = await (select(productUnits).join([
      innerJoin(products, products.id.equalsExp(productUnits.productId)),
      leftOuterJoin(unitTypes, unitTypes.id.equalsExp(productUnits.unitTypeId)),
    ])
          ..where(productUnits.id.isIn(productUnitIds)))
        .get();
    return {
      for (final row in rows)
        row.readTable(productUnits).id: (
          productName: row.readTable(products).name,
          unitName: row.readTableOrNull(unitTypes)?.name ?? '',
        ),
    };
  }

  /// Nama pelanggan TERKINI milik sekumpulan nota — dipakai dashboard Laci
  /// Meja supaya nama yang tampil selalu ikut nota rujukannya.
  ///
  /// Dilaporkan user: pre-order LPG dibuat saat nota masih memakai pembeli
  /// ad-hoc, lalu notanya diubah ke pelanggan terdaftar — di Laci Meja
  /// namanya TETAP yang lama. Akarnya: ketiga tabel Laci Meja menyimpan nama
  /// pelanggan sebagai SALINAN BEKU saat entri dicatat
  /// (`customerNameText`/`customerName`), tidak pernah dicap ulang saat nota
  /// berubah. Alih-alih menambah jalur "cap ulang" (yang untuk device kasir
  /// berarti mutasi master-data -> antrian persetujuan owner, lihat dok
  /// `dumpLaciMejaProposals`), nama cukup DIBACA HIDUP dari notanya di sisi
  /// tampilan — otomatis benar juga untuk entri lama yang terlanjur salah,
  /// tanpa migrasi & tanpa backfill.
  ///
  /// Mengikuti model tiga-keadaan `Transactions` apa adanya (lihat dok
  /// `Transactions.customerName`): `customerId` menang, lalu `customerName`
  /// ad-hoc, dan nota tanpa keduanya TIDAK masuk hasil sama sekali —
  /// pemanggil yang memutuskan cadangannya (salinan beku lama, atau "Umum").
  Future<Map<String, String>> getCustomerNamesForTransactions(
      List<String> transactionIds) async {
    if (transactionIds.isEmpty) return {};
    final rows = await (select(transactions).join([
      leftOuterJoin(customers, customers.id.equalsExp(transactions.customerId)),
    ])
          ..where(transactions.id.isIn(transactionIds)))
        .get();
    final out = <String, String>{};
    for (final row in rows) {
      final tx = row.readTable(transactions);
      // Pelanggan terdaftar bisa saja sudah dihapus (soft-delete) — kalau
      // baris `customers`-nya tidak ketemu, jangan diam-diam jatuh ke
      // `customerName` nota (kolom itu justru diabaikan saat customerId
      // terisi); biarkan kosong supaya pemanggil pakai cadangannya sendiri.
      final name = tx.customerId != null
          ? row.readTableOrNull(customers)?.name
          : tx.customerName;
      if (name != null && name.trim().isNotEmpty) out[tx.id] = name.trim();
    }
    return out;
  }

  /// Susulan (permintaan user): alamat pelanggan TERDAFTAR utk sekumpulan
  /// `customerId` — dipakai dashboard Laci Meja menampilkan alamat di bawah
  /// nama, supaya nama KEMBAR (mis. dua "Bu Sri" beda alamat) bisa
  /// dibedakan tanpa harus buka nota. Cuma utk pelanggan terdaftar (baris
  /// Laci Meja punya `customerId`) — pelanggan ad-hoc tidak punya record
  /// `Customers` sama sekali, jadi tidak ada alamat yang bisa diambil.
  Future<Map<String, String>> getCustomerAddressesForIds(
      List<String> customerIds) async {
    if (customerIds.isEmpty) return {};
    final rows =
        await (select(customers)..where((t) => t.id.isIn(customerIds))).get();
    final out = <String, String>{};
    for (final c in rows) {
      final addr = c.address?.trim();
      if (addr != null && addr.isNotEmpty) out[c.id] = addr;
    }
    return out;
  }

  /// Baris `BorrowedItems` (pinjaman) milik SATU nota — dipakai struk in-app
  /// menampilkan SECTION "Pinjaman Barang" ("rujukan kebenaran" permintaan
  /// user: staf bisa cek nota asli utk konfirmasi barang apa yang memang
  /// dipinjamkan dari transaksi itu).
  ///
  /// SECTION, bukan penanda per-baris produk: nama barang pinjaman diketik
  /// bebas (biasanya WADAH — galon/tabung kosong — yang justru BUKAN baris
  /// di nota), jadi tidak ada baris nota yang bisa ditempeli penanda.
  ///
  /// Sengaja TIDAK memfilter `fullyReturnedAt`: nota adalah bukti historis
  /// permanen, bukan indikator status hidup — begitu sesuatu pernah
  /// dipinjamkan lewat nota ini, catatannya tetap ada walau sudah kembali.
  Future<List<BorrowedItem>> getBorrowedForTransaction(String transactionId) =>
      (select(borrowedItems)
            ..where((t) => t.transactionId.equals(transactionId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Susulan (permintaan user) — barang titip/ketinggalan yang BUKAN baris
  /// nota (`transactionItemId IS NULL`), mis. barang pelanggan yang tidak
  /// dibeli di toko ini tapi tertinggal/sengaja dititipkan. Pola identik
  /// [getBorrowedForTransaction]: dipakai section terpisah di struk (bukan
  /// penanda per-baris — tidak ada baris nota utk ditaut).
  Future<List<LeftBehindItem>> getLeftBehindWithoutLineForTransaction(
          String transactionId) =>
      (select(leftBehindItems)
            ..where((t) =>
                t.transactionId.equals(transactionId) &
                t.transactionItemId.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Ringkasan Laci Meja yang MASIH menggantung utk satu pelanggan —
  /// dipakai pengingat di cart bar & modal checkout (pola sama dgn
  /// pengingat hutang), supaya barang titipan/pinjaman/pre-order tidak
  /// terlupa saat pelanggan yang sama datang lagi.
  ///
  /// `titip` dan `ketinggalan` DIPISAH (bukan digabung satu angka) —
  /// permintaan user: keterangan di modal checkout wajib cocok dgn jenis
  /// asli barangnya, jangan selalu tertulis "dititip" padahal aslinya
  /// ketinggalan tanpa sengaja.
  /// SATU pintu utk semua kategori — [customerId] dipakai mencocokkan
  /// Titip/Ketinggalan & Pinjaman (keduanya menyimpan FK pelanggan),
  /// [customerName] dipakai mencocokkan Pre-order (tabel `PreorderEntries`
  /// HANYA menyimpan nama, tanpa FK — lihat dok tabelnya).
  ///
  /// KEDUANYA boleh diisi sekaligus & memang seharusnya begitu utk pelanggan
  /// TERDAFTAR: versi lama memisahkan jadi 2 method dan yang berbasis
  /// `customerId` selalu mengembalikan `preorder: 0` — akibatnya pre-order
  /// milik pelanggan terdaftar TIDAK PERNAH muncul di pengingat sama sekali.
  Future<LaciMejaPending> getLaciMejaPending({
    String? customerId,
    String? customerName,
  }) async {
    final id = customerId?.trim() ?? '';
    final nama = customerName?.trim() ?? '';
    if (id.isEmpty && nama.isEmpty) return kEmptyLaciMejaPending;

    // Titip/Ketinggalan & Pinjaman: cocokkan lewat id kalau pelanggan
    // terdaftar, kalau tidak lewat nama teksnya.
    //
    // Item 60 — JOIN ke `transactions` & kecualikan nota yang sudah di-void
    // (`voidTransaction` tidak menghapus baris Titip/Pinjaman, cuma menulis
    // event 'batal' audit — lihat dok di `voidTransaction`; tabel ini
    // sengaja TIDAK dapat kolom `cancelledAt` baru, status "batal"-nya
    // murni disimpulkan dari status nota induk di sini).
    final left = id.isNotEmpty
        ? (await (select(leftBehindItems).join([
            innerJoin(transactions,
                transactions.id.equalsExp(leftBehindItems.transactionId)),
          ])
                ..where(leftBehindItems.customerId.equals(id) &
                    leftBehindItems.collectedAt.isNull() &
                    transactions.status.isNotValue('void')))
              .get())
            .map((r) => r.readTable(leftBehindItems))
            .toList()
        : (await (select(leftBehindItems).join([
            innerJoin(transactions,
                transactions.id.equalsExp(leftBehindItems.transactionId)),
          ])
                ..where(leftBehindItems.customerNameText.equals(nama) &
                    leftBehindItems.collectedAt.isNull() &
                    transactions.status.isNotValue('void')))
              .get())
            .map((r) => r.readTable(leftBehindItems))
            .toList();
    final borrowed = id.isNotEmpty
        ? (await (select(borrowedItems).join([
            innerJoin(transactions,
                transactions.id.equalsExp(borrowedItems.transactionId)),
          ])
                ..where(borrowedItems.customerId.equals(id) &
                    borrowedItems.fullyReturnedAt.isNull() &
                    transactions.status.isNotValue('void')))
              .get())
            .map((r) => r.readTable(borrowedItems))
            .toList()
        : (await (select(borrowedItems).join([
            innerJoin(transactions,
                transactions.id.equalsExp(borrowedItems.transactionId)),
          ])
                ..where(borrowedItems.customerNameText.equals(nama) &
                    borrowedItems.fullyReturnedAt.isNull() &
                    transactions.status.isNotValue('void')))
              .get())
            .map((r) => r.readTable(borrowedItems))
            .toList();

    // Pre-order: pelanggan TERDAFTAR (id terisi) dicocokkan MURNI lewat
    // `customerId` (Item 58 — dua pelanggan beda id namanya bisa sama,
    // JANGAN OR dgn nama), ad-hoc tetap lewat nama (satu-satunya identitas
    // yg tersedia utk kasus itu). + JOIN produk supaya baris cart bar bisa
    // menyebut nama produknya.
    final preorders = <PreorderPendingLine>[];
    if (id.isNotEmpty || nama.isNotEmpty) {
      final rows = await (select(preorderEntries).join([
        leftOuterJoin(
            products, products.id.equalsExp(preorderEntries.productId)),
      ])
            ..where((id.isNotEmpty
                    ? preorderEntries.customerId.equals(id)
                    : preorderEntries.customerName.equals(nama)) &
                preorderEntries.fulfilledAt.isNull() &
                preorderEntries.cancelledAt.isNull()))
          .get();
      for (final row in rows) {
        final e = row.readTable(preorderEntries);
        preorders.add((
          productName: row.readTableOrNull(products)?.name ?? e.productId,
          qty: e.qtyOrdered,
          depositQty: e.depositQty,
          id: e.id,
          transactionId: e.transactionId,
        ));
      }
    }

    return (
      titip: left.where((e) => e.jenis == 'titip').length,
      ketinggalan: left.where((e) => e.jenis == 'ketinggalan').length,
      pinjaman: borrowed.length,
      preorders: preorders,
    );
  }

  /// Diurut PALING LAMA MENUNGGU dulu (FIFO), sesuai rancangan dashboard.
  ///
  /// Item 60 — mode default (dashboard, `includeCollected: false`) ikut
  /// JOIN & mengecualikan nota yang sudah di-void (lihat dok
  /// `getLaciMejaPending`). Mode `includeCollected: true` (riwayat penuh,
  /// `riwayat_laci_meja_screen.dart`) SENGAJA TIDAK ikut filter void — nota
  /// adalah bukti historis permanen, pola sama `getBorrowedForTransaction`.
  Stream<List<LeftBehindItem>> watchLeftBehindItems(
      {bool includeCollected = false}) {
    if (includeCollected) {
      return (select(leftBehindItems)
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();
    }
    final q = select(leftBehindItems).join([
      innerJoin(transactions,
          transactions.id.equalsExp(leftBehindItems.transactionId)),
    ])
      ..where(leftBehindItems.collectedAt.isNull() &
          transactions.status.isNotValue('void'))
      ..orderBy([OrderingTerm.asc(leftBehindItems.createdAt)]);
    return q.watch().map(
        (rows) => rows.map((r) => r.readTable(leftBehindItems)).toList());
  }

  /// Tandai SELESAI seluruhnya. Tetap mencatat baris log (PLAN.md Item 54)
  /// supaya "ambil semua" ikut muncul di riwayat & log global — [sisaQty]
  /// adalah jumlah yang berpindah pada momen ini (null kalau qty entri
  /// memang tidak tercatat, log dicatat dgn qty 0).
  Future<void> markLeftBehindCollected(String id,
      {bool locallyModified = false,
      double? sisaQty,
      String? eventId,
      String? deviceCode}) async {
    await recordLaciMejaEvent(
      id: eventId ?? '$id-${DateTime.now().microsecondsSinceEpoch}',
      entityType: 'titip',
      entryId: id,
      aksi: 'ambil',
      qty: sisaQty ?? 0,
      deviceCode: deviceCode,
      locallyModified: locallyModified,
    );
    await (update(leftBehindItems)..where((t) => t.id.equals(id))).write(
      LeftBehindItemsCompanion(
        collectedAt: Value(DateTime.now()),
        locallyModified: Value(locallyModified),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ── Pinjaman Barang ──

  Future<void> addBorrowedItem({
    required String id,
    required String transactionId,
    required String itemName,
    required double qty,
    String? transactionItemId,
    String? customerId,
    String? customerNameText,
    String? note,
    bool locallyModified = false,
  }) =>
      into(borrowedItems).insert(BorrowedItemsCompanion.insert(
        id: id,
        transactionId: transactionId,
        itemName: itemName,
        qty: qty,
        transactionItemId: Value(transactionItemId),
        customerId: Value(customerId),
        customerNameText: Value(customerNameText),
        note: Value(note),
        locallyModified: Value(locallyModified),
      ));

  /// Kartu yang disematkan (`pinned`) naik ke atas, sisanya tetap FIFO
  /// `createdAt` seperti kategori Laci Meja lain.
  /// Item 60 — sama pola `watchLeftBehindItems`: mode default kecualikan
  /// nota void, mode `includeFullyReturned: true` (riwayat) tidak difilter.
  Stream<List<BorrowedItem>> watchBorrowedItems(
      {bool includeFullyReturned = false}) {
    if (includeFullyReturned) {
      return (select(borrowedItems)
            ..orderBy([
              (t) => OrderingTerm.desc(t.pinned),
              (t) => OrderingTerm.asc(t.createdAt),
            ]))
          .watch();
    }
    final q = select(borrowedItems).join([
      innerJoin(transactions,
          transactions.id.equalsExp(borrowedItems.transactionId)),
    ])
      ..where(borrowedItems.fullyReturnedAt.isNull() &
          transactions.status.isNotValue('void'))
      ..orderBy([
        OrderingTerm.desc(borrowedItems.pinned),
        OrderingTerm.asc(borrowedItems.createdAt),
      ]);
    return q
        .watch()
        .map((rows) => rows.map((r) => r.readTable(borrowedItems)).toList());
  }

  /// [qtyReturnedDelta] ditambahkan ke `qtyReturned` yang sudah ada (bisa
  /// kembali sebagian bertahap). `fullyReturnedAt` di-set otomatis begitu
  /// total yang kembali >= qty yang dipinjam.
  ///
  /// PLAN.md Item 54: tiap pengembalian sekarang JUGA menulis baris log, dan
  /// `qtyReturned` DIHITUNG ULANG dari log (bukan `+= delta` spt dulu) —
  /// dengan begitu kolom itu jadi cache murni dari satu sumber kebenaran,
  /// tidak bisa menyimpang dari riwayat yang ditampilkan. Migrasi v33 sudah
  /// mem-backfill akumulasi lama jadi satu baris log historis, jadi hasil
  /// hitung ulangnya sama dgn nilai sebelumnya utk data lama.
  Future<void> returnBorrowedItemQty(String id, double qtyReturnedDelta,
      {bool locallyModified = false,
      String? eventId,
      String? deviceCode}) async {
    final row = await (select(borrowedItems)..where((t) => t.id.equals(id)))
        .getSingle();
    await recordLaciMejaEvent(
      id: eventId ?? '$id-${DateTime.now().microsecondsSinceEpoch}',
      entityType: 'pinjaman',
      entryId: id,
      aksi: 'kembali',
      qty: qtyReturnedDelta,
      deviceCode: deviceCode,
      locallyModified: locallyModified,
    );
    final newReturned = (await getLaciMejaTakenQty([id]))[id] ?? 0;
    await (update(borrowedItems)..where((t) => t.id.equals(id))).write(
      BorrowedItemsCompanion(
        qtyReturned: Value(newReturned),
        fullyReturnedAt: Value(newReturned >= row.qty ? DateTime.now() : null),
        locallyModified: Value(locallyModified),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ── Pre-order ──

  Future<void> addPreorderEntry({
    required String id,
    required String productId,
    required String productUnitId,
    required String customerName,
    required double qtyOrdered,
    String? transactionId,
    String? customerId,
    String? phone,
    double depositQty = 0,
    bool paid = false,
    String? note,
    bool locallyModified = false,
    // Susulan (permintaan user) — lihat dok kolom di
    // `PreorderEntries.transactionItemId`. Diisi pemanggil checkout
    // (payment_screen.dart) yang tahu persis id baris nota terkait;
    // null aman utk pre-order titip wadah tanpa membeli apa pun.
    String? transactionItemId,
  }) =>
      into(preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: id,
        productId: productId,
        productUnitId: productUnitId,
        customerName: customerName,
        qtyOrdered: qtyOrdered,
        transactionId: Value(transactionId),
        customerId: Value(customerId),
        phone: Value(phone),
        depositQty: Value(depositQty),
        paid: Value(paid),
        note: Value(note),
        locallyModified: Value(locallyModified),
        transactionItemId: Value(transactionItemId),
      ));

  /// FIFO MURNI berdasar `createdAt` — `paid` HANYA informatif, TIDAK PERNAH
  /// ikut menentukan urutan (aturan bisnis Item 52, jangan diubah).
  Stream<List<PreorderEntry>> watchPreorderEntries(
          {String? productId, bool includeClosed = false}) =>
      (select(preorderEntries)
            ..where((t) {
              final open = includeClosed
                  ? const Constant(true)
                  : t.fulfilledAt.isNull() & t.cancelledAt.isNull();
              return productId == null
                  ? open
                  : open & t.productId.equals(productId);
            })
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();

  /// Penuhi SELURUH sisa sekaligus — pelengkap [fulfillPreorderQty] utk kasus
  /// paling umum. Sisa yang belum tercatat di log ikut ditulis sbg satu baris
  /// 'penuhi' supaya riwayatnya tidak bolong.
  ///
  /// Item 59 — barang baru benar² keluar dari stok toko SAAT ini (bukan saat
  /// DP dibayar `collectPreorderDeposit`, uang bisa masuk duluan tapi barang
  /// belum pindah tangan). `qtyChange` cuma [sisa] yang BELUM pernah terpotong
  /// oleh pemenuhan sebagian sebelumnya (lihat dok `getLaciMejaTakenQty`) —
  /// kalau `fulfillPreorderQty` sudah pernah dipanggil utk entri ini, sisanya
  /// tidak dobel-hitung. Konsisten dgn checkout normal (`recordSale`), TIDAK
  /// ada guard stok negatif di sini — app ini secara umum mengizinkan stok
  /// jadi negatif saat keluar (checkout normal pun tidak block).
  Future<void> fulfillPreorderEntry(String id,
      {bool locallyModified = false,
      String? eventId,
      String? deviceCode}) async {
    return transaction(() async {
      final row = await (select(preorderEntries)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      final taken = (await getLaciMejaTakenQty([id]))[id] ?? 0;
      final sisa = row.qtyOrdered - taken;
      final now = DateTime.now();
      await recordLaciMejaEvent(
        id: eventId ?? '$id-${now.microsecondsSinceEpoch}',
        entityType: 'preorder',
        entryId: id,
        aksi: 'penuhi',
        qty: sisa > 0 ? sisa : 0,
        deviceCode: deviceCode,
        locallyModified: locallyModified,
      );
      if (sisa > 0) {
        await _appendStock(
          productUnitId: row.productUnitId,
          qtyChange: -sisa,
          type: 'preorder_fulfill',
          referenceId: id,
          kasirId: deviceCode,
          note: 'Pre-order dipenuhi: ${row.customerName}',
          now: now,
        );
      }
      await (update(preorderEntries)..where((t) => t.id.equals(id))).write(
        PreorderEntriesCompanion(
          fulfilledAt: Value(now),
          locallyModified: Value(locallyModified),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Batalkan pre-order. Baris log `aksi = 'batal'` qty-nya 0 — pembatalan
  /// menutup sisa TANPA ada barang berpindah (lihat dok `LaciMejaEvents`),
  /// jadi tidak boleh ikut terhitung sbg "sudah dipenuhi".
  Future<void> cancelPreorderEntry(String id,
      {bool locallyModified = false,
      String? eventId,
      String? deviceCode}) async {
    await recordLaciMejaEvent(
      id: eventId ?? '$id-${DateTime.now().microsecondsSinceEpoch}',
      entityType: 'preorder',
      entryId: id,
      aksi: 'batal',
      deviceCode: deviceCode,
      locallyModified: locallyModified,
    );
    await (update(preorderEntries)..where((t) => t.id.equals(id))).write(
      PreorderEntriesCompanion(
        cancelledAt: Value(DateTime.now()),
        locallyModified: Value(locallyModified),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ── Edit atribut entri Laci Meja (permintaan user) ──
  //
  // Alasan fitur ini ada: sebelumnya entri yang SALAH input hanya bisa
  // "diperbaiki" dengan memenuhi/mengambilnya lalu membuat entri baru —
  // yang berarti riwayat audit mencatat kejadian yang TIDAK PERNAH TERJADI
  // secara fisik. Mengedit di tempat menjaga log tetap jujur.
  //
  // Aturan bersama ketiga fungsi di bawah:
  //  * `lastEditedAt` distempel HANYA di sini (bukan di aksi ambil/kembali/
  //    penuhi/pin) — itulah gunanya kolom ini terpisah dari `updatedAt`.
  //  * Tiap edit menulis satu baris log `aksi = 'edit'` (qty 0, tidak ada
  //    barang berpindah) berisi ringkasan perubahan, supaya riwayat tetap
  //    utuh menjelaskan kenapa angkanya berubah.
  //  * Pemanggil WAJIB sudah memastikan qty baru >= qty yang sudah terlanjur
  //    diambil/dikembalikan/dipenuhi (dihitung dari log) — kalau tidak, sisa
  //    entri jadi negatif dan ledger barang fisiknya ngawur.

  Future<void> editLeftBehindItem(
    String id, {
    String? customerNameText,
    double? qty,
    String? note,
    String? changeSummary,
    bool locallyModified = false,
    String? eventId,
    String? deviceCode,
  }) async {
    await (update(leftBehindItems)..where((t) => t.id.equals(id))).write(
      LeftBehindItemsCompanion(
        customerNameText: Value(customerNameText),
        qty: qty == null ? const Value.absent() : Value(qty),
        note: Value(note),
        lastEditedAt: Value(DateTime.now()),
        locallyModified: Value(locallyModified),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await recordLaciMejaEvent(
      id: eventId ?? '$id-${DateTime.now().microsecondsSinceEpoch}',
      entityType: 'titip',
      entryId: id,
      aksi: 'edit',
      note: changeSummary,
      deviceCode: deviceCode,
      locallyModified: locallyModified,
    );
  }

  Future<void> editBorrowedItem(
    String id, {
    String? customerNameText,
    double? qty,
    String? note,
    String? changeSummary,
    bool locallyModified = false,
    String? eventId,
    String? deviceCode,
  }) async {
    await (update(borrowedItems)..where((t) => t.id.equals(id))).write(
      BorrowedItemsCompanion(
        customerNameText: Value(customerNameText),
        qty: qty == null ? const Value.absent() : Value(qty),
        note: Value(note),
        lastEditedAt: Value(DateTime.now()),
        locallyModified: Value(locallyModified),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Menurunkan qty bisa membuat jumlah yang sudah kembali PERSIS menutup
    // pinjaman — status "sudah kembali semua" harus ikut menyesuaikan,
    // begitu juga sebaliknya kalau qty dinaikkan.
    if (qty != null) {
      final returned = (await getLaciMejaTakenQty([id]))[id] ?? 0;
      await (update(borrowedItems)..where((t) => t.id.equals(id))).write(
        BorrowedItemsCompanion(
          fullyReturnedAt: Value(returned >= qty ? DateTime.now() : null),
        ),
      );
    }
    await recordLaciMejaEvent(
      id: eventId ?? '$id-${DateTime.now().microsecondsSinceEpoch}',
      entityType: 'pinjaman',
      entryId: id,
      aksi: 'edit',
      note: changeSummary,
      deviceCode: deviceCode,
      locallyModified: locallyModified,
    );
  }

  Future<void> editPreorderEntry(
    String id, {
    String? customerName,
    String? phone,
    double? qtyOrdered,
    double? depositQty,
    String? note,
    String? changeSummary,
    bool locallyModified = false,
    String? eventId,
    String? deviceCode,
  }) async {
    await (update(preorderEntries)..where((t) => t.id.equals(id))).write(
      PreorderEntriesCompanion(
        customerName:
            customerName == null ? const Value.absent() : Value(customerName),
        phone: Value(phone),
        qtyOrdered:
            qtyOrdered == null ? const Value.absent() : Value(qtyOrdered),
        depositQty:
            depositQty == null ? const Value.absent() : Value(depositQty),
        note: Value(note),
        lastEditedAt: Value(DateTime.now()),
        locallyModified: Value(locallyModified),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await recordLaciMejaEvent(
      id: eventId ?? '$id-${DateTime.now().microsecondsSinceEpoch}',
      entityType: 'preorder',
      entryId: id,
      aksi: 'edit',
      note: changeSummary,
      deviceCode: deviceCode,
      locallyModified: locallyModified,
    );
  }

  /// Nominal DP/jaminan pre-order yang MASIH harus dikumpulkan — baris nota
  /// yang harganya dikunci Rp 0 saat checkout (`_effectivePrice = 0` di
  /// `item_entry_sheet.dart` saat `isPreorder && !dpPaid`). Null kalau tidak
  /// ada apa pun yg perlu dikumpulkan: entri tidak tertaut ke baris nota
  /// (`transactionItemId` null — mis. entri lama sebelum kolom ini ada,
  /// atau titip wadah tanpa membeli apa pun), baris nota sudah dihapus, atau
  /// harganya sudah bukan Rp 0 lagi (sudah pernah dikumpulkan).
  Future<int?> getPreorderDepositOwed(String preorderEntryId) async {
    final entry = await (select(preorderEntries)
          ..where((t) => t.id.equals(preorderEntryId)))
        .getSingleOrNull();
    final itemId = entry?.transactionItemId;
    if (entry == null || itemId == null) return null;
    final item = await (select(transactionItems)
          ..where((t) => t.id.equals(itemId)))
        .getSingleOrNull();
    if (item == null) return null;
    final owed = (item.originalPrice * item.qty).round() - item.subtotal;
    return owed > 0 ? owed : null;
  }

  /// Kumpulkan pembayaran DP/jaminan pre-order yang tadinya dikunci Rp 0
  /// saat checkout — dipanggil dari dashboard Laci Meja saat pre-order
  /// akhirnya DIPENUHI & pelanggan bayar (permintaan user).
  ///
  /// Menaikkan `priceAtSale`/`subtotal` baris nota TERTAUT (lihat dok
  /// `PreorderEntries.transactionItemId`) dari Rp 0 ke `originalPrice` —
  /// SATU-SATUNYA kasus baris nota LUNAS boleh naik nilainya, beda dari
  /// `editPaidTransactionItem` yang SENGAJA cuma izinkan turun (baris ITU
  /// utk koreksi umum yang berisiko disalahgunakan menambah tagihan nota
  /// yang sudah genuinely settled — baris pre-order INI beda: dia memang
  /// belum PERNAH benar-benar dibayar sejak awal, meski status nota
  /// globalnya sempat "lunas" krn item lain menutup total). Lalu:
  ///   1. Rekonsiliasi total/status nota (`_reconcileTransactionTotals`,
  ///      pola sama `addItemsToTransaction`) — nota bisa balik jadi
  ///      "kurang_bayar" utk selisihnya, KONSISTEN dgn perbaikan "Kembali/
  ///      Sisa bisa muncul bersamaan" sesi sebelumnya.
  ///   2. Catat pembayaran via `addPaymentToTransaction` — muncul otomatis
  ///      di "Riwayat Pembayaran" struk (permintaan user), tanpa jalur baru.
  ///   3. Tandai `preorderEntries.paid = true` — dashboard Laci Meja
  ///      berhenti menampilkan "Tempo" utk entri ini.
  ///   4. Catat event `aksi: 'bayar'` (`qty: 0` SENGAJA — supaya TIDAK ikut
  ///      kehitung `getLaciMejaTakenQty`/progress bar, nominalnya di
  ///      `note`) — muncul di kartu "riwayat" pre-order di nota (permintaan
  ///      user).
  ///
  /// Return nominal yang benar² terkumpul (owed SAAT dipanggil, BUKAN
  /// [amount] mentah — bisa beda kalau kasir bayar lebih/kurang), atau null
  /// kalau tidak ada apa pun yg perlu dikumpulkan (lihat
  /// [getPreorderDepositOwed]) — pemanggil UI menafsirkan null sbg
  /// "sudah beres, tidak perlu sheet pembayaran".
  Future<int?> collectPreorderDeposit({
    required String preorderEntryId,
    required int amount,
    required String method,
    String? methodName,
    required String kasirId,
  }) async {
    return transaction(() async {
      final entry = await (select(preorderEntries)
            ..where((t) => t.id.equals(preorderEntryId)))
          .getSingleOrNull();
      final itemId = entry?.transactionItemId;
      final txId = entry?.transactionId;
      if (entry == null || itemId == null || txId == null) return null;
      final item = await (select(transactionItems)
            ..where((t) => t.id.equals(itemId)))
          .getSingleOrNull();
      if (item == null) return null;
      final newSubtotal = (item.originalPrice * item.qty).round();
      final owed = newSubtotal - item.subtotal;
      if (owed <= 0) return null;

      await (update(transactionItems)..where((t) => t.id.equals(item.id)))
          .write(TransactionItemsCompanion(
        priceAtSale: Value(item.originalPrice),
        subtotal: Value(newSubtotal),
      ));
      await _reconcileTransactionTotals(txId);
      await addPaymentToTransaction(
        txId: txId,
        amount: amount,
        method: method,
        methodName: methodName,
        kasirId: kasirId,
        note: _kPreorderDepositNote,
      );

      final now = DateTime.now();
      await (update(preorderEntries)
            ..where((t) => t.id.equals(preorderEntryId)))
          .write(PreorderEntriesCompanion(
        paid: const Value(true),
        updatedAt: Value(now),
      ));
      await recordLaciMejaEvent(
        id: '$preorderEntryId-bayar-${now.microsecondsSinceEpoch}',
        entityType: 'preorder',
        entryId: preorderEntryId,
        aksi: 'bayar',
        qty: 0,
        note: 'DP dibayar ${_fmtRupiahPlain(amount)}',
        deviceCode: kasirId,
      );
      return owed;
    });
  }

  static String _fmtRupiahPlain(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return 'Rp $buf';
  }

  /// Sematkan/lepas sematan sekumpulan baris pinjaman sekaligus. UI
  /// mengelompokkan kartu pinjaman PER PELANGGAN, jadi satu ketukan pin
  /// mengenai semua baris dalam grup itu — kalau tidak, kartu bisa "setengah
  /// tersemat" dan urutannya jadi tidak bisa dijelaskan ke user.
  ///
  /// TIDAK menyentuh `lastEditedAt`: menyematkan bukan mengubah isi entri.
  Future<void> setBorrowedPinned(List<String> ids, bool pinned,
      {bool locallyModified = false}) async {
    if (ids.isEmpty) return;
    await (update(borrowedItems)..where((t) => t.id.isIn(ids))).write(
      BorrowedItemsCompanion(
        pinned: Value(pinned),
        locallyModified: Value(locallyModified),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ── Log kejadian Laci Meja (PLAN.md Item 54) ──
  //
  // Log ini SUMBER KEBENARAN utk "sudah berapa yang diambil/kembali/dipenuhi".
  // Kolom `borrowedItems.qtyReturned` dipertahankan sbg CACHE (banyak pembaca
  // lama bergantung padanya) dan SELALU dihitung ulang dari log — lihat
  // [returnBorrowedItemQty]. Titip/ketinggalan & pre-order TIDAK punya kolom
  // akumulator sejenis; sisanya dihitung on-the-fly lewat [getLaciMejaTakenQty]
  // supaya tidak ada cache kedua yang bisa menyimpang.

  /// Catat satu kejadian. Tidak pernah meng-update baris lama (lihat dok
  /// `LaciMejaEvents`) — pembatalan pun baris baru.
  Future<void> recordLaciMejaEvent({
    required String id,
    required String entityType,
    required String entryId,
    required String aksi,
    double qty = 0,
    String? note,
    String? deviceCode,
    bool locallyModified = false,
  }) =>
      into(laciMejaEvents).insert(LaciMejaEventsCompanion.insert(
        id: id,
        entityType: entityType,
        entryId: entryId,
        aksi: aksi,
        qty: Value(qty),
        note: Value(note),
        deviceCode: Value(deviceCode),
        locallyModified: Value(locallyModified),
      ));

  /// Total qty yang SUDAH terproses per entri (`aksi = 'batal'` tidak ikut —
  /// pembatalan menutup sisa tanpa ada barang berpindah). Satu query agregat
  /// utk banyak entri sekaligus, bukan N+1.
  Future<Map<String, double>> getLaciMejaTakenQty(List<String> entryIds) async {
    if (entryIds.isEmpty) return {};
    final rows = await (selectOnly(laciMejaEvents)
          ..addColumns([laciMejaEvents.entryId, laciMejaEvents.qty.sum()])
          ..where(laciMejaEvents.entryId.isIn(entryIds) &
              laciMejaEvents.aksi.equals('batal').not())
          ..groupBy([laciMejaEvents.entryId]))
        .get();
    return {
      for (final r in rows)
        r.read(laciMejaEvents.entryId)!: r.read(laciMejaEvents.qty.sum()) ?? 0,
    };
  }

  /// Riwayat per entri (terlama dulu, spt Riwayat Pembayaran) — dipakai kartu
  /// riwayat di layar nota.
  Future<Map<String, List<LaciMejaEvent>>> getLaciMejaEventsForEntries(
      List<String> entryIds) async {
    if (entryIds.isEmpty) return {};
    final rows = await (select(laciMejaEvents)
          ..where((t) => t.entryId.isIn(entryIds))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final out = <String, List<LaciMejaEvent>>{};
    for (final r in rows) {
      (out[r.entryId] ??= []).add(r);
    }
    return out;
  }

  /// Baris `PreorderEntries` milik satu nota — pelengkap
  /// [getBorrowedForTransaction]/[getLeftBehindWithoutLineForTransaction]
  /// supaya layar nota bisa menampilkan kartu riwayat pre-order juga
  /// (sebelumnya pre-order satu-satunya kategori tanpa kartu di nota).
  ///
  /// Sengaja TIDAK memfilter `fulfilledAt`/`cancelledAt`, alasan identik
  /// [getBorrowedForTransaction]: nota adalah bukti historis permanen.
  Future<List<PreorderEntry>> getPreorderForTransaction(String transactionId) =>
      (select(preorderEntries)
            ..where((t) => t.transactionId.equals(transactionId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Log gabungan ketiga kategori utk layar "Riwayat" Laci Meja — sudah
  /// diperkaya nama barang & nama pelanggan supaya layar tidak perlu N+1.
  ///
  /// Nama pelanggan dibaca HIDUP dari nota (pola sama
  /// [getCustomerNamesForTransactions]) lalu jatuh ke salinan beku entri —
  /// biar konsisten dgn dashboard, yang namanya juga ikut nota.
  Stream<List<LaciMejaEventView>> watchLaciMejaEventLog({int limit = 300}) {
    return customSelect(
      'SELECT e.id AS id, e.entity_type AS entity_type, e.entry_id AS entry_id, '
      '  e.aksi AS aksi, e.qty AS qty, e.note AS note, '
      '  e.created_at AS created_at, '
      '  COALESCE(l.item_name, b.item_name, pr.name, p.product_id) AS item_name, '
      '  COALESCE('
      '    CASE WHEN t.customer_id IS NOT NULL THEN c.name ELSE t.customer_name END, '
      '    l.customer_name_text, b.customer_name_text, p.customer_name'
      '  ) AS customer_name, '
      '  COALESCE(l.transaction_id, b.transaction_id, p.transaction_id) AS transaction_id '
      'FROM laci_meja_events e '
      "LEFT JOIN left_behind_items l ON e.entity_type = 'titip' AND l.id = e.entry_id "
      "LEFT JOIN borrowed_items b ON e.entity_type = 'pinjaman' AND b.id = e.entry_id "
      "LEFT JOIN preorder_entries p ON e.entity_type = 'preorder' AND p.id = e.entry_id "
      'LEFT JOIN products pr ON pr.id = p.product_id '
      'LEFT JOIN transactions t ON t.id = COALESCE(l.transaction_id, b.transaction_id, p.transaction_id) '
      'LEFT JOIN customers c ON c.id = t.customer_id '
      'ORDER BY e.created_at DESC LIMIT $limit',
      readsFrom: {
        laciMejaEvents,
        leftBehindItems,
        borrowedItems,
        preorderEntries,
        products,
        transactions,
        customers,
      },
    ).watch().map((rows) => rows
        .map((r) => (
              id: r.data['id'] as String,
              entityType: r.data['entity_type'] as String,
              entryId: r.data['entry_id'] as String,
              aksi: r.data['aksi'] as String,
              qty: (r.data['qty'] as num?)?.toDouble() ?? 0,
              note: r.data['note'] as String?,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                  (r.data['created_at'] as int) * 1000),
              itemName: (r.data['item_name'] as String?) ?? '-',
              customerName: r.data['customer_name'] as String?,
              transactionId: r.data['transaction_id'] as String?,
            ))
        .toList());
  }

  /// Ambil SEBAGIAN barang titip/ketinggalan. [total] = jumlah yang seharusnya
  /// ada (null utk entri lama yang qty-nya tidak tercatat) — begitu akumulasi
  /// log mencapai [total], entri ditandai selesai (`collectedAt`). Kalau
  /// [total] null, satu pengambilan langsung dianggap menutup entri (perilaku
  /// lama, tidak ada angka yang bisa dijadikan acuan sisa).
  Future<void> collectLeftBehindQty(
    String id,
    double qtyTaken, {
    double? total,
    String? eventId,
    String? deviceCode,
    bool locallyModified = false,
  }) async {
    await recordLaciMejaEvent(
      id: eventId ?? '$id-${DateTime.now().microsecondsSinceEpoch}',
      entityType: 'titip',
      entryId: id,
      aksi: 'ambil',
      qty: qtyTaken,
      deviceCode: deviceCode,
      locallyModified: locallyModified,
    );
    final taken = (await getLaciMejaTakenQty([id]))[id] ?? 0;
    final done = total == null || taken >= total;
    await (update(leftBehindItems)..where((t) => t.id.equals(id))).write(
      LeftBehindItemsCompanion(
        collectedAt: Value(done ? DateTime.now() : null),
        locallyModified: Value(locallyModified),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Penuhi SEBAGIAN pre-order. Selesai (`fulfilledAt`) begitu akumulasi log
  /// mencapai `qtyOrdered`.
  ///
  /// Item 59 — [qtyFulfilled] dipotong dari stok toko SAAT INI (barang benar²
  /// diserahkan), bukan saat DP dibayar. Type ledger `preorder_fulfill`
  /// (terpisah dari `sale` biasa) supaya audit trail jelas: ini realisasi
  /// fisik pre-order, bukan checkout baru. Tanpa guard stok negatif — samakan
  /// dgn checkout normal yang juga tidak block stok kurang.
  Future<void> fulfillPreorderQty(
    String id,
    double qtyFulfilled, {
    String? eventId,
    String? deviceCode,
    bool locallyModified = false,
  }) async {
    return transaction(() async {
      final row = await (select(preorderEntries)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      final now = DateTime.now();
      await recordLaciMejaEvent(
        id: eventId ?? '$id-${now.microsecondsSinceEpoch}',
        entityType: 'preorder',
        entryId: id,
        aksi: 'penuhi',
        qty: qtyFulfilled,
        deviceCode: deviceCode,
        locallyModified: locallyModified,
      );
      if (qtyFulfilled > 0) {
        await _appendStock(
          productUnitId: row.productUnitId,
          qtyChange: -qtyFulfilled,
          type: 'preorder_fulfill',
          referenceId: id,
          kasirId: deviceCode,
          note: 'Pre-order dipenuhi: ${row.customerName}',
          now: now,
        );
      }
      final taken = (await getLaciMejaTakenQty([id]))[id] ?? 0;
      await (update(preorderEntries)..where((t) => t.id.equals(id))).write(
        PreorderEntriesCompanion(
          fulfilledAt: Value(taken >= row.qtyOrdered ? now : null),
          locallyModified: Value(locallyModified),
          updatedAt: Value(now),
        ),
      );
    });
  }

  /// Badge gabungan 3 kategori utk ikon Kasir (bottom nav) & kartu dashboard.
  /// Query gabungan tunggal (bukan 3 stream dikombinasi) supaya tidak perlu
  /// dependency tambahan (mis. rxdart) hanya utk menjumlahkan count — drift
  /// sudah mendukung `.watch()` di atas raw SQL asal `readsFrom` diisi
  /// eksplisit dgn tabel yang dibaca.
  /// Item 60 — `left_behind_items`/`borrowed_items` ikut JOIN
  /// `transactions` & kecualikan nota void (lihat dok `getLaciMejaPending`),
  /// `readsFrom` ditambah `transactions` supaya badge ikut refresh saat
  /// status nota berubah (mis. baru saja di-void).
  Stream<int> watchLaciMejaOpenCount() {
    return customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM left_behind_items li '
      'JOIN transactions t ON t.id = li.transaction_id '
      'WHERE li.collected_at IS NULL AND t.status != \'void\') + '
      '(SELECT COUNT(*) FROM borrowed_items bi '
      'JOIN transactions t ON t.id = bi.transaction_id '
      'WHERE bi.fully_returned_at IS NULL AND t.status != \'void\') + '
      '(SELECT COUNT(*) FROM preorder_entries '
      'WHERE fulfilled_at IS NULL AND cancelled_at IS NULL) AS cnt',
      readsFrom: {leftBehindItems, borrowedItems, preorderEntries, transactions},
    ).watchSingle().map((r) => r.data['cnt'] as int);
  }

  /// Kumpulkan baris 3 tabel Laci Meja yang ditandai `locallyModified` di
  /// device ini — dikirim sbg "usulan" ke owner via sync (pola Item 40,
  /// tapi PARALEL: tidak menyentuh `dumpLocalProposals`/`applyProductProposals`
  /// milik produk sama sekali, supaya alur usulan produk yang sudah matang
  /// tidak ikut berisiko).
  Future<Map<String, List<Map<String, Object?>>>>
      dumpLaciMejaProposals() async {
    final result = <String, List<Map<String, Object?>>>{};
    for (final t in const [
      'left_behind_items',
      'borrowed_items',
      'preorder_entries',
      // Log kejadian (PLAN.md Item 54) — ikut jalur usulan yang SAMA, sesuai
      // keputusan user (pengambilan dari HP kasir tetap perlu persetujuan
      // owner). Ditaruh TERAKHIR supaya entri induknya diterapkan lebih dulu
      // dalam satu batch — lihat guard `entry_id` di applyLaciMejaProposals.
      'laci_meja_events',
    ]) {
      final rows = await customSelect(
        'SELECT * FROM "$t" WHERE locally_modified = 1',
      ).get();
      if (rows.isNotEmpty) result[t] = rows.map((r) => r.data).toList();
    }
    return result;
  }

  /// Buang baris Laci Meja (left_behind_items/borrowed_items/preorder_entries)
  /// dari usulan [rows] (payload `dumpLaciMejaProposals` klien) yang isinya
  /// SUDAH IDENTIK dgn data HOST saat ini — dipanggil host SEBELUM baris itu
  /// masuk antrian `_pendingLaciMejaProposals`. Pola SAMA PERSIS dgn
  /// [filterUnchangedProposals] (produk, Item 40) tapi lebih sederhana
  /// (satu baris = satu record datar, tanpa nested tier/unit).
  ///
  /// Bug nyata dilaporkan user: pre-order yang sudah "Dipenuhi" TETAP
  /// terus-menerus muncul sbg usulan baru tiap sync walau ownernya SUDAH
  /// menerapkan usulan itu sebelumnya. Akar: `locally_modified` di klien
  /// TIDAK PERNAH direset manual — cuma direset kalau baris resmi dari host
  /// (locally_modified=0) berhasil ter-merge BALIK ke klien lewat
  /// `mergeRows` (host->klien). Sebelum itu terjadi (mis. owner belum
  /// sempat approve, atau klien sync lagi SEBELUM sempat menerima baris
  /// balik), baris yang SAMA terus dikirim ulang sbg "usulan baru" —
  /// owner melihat pre-order yang sudah "Dipenuhi" seolah masih perlu
  /// ditinjau. Fix: bandingkan tiap baris usulan thd baris HOST saat ini
  /// per-kolom (kecuali `locally_modified`/`updated_at`, yang MEMANG selalu
  /// beda antar device) — kalau identik, baris itu DIBUANG dari usulan
  /// (host sudah tahu, tidak ada apa pun yang perlu diputuskan owner).
  /// Baris yang belum ADA di host (pre-order/titip/pinjaman baru) SELALU
  /// lolos filter (tidak ada pembanding).
  Future<Map<String, List<Map<String, Object?>>>>
      filterUnchangedLaciMejaProposals(
          Map<String, List<Map<String, Object?>>> rows) async {
    final result = <String, List<Map<String, Object?>>>{};
    for (final entry in rows.entries) {
      final table = entry.key;
      final kept = <Map<String, Object?>>[];
      for (final row in entry.value) {
        final id = row['id'];
        if (id is! String) {
          kept.add(row);
          continue;
        }
        final existingRows = await customSelect(
          'SELECT * FROM "$table" WHERE id = ?',
          variables: [Variable.withString(id)],
        ).get();
        if (existingRows.isEmpty) {
          kept.add(row); // Baris baru — tidak ada pembanding di host.
          continue;
        }
        final existing = existingRows.single.data;
        var changed = false;
        for (final key in row.keys) {
          if (key == 'locally_modified' || key == 'updated_at') continue;
          if (existing[key] != row[key]) {
            changed = true;
            break;
          }
        }
        if (changed) kept.add(row);
      }
      if (kept.isNotEmpty) result[table] = kept;
    }
    return result;
  }

  /// Label ringkas satu baris Laci Meja utk pesan "dilewati" — dipakai
  /// [applyLaciMejaProposals] saat baris gagal diterapkan (transaksi
  /// terkait belum tersinkron).
  String _laciMejaRowLabel(String table, Map<String, Object?> row) {
    switch (table) {
      case 'preorder_entries':
        return 'Pre-order "${row['customer_name'] ?? '?'}"';
      case 'borrowed_items':
      case 'left_behind_items':
        return '"${row['item_name'] ?? '?'}"';
      default:
        return table;
    }
  }

  /// Terapkan usulan Laci Meja yang DISETUJUI owner — [approvedIds] per
  /// tabel. `locallyModified` dipaksa false (host jadi sumber kebenaran),
  /// `updated_at` dicap ulang ke SAAT INI (sama alasan spt
  /// `applyProductProposals`: supaya baris ini lolos filter watermark
  /// `dumpSince` pada sync berikutnya, bukan macet tak pernah terkirim
  /// balik ke klien).
  ///
  /// Susulan (bug ditemukan user, `SqliteException FOREIGN KEY constraint
  /// failed` saat Terapkan): ketiga tabel Laci Meja (`left_behind_items`/
  /// `borrowed_items`/`preorder_entries`) punya kolom `transaction_id`
  /// yang ber-FK ke `transactions.id` — tapi antrian usulan Laci Meja ini
  /// SAMA SEKALI TERPISAH dari antrian sync kategori "Transaksi"
  /// (`LanSyncService.syncCategories`/`approveSync`), tidak ada jaminan
  /// urutan penerapan. Kalau owner menerapkan usulan Laci Meja SEBELUM
  /// transaksi terkaitnya sendiri tersinkron ke host, insert PASTI gagal
  /// FK — dan karena baris-baris lain sebelumnya sudah dieksekusi di
  /// `transaction()` yang SAMA, seluruh batch ikut rollback (bukan cuma
  /// baris yang bermasalah). Fix: cek existensi `transaction_id` di host
  /// SEBELUM insert per-baris — kalau belum ada, SKIP baris itu saja
  /// (lanjut ke baris lain, JANGAN gagalkan seluruh batch). Baris yang
  /// di-skip TETAP `locallyModified=1` di device asalnya (tidak disentuh
  /// di sini sama sekali), jadi otomatis diusulkan ulang sync berikutnya
  /// begitu transaksinya sendiri sudah masuk ke host — bukan hilang.
  Future<({int applied, List<String> skippedReasons})> applyLaciMejaProposals(
      Map<String, List<Map<String, Object?>>> proposals,
      Map<String, Set<String>> approvedIds) async {
    var count = 0;
    final skippedReasons = <String>[];
    // `customInsert` raw SQL TIDAK memberi tahu Drift tabel mana yang
    // berubah kecuali param `updates:` disertakan — tanpa ini `.watch()`
    // (mis. layar dashboard Laci Meja) tidak auto-refresh walau data DB
    // sudah benar (lihat gotcha yang sama di `mergeRows`/`restoreFromDump`).
    final tablesByName = {for (final t in allTables) t.entityName: t};
    await transaction(() async {
      for (final entry in proposals.entries) {
        final approved = approvedIds[entry.key] ?? const {};
        if (approved.isEmpty) continue;
        final localColumns =
            (await customSelect('PRAGMA table_info("${entry.key}")').get())
                .map((r) => r.data['name'] as String)
                .toSet();
        final table = tablesByName[entry.key];
        for (final row in entry.value) {
          if (!approved.contains(row['id'])) continue;
          var cleaned = Map<String, Object?>.from(row)
            ..removeWhere((k, _) => !localColumns.contains(k));
          if (cleaned.isEmpty) continue;

          final txId = cleaned['transaction_id'];
          if (txId is String && txId.isNotEmpty) {
            final found = await customSelect(
              'SELECT 1 FROM transactions WHERE id = ? LIMIT 1',
              variables: [Variable.withString(txId)],
            ).get();
            if (found.isEmpty) {
              skippedReasons.add(
                  '${_laciMejaRowLabel(entry.key, row)}: transaksi terkait belum tersinkron ke perangkat ini');
              continue;
            }
          }

          // Guard sejenis utk log kejadian: `entry_id` menunjuk baris di salah
          // satu dari 3 tabel induk (polimorfik, jadi TIDAK bisa FK fisik).
          // Kalau induknya belum ada di host, baris log ini akan jadi yatim
          // dan tampil tanpa nama barang di layar Riwayat — lewati saja,
          // `locally_modified`-nya tetap 1 di device asal jadi otomatis
          // diusulkan ulang sync berikutnya begitu induknya masuk.
          if (entry.key == 'laci_meja_events') {
            const parentTable = {
              'titip': 'left_behind_items',
              'pinjaman': 'borrowed_items',
              'preorder': 'preorder_entries',
            };
            final parent = parentTable[cleaned['entity_type']];
            final entryId = cleaned['entry_id'];
            if (parent == null || entryId is! String) continue;
            final found = await customSelect(
              'SELECT 1 FROM "$parent" WHERE id = ? LIMIT 1',
              variables: [Variable.withString(entryId)],
            ).get();
            if (found.isEmpty) {
              skippedReasons.add(
                  'Riwayat Laci Meja: entri terkait belum tersinkron ke perangkat ini');
              continue;
            }
          }

          // Audit sync pre-order (sesi 2 Sep 2026): `INSERT OR REPLACE` di
          // bawah menimpa SELURUH baris host dgn versi klien. Kalau owner
          // sudah MENUTUP entri di host (memenuhi/membatalkan pre-order,
          // ambil titipan, pinjaman kembali semua) SEBELUM menyetujui usulan
          // klien yang masih memuat versi TERBUKA (mis. klien mengedit qty
          // lebih dulu, `locally_modified=1`), persetujuan itu diam-diam
          // MEMBUKA KEMBALI entri yang sudah selesai — padahal event
          // 'penuhi'/'ambil'/'kembali'-nya tetap ada, jadi dashboard
          // menampilkan entri "terbuka" dgn sisa 0 yang tidak bisa ditutup
          // lagi lewat jalur normal. Status tutup bersifat SATU ARAH
          // (tidak ada jalur app yang mengosongkan kolom ini kembali) —
          // pertahankan nilai host kalau usulan masih null, pola sama dgn
          // `deleted_at` `expenses` di `mergeRows`. `qty_returned` (cache
          // dari log, lihat `returnBorrowedItemQty`) ikut dijaga: ambil
          // yang terbesar supaya cache tidak mundur.
          const closedColumns = {
            'preorder_entries': ['fulfilled_at', 'cancelled_at'],
            'left_behind_items': ['collected_at'],
            'borrowed_items': ['fully_returned_at'],
          };
          final guarded = closedColumns[entry.key];
          if (guarded != null) {
            final hostRow = await customSelect(
              'SELECT * FROM "${entry.key}" WHERE id = ? LIMIT 1',
              variables: [Variable.withString(cleaned['id'] as String)],
            ).getSingleOrNull();
            if (hostRow != null) {
              for (final col in guarded) {
                if (cleaned[col] == null && hostRow.data[col] != null) {
                  cleaned[col] = hostRow.data[col];
                }
              }
              final hostReturned = hostRow.data['qty_returned'];
              final incomingReturned = cleaned['qty_returned'];
              if (hostReturned is num &&
                  (incomingReturned is! num || incomingReturned < hostReturned)) {
                cleaned['qty_returned'] = hostReturned;
              }
            }
          }

          cleaned['locally_modified'] = 0;
          // `updated_at` HANYA dicap ulang kalau tabelnya memang punya kolom
          // itu — `laci_meja_events` tidak punya (baris log tidak pernah
          // di-update, deltanya by `created_at`). Tanpa cek ini, insert-nya
          // gagal "no such column".
          if (localColumns.contains('updated_at')) {
            cleaned['updated_at'] =
                DateTime.now().millisecondsSinceEpoch ~/ 1000;
          }
          // Item 57 — `laci_meja_events` tidak punya `updated_at` (baris log
          // tidak pernah di-update, `createdAt` = waktu kejadian fisik yang
          // tidak boleh diubah). `applied_at` dicap DI SINI, saat host
          // menyetujui, dipakai filter delta tambahan di `dumpSince` supaya
          // event ini dijamin lolos ke sync klien berikutnya kapan pun
          // disetujui (lihat dok kolom di `laci_meja_tables.dart`).
          if (entry.key == 'laci_meja_events' &&
              localColumns.contains('applied_at')) {
            cleaned['applied_at'] =
                DateTime.now().millisecondsSinceEpoch ~/ 1000;
          }
          final cols = cleaned.keys.map((k) => '"$k"').join(', ');
          final placeholders = cleaned.values.map((_) => '?').join(', ');
          await customInsert(
            'INSERT OR REPLACE INTO "${entry.key}" ($cols) VALUES ($placeholders)',
            variables: _rowToVars(cleaned),
            updates: table == null ? null : {table},
          );
          count++;
        }
      }
    });
    return (applied: count, skippedReasons: skippedReasons);
  }

  // ───────────────────────── Usulan Pelanggan ─────────────────────────
  //
  // Susulan (permintaan user) — pola SAMA PERSIS dgn Laci Meja di atas
  // (yang sendiri PARALEL dari usulan produk Item 40): `locallyModified`
  // di `customers`, UI yang memanggil create/update WAJIB set true kalau
  // device BUKAN owner (lihat `device.isOwner`). Sengaja 1 tabel saja
  // (bukan gabungan banyak tabel spt Laci Meja) — pelanggan tidak punya
  // sub-tabel terkait yang perlu ikut diusulkan.

  /// Set pelanggan sbg "diedit lokal" — dipanggil UI setelah simpan
  /// pelanggan (baru/ubah) di device yang BUKAN owner.
  Future<void> markCustomerLocallyModified(String customerId) async {
    await (update(customers)..where((t) => t.id.equals(customerId))).write(
      CustomersCompanion(
        locallyModified: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Kumpulkan baris `customers` yang ditandai `locallyModified` di device
  /// ini — dikirim sbg "usulan" ke owner via sync. TIDAK menghapus flag di
  /// sini (sama pola dgn `dumpLocalProposals` produk) — flag baru hilang
  /// otomatis saat baris ini ditimpa push resmi dari host.
  Future<List<Map<String, Object?>>> dumpLocalCustomerProposals() async {
    final rows = await customSelect(
      'SELECT * FROM "customers" WHERE locally_modified = 1',
    ).get();
    return rows.map((r) => r.data).toList();
  }

  /// Terapkan pelanggan yang DISETUJUI owner (subset [approvedIds] dari
  /// [rows]) ke tabel `customers` host. `locallyModified` DIPAKSA false
  /// (host jadi sumber kebenaran), `updated_at` dicap ulang ke SAAT INI
  /// (sama alasan spt `applyProductProposals`: supaya baris ini lolos
  /// filter watermark `dumpSince` pada sync berikutnya, bukan macet tak
  /// pernah terkirim balik ke klien).
  Future<int> applyCustomerProposals(
      List<Map<String, Object?>> rows, Set<String> approvedIds) async {
    if (approvedIds.isEmpty) return 0;
    var count = 0;
    final localColumns =
        (await customSelect('PRAGMA table_info("customers")').get())
            .map((r) => r.data['name'] as String)
            .toSet();
    await transaction(() async {
      for (final row in rows) {
        if (!approvedIds.contains(row['id'])) continue;
        var cleaned = Map<String, Object?>.from(row)
          ..removeWhere((k, _) => !localColumns.contains(k));
        if (cleaned.isEmpty) continue;
        cleaned['locally_modified'] = 0;
        cleaned['updated_at'] = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final cols = cleaned.keys.map((k) => '"$k"').join(', ');
        final placeholders = cleaned.values.map((_) => '?').join(', ');
        await customInsert(
          'INSERT OR REPLACE INTO "customers" ($cols) VALUES ($placeholders)',
          variables: _rowToVars(cleaned),
          updates: {customers},
        );
        count++;
      }
    });
    return count;
  }
}

/// Hasil agregat top-produk untuk laporan (JOIN query).
/// Satu baris kamus belajar penerimaan barang (untuk layar kelola kamus).
/// `productName` null = satuan tujuannya sudah dihapus sejak alias dipelajari
/// — barisnya tetap ditampilkan supaya bisa dibersihkan user.
typedef ReceiveAliasRow = ({
  String id,
  String normalizedName,
  String normalizedUnit,
  String productUnitId,
  String? productName,
});

/// Satu titik tren harian arus kas.
typedef CashFlowDaily = ({DateTime date, int cashIn, int cashOut});

/// Ringkasan arus kas satu rentang tanggal.
typedef CashFlowSummary = ({
  /// Kas masuk TUNAI, net dari kembalian yang diserahkan.
  int cashIn,

  /// Kas masuk NON-tunai (transfer/QRIS/e-wallet/dst), net dari kembalian.
  int nonCashIn,

  /// Total uang keluar (`expenses`, semua jenis).
  int cashOut,

  /// Rincian uang keluar per jenis pengeluaran.
  Map<String, int> outByType,

  /// Rincian uang masuk per metode bayar (termasuk metode non-tunai
  /// masing-masing, supaya bisa dipecah lebih detail dari sekadar
  /// tunai/non-tunai).
  Map<String, int> inByMethod,
});

/// Ringkasan statistik satu produk dalam rentang tanggal (layar detail
/// produk, dibuka dari tab Produk di Laporan).
typedef ProductStatsSummary = ({
  /// Total terjual, sudah DIKONVERSI ke satuan dasar (lihat dok
  /// `AppDatabase.getProductStatsSummary`) — bukan jumlah mentah lintas
  /// satuan.
  double qtySold,

  /// Nama satuan dasar produk ini (mis. "pcs") — satuan yang dipakai
  /// [qtySold].
  String unitName,

  /// Satuan NON-dasar yang ikut terjual di rentang ini, qty MENTAH apa
  /// adanya dlm satuan itu (bukan dikonversi) — mis. produk dijual sbg
  /// "3 dus" selain sekian pcs. Kosong kalau semua penjualan sudah dlm
  /// satuan dasar.
  List<({String unitName, double qty})> unitBreakdown,
  int revenue,
  int cogs,

  /// Jumlah NOTA yang memuat produk ini (DISTINCT transaction_id), bukan
  /// jumlah baris — satu nota bisa memuat produk yang sama beberapa kali
  /// dgn satuan berbeda (pola lazim di data toko ini, lihat dok
  /// `LeftBehindItems.transactionItemId`).
  int txCount,
});

/// Satu titik tren harian penjualan produk.
typedef ProductDailySales = ({DateTime date, double qty, int revenue});

/// Pembeli (pelanggan TERDAFTAR) satu produk.
typedef ProductBuyerStat = ({
  String customerId,
  String name,
  double qty,
  int revenue,
});

/// Ringkasan belanja satu pelanggan dalam rentang tanggal.
typedef CustomerStatsSummary = ({
  int totalSpent,
  int txCount,
  double itemQty,
  int avgPerTx,
});

class ProductRevenueStat {
  const ProductRevenueStat({
    required this.productId,
    required this.name,
    required this.revenue,
    required this.qtySold,
    required this.cogs,
  });

  final String productId;
  final String name;
  final int revenue;
  final double qtySold;
  final int cogs;

  int get profit => revenue - cogs;
}

/// Hasil agregat top-pelanggan untuk laporan (JOIN query).
class CustomerRevenueStat {
  const CustomerRevenueStat({
    required this.customerId,
    required this.name,
    required this.loyaltyPoints,
    required this.totalSpent,
    required this.txCount,
  });

  final String customerId;
  final String name;
  final int loyaltyPoints;
  final int totalSpent;
  final int txCount;
}

/// Build typed variable list for raw SQL queries.
/// Uses Variable<Object> for all values — SQLite will infer the type from the
/// runtime Dart type passed through DriftSqlType.any.
List<Variable<Object>> _rowToVars(Map<String, Object?> row) {
  return row.values.map<Variable<Object>>((v) {
    if (v == null) return const Variable<Object>(null);
    if (v is bool) return Variable<Object>(v ? 1 : 0);
    return Variable<Object>(v);
  }).toList();
}

// Top-level function — wajib untuk bisa dikirim ke background isolate Dart.
// Lambda closure TIDAK reliable saat di-serialize lintas isolate; named
// top-level function selalu bisa dikirim.
void _sqlcipherIsolateSetup() {
  open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
}

QueryExecutor _openConnection(String encryptionKey) {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'the_pos.db'));
    return NativeDatabase.createInBackground(
      file,
      isolateSetup: _sqlcipherIsolateSetup,
      setup: (rawDb) {
        // Guard: pastikan benar-benar SQLCipher, bukan sqlite3 polos —
        // sqlite3 polos akan menulis DB tanpa enkripsi secara diam-diam.
        final cipherVersion = rawDb.select('PRAGMA cipher_version;');
        if (cipherVersion.isEmpty) {
          throw StateError(
              'SQLCipher tidak termuat — database tidak akan terenkripsi');
        }
        // Key turunan (deriveDbKeyHex) selalu hex 64-char. Validasi ketat
        // memastikan tidak ada karakter kutip/escape yang bisa menyusup ke
        // PRAGMA (passphrase mode SQLCipher dipertahankan agar DB lama tetap
        // bisa dibuka — JANGAN ubah ke format raw-key x'...').
        if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(encryptionKey)) {
          throw ArgumentError(
              'Encryption key harus hex murni; nilai tidak valid ditolak.');
        }
        rawDb.execute("PRAGMA key = '$encryptionKey';");
        // Performance tuning — dipasang setiap koneksi dibuka. WAL + cache
        // + mmap menjaga query tetap cepat walau data menumpuk.
        // Item 41 C.1 — cache diturunkan 64→16 MB & mmap 256→128 MB:
        // target app ini HP kelas bawah RAM 1-2 GB (banyak 32-bit murni);
        // cache 64 MB adalah heap murni SQLCipher yang justru memancing
        // LMK/OOM-kill ("app tiba-tiba tertutup") — 16 MB masih sangat
        // longgar utk pola query POS (baris kecil, indeks sudah lengkap).
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA synchronous = NORMAL;');
        rawDb.execute('PRAGMA cache_size = -16384;'); // 16 MB page cache
        rawDb.execute('PRAGMA mmap_size = 134217728;'); // 128 MB mmap
        rawDb.execute('PRAGMA temp_store = MEMORY;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
        // Audit efisiensi storage — tanpa ini, ruang bekas baris yang
        // dihapus (void transaksi, dsb.) TIDAK otomatis dikembalikan ke OS
        // di luar `VACUUM` manual (cuma dipanggil Tutup Buku, setahun
        // sekali). Pada DB BARU berlaku langsung; pada DB LAMA (auto_vacuum
        // masih NONE) baru benar-benar aktif setelah `VACUUM` berikutnya
        // (SQLite mensyaratkan itu) — otomatis kepakai di Tutup Buku
        // berikutnya, tidak perlu tindakan tambahan.
        rawDb.execute('PRAGMA auto_vacuum = INCREMENTAL;');
      },
    );
  });
}

/// Turunkan key DB dari store_key. Dipanggil sebelum [AppDatabase.open].
String deriveDatabaseKey(String storeKeyBase64) =>
    CryptoService.deriveDbKeyHex(storeKeyBase64);

/// Satu baris buku hutang (Item 12): pelanggan + total hutang + nota tertua
/// yang belum lunas (untuk menghitung umur menunggak).
class DebtBookEntry {
  const DebtBookEntry({
    required this.customerId,
    required this.name,
    required this.phone,
    required this.debt,
    required this.oldest,
    required this.count,
  });

  final String customerId;
  final String name;
  final String? phone;
  final int debt;
  final DateTime oldest;
  final int count;

  int get daysOverdue => DateTime.now().difference(oldest).inDays;
}

/// Satu nota belum lunas — dipakai daftar detail di Buku Hutang.
class UnpaidTxEntry {
  const UnpaidTxEntry({
    required this.id,
    required this.localId,
    required this.createdAt,
    required this.sisa,
  });

  final String id;
  final String localId;
  final DateTime createdAt;
  final int sisa;
}
