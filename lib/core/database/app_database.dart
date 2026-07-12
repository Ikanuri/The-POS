import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:uuid/uuid.dart';

import '../services/crypto_service.dart';
import 'tables/app_settings_table.dart';
import 'tables/cash_closing_tables.dart';
import 'tables/customer_tables.dart';
import 'tables/employee_tables.dart';
import 'tables/ledger_tables.dart';
import 'tables/pricing_tables.dart';
import 'tables/product_tables.dart';
import 'tables/settings_tables.dart';
import 'tables/summary_tables.dart';
import 'tables/supplier_tables.dart';
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
];

/// Izin khusus role Asisten. Disimpan di tabel kasir_permissions yang sama
/// (dengan prefix `asisten_`) agar ikut tersinkron, tapi ditampilkan di layar
/// "Izin Asisten" terpisah. Asisten tetap punya akses penuh untuk hal lain.
const kAsistenPermissionKeys = <String>[
  'asisten_stok_minus',
];

@DriftDatabase(tables: [
  AppSettings,
  Products,
  ProductGroups,
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e, {this.readOnly = false});

  /// true untuk koneksi arsip (PRAGMA query_only = ON). Saat read-only,
  /// `beforeOpen` tidak boleh menulis (seed batch) karena DB tidak bisa ditulis.
  final bool readOnly;

  static AppDatabase open(String encryptionKey) =>
      AppDatabase(_openConnection(encryptionKey));

  @override
  int get schemaVersion => 14;

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

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          for (final stmt in _performanceIndexes) {
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
            await m.addColumn(transactionPayments, transactionPayments.changeGiven);
            await m.addColumn(transactionPayments, transactionPayments.changeTaken);
          }
          if (from < 14) {
            // Tanda cepat "stok habis" manual per produk (Item 25a).
            await m.addColumn(products, products.markedOutOfStock);
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

  Future<void> setSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
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
    final row = await (select(stockLedger)
          ..where((t) => t.productUnitId.equals(baseUnitId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
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
        'WHERE product_unit_id = ? ORDER BY created_at DESC, id DESC LIMIT 1',
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
        'WHERE product_unit_id = ? ORDER BY created_at DESC, id DESC LIMIT 1',
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
  /// dengan memeriksa localId yang sudah ada.
  Future<String> generateUniqueLocalId(String deviceCode,
      [DateTime? at]) async {
    final now = at ?? DateTime.now();
    final datePart = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final prefix = '$deviceCode-$datePart-';
    final existing = await (select(transactions)
          ..where((t) => t.localId.like('$prefix%')))
        .get();
    final used = existing.map((t) => t.localId).toSet();
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
                  ORDER BY sl.created_at DESC, sl.id DESC LIMIT 1), 0) AS stock
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
            readsFrom: {productUnits, products, stockLedger})
        .get();
    return rows.map((r) => r.data['pid'] as String).toSet();
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

  /// Buat varian baru: produk anak + satu satuan dasar + tier harga + barcode
  /// opsional. Harga default mengikuti induk (di-pass oleh pemanggil).
  /// Buat varian (produk anak). Mengembalikan id produk varian baru agar
  /// pemanggil bisa melacaknya (mis. untuk undo bila edit dibatalkan).
  Future<String> createVariant({
    required String parentProductId,
    required String name,
    required int price,
    required int costPrice,
    int? unitTypeId,
    String? barcode,
    String? kodeProduk,
    bool isNonStock = true,
  }) async {
    final now = DateTime.now();
    final productId = const Uuid().v4();
    final unitId = const Uuid().v4();
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
        id: unitId,
        productId: productId,
        unitTypeId: Value(unitTypeId),
        isBaseUnit: const Value(true),
        ratioToBase: const Value(1.0),
        isNonStock: Value(isNonStock),
      ));
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
    });
    return productId;
  }

  /// Soft-delete varian (set isActive=false).
  Future<void> deleteVariant(String variantProductId) =>
      (update(products)..where((t) => t.id.equals(variantProductId))).write(
        ProductsCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Perbarui varian (produk anak): nama, harga dasar, barcode utama, dan
  /// pelacakan stok. Mengubah satuan dasar varian beserta tier harga minQty=1
  /// dan barcode primer. Tidak menyentuh stok yang sudah tercatat.
  Future<void> updateVariant({
    required String variantProductId,
    required String name,
    required int price,
    String? barcode,
    bool? isNonStock,
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
      final unit =
          units.firstWhere((u) => u.isBaseUnit, orElse: () => units.first);

      if (isNonStock != null) {
        await (update(productUnits)..where((t) => t.id.equals(unit.id)))
            .write(ProductUnitsCompanion(isNonStock: Value(isNonStock)));
      }

      // Tier harga dasar (minQty == 1): update bila ada, selainnya buat baru.
      final baseTier = await (select(priceTiers)
            ..where(
                (t) => t.productUnitId.equals(unit.id) & t.minQty.equals(1)))
          .getSingleOrNull();
      if (baseTier != null) {
        await (update(priceTiers)..where((t) => t.id.equals(baseTier.id)))
            .write(PriceTiersCompanion(price: Value(price)));
      } else {
        await into(priceTiers).insert(PriceTiersCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: unit.id,
          minQty: const Value(1),
          price: price,
          createdAt: Value(now),
        ));
      }

      // Barcode utama: update / hapus / buat sesuai input.
      final existing = await (select(productBarcodes)
            ..where((t) =>
                t.productUnitId.equals(unit.id) & t.isPrimary.equals(true)))
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
          productUnitId: unit.id,
          barcode: bc,
          isPrimary: const Value(true),
        ));
      }
    });
  }

  Future<List<ProductUnit>> getProductUnits(String productId) =>
      (select(productUnits)..where((t) => t.productId.equals(productId))).get();

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
    final emptySlot = await (select(productGroups)
          ..where((t) => t.name.isNull())
          ..limit(1))
        .getSingleOrNull();
    if (emptySlot != null) {
      await (update(productGroups)..where((t) => t.id.equals(emptySlot.id)))
          .write(ProductGroupsCompanion(name: Value(name)));
    } else {
      final rows =
          await customSelect('SELECT MAX(id) as mx FROM product_groups')
              .getSingleOrNull();
      final nextId = (rows?.data['mx'] as int? ?? 20) + 1;
      await into(productGroups).insert(
          ProductGroupsCompanion.insert(id: Value(nextId), name: Value(name)));
    }
  }

  Future<void> renameProductGroup(int id, String newName) =>
      (update(productGroups)..where((t) => t.id.equals(id)))
          .write(ProductGroupsCompanion(name: Value(newName)));

  Future<void> deleteProductGroup(int id) async {
    await (update(products)..where((t) => t.productGroupId.equals(id)))
        .write(const ProductsCompanion(productGroupId: Value(null)));
    await (update(productGroups)..where((t) => t.id.equals(id)))
        .write(const ProductGroupsCompanion(name: Value(null)));
  }

  Future<int> countProductsInGroup(int groupId) async {
    final row = await customSelect(
      'SELECT COUNT(*) as cnt FROM products '
      'WHERE product_group_id = ? AND is_active = 1',
      variables: [Variable.withInt(groupId)],
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
          // Cegah tabrakan UNIQUE(barcode): nilai barcode yang sama bisa
          // sudah ada di baris lain (id berbeda). insertOnConflictUpdate
          // hanya menangani konflik PK id, bukan unique barcode — jadi
          // hapus dulu baris mana pun yang memegang nilai itu.
          await (delete(productBarcodes)
                ..where((t) => t.barcode.equals(bc.barcode.value)))
              .go();
          await into(productBarcodes).insert(bc);
        }
      }
      return productId;
    });
  }

  Future<void> deactivateProduct(String productId) =>
      (update(products)..where((t) => t.id.equals(productId)))
          .write(const ProductsCompanion(isActive: Value(false)));

  /// Item 25a — tandai/lepas tanda "stok habis" manual (lihat komentar
  /// kolom `markedOutOfStock` di product_tables.dart).
  Future<void> setMarkedOutOfStock(String productId, bool value) =>
      (update(products)..where((t) => t.id.equals(productId))).write(
          ProductsCompanion(markedOutOfStock: Value(value)));

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

      if (payment != null) {
        // Total SETELAH item susulan ini tapi SEBELUM _reconcileTransactionTotals
        // (yang baru jalan belakangan) — dihitung manual dari total lama +
        // subtotal item baru, supaya kembalian pembayaran ini dihitung
        // terhadap total yang benar (bukan total lama yang belum termasuk
        // tambahan barang).
        final newItemsTotal =
            items.fold<int>(0, (s, c) => s + c.subtotal.value);
        final totalAfterAddition = tx.total + newItemsTotal;
        final changeGiven = await _computePaymentChangeGiven(
          txId: txId,
          newPaymentAmount: payment.amount.value,
          currentTotal: totalAfterAddition,
        );
        await into(transactionPayments)
            .insert(payment.copyWith(changeGiven: Value(changeGiven)));
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
  Future<int> _computePaymentChangeGiven({
    required String txId,
    required int newPaymentAmount,
    required int currentTotal,
  }) async {
    final amountSum = transactionPayments.amount.sum();
    final changeSum = transactionPayments.changeGiven.sum();
    final row = await (selectOnly(transactionPayments)
          ..addColumns([amountSum, changeSum])
          ..where(transactionPayments.transactionId.equals(txId)))
        .getSingle();
    var priorPaid = row.read(amountSum);
    final priorChangeSum = row.read(changeSum) ?? 0;
    if (priorPaid == null) {
      // Belum ada baris pembayaran sama sekali untuk nota ini (nota
      // legacy/pre-backfill) — jatuhkan ke header `transactions.paid`,
      // konsisten dengan fallback yang sama di `_reconcileTransactionTotals`.
      final tx =
          await (select(transactions)..where((t) => t.id.equals(txId)))
              .getSingleOrNull();
      priorPaid = tx?.paid ?? 0;
    }
    final aggregateChange = (priorPaid + newPaymentAmount) - currentTotal;
    final thisChange = aggregateChange - priorChangeSum;
    return thisChange > 0 ? thisChange : 0;
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
  Future<void> _reconcileTransactionTotals(String txId) async {
    final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    if (tx == null || tx.status == 'void') return;
    // Retur bertotal negatif & tidak pernah ditambah item — jangan diutak-atik.
    if (tx.internalNote?.startsWith('RETUR:') ?? false) return;

    final itemRows = await (select(transactionItems)
          ..where((t) => t.transactionId.equals(txId)))
        .get();
    final newTotal = itemRows.fold<int>(0, (s, i) => s + i.subtotal);

    final payRows = await (select(transactionPayments)
          ..where((t) => t.transactionId.equals(txId)))
        .get();
    final sumPay = payRows.fold<int>(0, (s, p) => s + p.amount);
    final newPaid = payRows.isEmpty ? tx.paid : sumPay;

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
  /// Id yang tidak ada di DB lokal dilewati dengan aman.
  Future<void> reconcileTransactionsByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    await transaction(() async {
      for (final id in ids) {
        await _reconcileTransactionTotals(id);
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

  Future<void> voidTransaction(String txId, String kasirId) async {
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

      await (update(transactions)..where((t) => t.id.equals(txId)))
          .write(const TransactionsCompanion(status: Value('void')));

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
      await into(transactionPayments)
          .insert(TransactionPaymentsCompanion.insert(
        id: const Uuid().v4(),
        transactionId: txId,
        amount: 0,
        method: 'retur',
        paidAt: Value(now),
        kasirId: Value(kasirId),
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
            const TransactionsCompanion(
                status: Value('lunas'), changeAmount: Value(0)));
      }

      await _rebuildDailySummaryFor(_dateKey(tx.createdAt));
    });
  }

  // ───────────────────────── Customer debt ─────────────────────────

  /// Buku hutang: pelanggan dengan nota belum lunas, diurut dari yang paling
  /// lama menunggak (nota tertua yang belum lunas). Diturunkan dari tabel
  /// transactions (lebih akurat dari kolom cache `customers.outstandingDebt`).
  Future<List<DebtBookEntry>> getDebtBook() async {
    final rows = await customSelect(
      'SELECT c.id AS cid, c.name AS name, c.phone AS phone, '
      'SUM(t.total - t.paid) AS debt, MIN(t.created_at) AS oldest, '
      'COUNT(*) AS cnt '
      'FROM transactions t JOIN customers c ON c.id = t.customer_id '
      "WHERE t.status IN ('kurang_bayar', 'tempo') "
      'GROUP BY c.id HAVING debt > 0 ORDER BY oldest ASC',
      readsFrom: {transactions, customers},
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
  Future<List<UnpaidTxEntry>> getUnpaidTxDetails(String customerId) async {
    final rows = await (select(transactions)
          ..where((t) =>
              t.customerId.equals(customerId) &
              t.status.isIn(['kurang_bayar', 'tempo']))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows
        .map((t) => UnpaidTxEntry(
              id: t.id,
              localId: t.localId,
              createdAt: t.createdAt,
              sisa: t.total - t.paid,
            ))
        .toList();
  }

  /// Total hutang akumulatif pelanggan + jumlah nota yang belum lunas.
  Future<(int debtTotal, int debtCount)> getCustomerOutstandingDebt(
      String customerId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(total - paid), 0) AS total, COUNT(*) AS cnt '
      "FROM transactions WHERE customer_id = ? AND status IN ('kurang_bayar', 'tempo')",
      variables: [Variable.withString(customerId)],
      readsFrom: {transactions},
    ).getSingleOrNull();
    final total = (row?.data['total'] as int?) ?? 0;
    final cnt = (row?.data['cnt'] as int?) ?? 0;
    return (total, cnt);
  }

  // ───────────────────────── Pembayaran (buku pembayaran) ─────────────────────────

  /// Riwayat pembayaran satu transaksi, urut waktu (terlama dulu). Sumber
  /// timeline pembayaran di struk — kapan tiap cicilan/pelunasan masuk.
  Future<List<TransactionPayment>> getPaymentsForTx(String txId) =>
      (select(transactionPayments)
            ..where((t) => t.transactionId.equals(txId))
            ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
          .get();

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
    String? note,
    DateTime? now,
  }) async {
    if (amount <= 0) return 0;
    final ts = now ?? DateTime.now();
    return transaction(() async {
      final tx = await (select(transactions)..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      if (tx == null || tx.status == 'void') return 0;
      final changeGiven = await _computePaymentChangeGiven(
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
        paidAt: Value(ts),
        kasirId: Value(kasirId),
        note: Value(note),
        changeGiven: Value(changeGiven),
      ));
      // Status dari `paid` dikurangi TOTAL kembalian yang pernah diberikan
      // (termasuk baris ini) — sama alasannya seperti di
      // `_reconcileTransactionTotals`: kembalian lama yang dipakai ulang
      // sbg pembayaran ini jangan sampai ke-hitung dobel di `paid`.
      final changeSum = transactionPayments.changeGiven.sum();
      final sumRow = await (selectOnly(transactionPayments)
            ..addColumns([changeSum])
            ..where(transactionPayments.transactionId.equals(txId)))
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
        ),
      );
      return changeGiven;
    });
  }

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
      createdAt:
          createdAt == null ? const Value.absent() : Value(createdAt),
    ));
  }

  Future<void> deleteExpense(String id) =>
      (delete(expenses)..where((t) => t.id.equals(id))).go();

  /// Semua pengeluaran dalam rentang [from]..[to], terbaru dulu.
  Stream<List<Expense>> watchExpenses(DateTime from, DateTime to) {
    return (select(expenses)
          ..where((t) =>
              t.createdAt.isBiggerOrEqualValue(from) &
              t.createdAt.isSmallerOrEqualValue(to))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Total pengeluaran yang mengurangi Laba Bersih (daily_expense +
  /// change_given) dalam rentang.
  Future<int> getNetProfitExpenseTotal(DateTime from, DateTime to) async {
    final amountSum = expenses.amount.sum();
    final row = await (selectOnly(expenses)
          ..addColumns([amountSum])
          ..where(expenses.type.isIn(netProfitExpenseTypes) &
              expenses.createdAt.isBiggerOrEqualValue(from) &
              expenses.createdAt.isSmallerOrEqualValue(to)))
        .getSingle();
    return row.read(amountSum) ?? 0;
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
  }) async {
    if (txIds.isEmpty || amount <= 0) return (0, 0);
    return transaction(() async {
      final txs = await (select(transactions)
            ..where((t) => t.id.isIn(txIds))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
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
        final sisa = tx.total - tx.paid;
        if (sisa <= 0) continue; // sudah lunas → lewati
        final applied = remaining < sisa ? remaining : sisa;
        final paymentId = const Uuid().v4();
        await into(transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
            id: paymentId,
            transactionId: tx.id,
            amount: applied,
            method: method,
            paidAt: Value(now),
            kasirId: Value(kasirId),
            note: Value('Gabung: $label'),
          ),
        );
        lastPaymentId = paymentId;
        final newPaid = tx.paid + applied;
        await (update(transactions)..where((t) => t.id.equals(tx.id))).write(
          TransactionsCompanion(
            paid: Value(newPaid),
            status: Value(newPaid >= tx.total ? 'lunas' : 'kurang_bayar'),
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
      'SELECT t.id AS id, t.paid AS paid, t.payment_method AS method, '
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
        b.insert(
          transactionPayments,
          TransactionPaymentsCompanion.insert(
            id: const Uuid().v4(),
            transactionId: r.data['id'] as String,
            amount: r.data['paid'] as int,
            method: (r.data['method'] as String?) ?? 'tunai',
            paidAt: Value(paidAt),
            kasirId: Value(r.data['kasir'] as String?),
            note: const Value('Migrasi data lama'),
            // Satu-satunya pembayaran nota lama → warisi kembalian &
            // status ambil dari header transaksi (sumber lama), supaya
            // Ringkasan (sekarang baca dari baris pembayaran) tidak
            // mendadak kosong untuk nota yang sudah ada sebelum migrasi ini.
            changeGiven: Value((r.data['change_amount'] as int?) ?? 0),
            changeTaken: Value((r.data['change_taken'] as int?) == 1),
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
    // 0=tunai 1=qris 2=transfer 3=lainnya
    final idx = switch (method) {
      'tunai' => 0,
      'qris' => 1,
      'transfer' => 2,
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

  Stream<List<Transaction>> watchTransactions({
    required DateTime from,
    required DateTime to,
  }) =>
      (select(transactions)
            ..where((t) =>
                t.status.isNotValue('void') &
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

  // ───────────────────────── Backup / Restore ─────────────────────────

  static const _allTables = [
    'app_settings',
    'products',
    'product_groups',
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
    'held_orders',
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
      'stock_ledger',
      'loyalty_point_ledger',
      'expenses',
    ];
    const masterData = [
      'products',
      'product_units',
      'price_tiers',
      'alt_prices',
      'product_barcodes',
      'customers',
      'customer_groups',
      'customer_group_prices',
    ];

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
        case 'transaction_items':
          // Item susulan (fitur tambah belanjaan) bisa menempel pada transaksi
          // lama — ikutkan juga berdasarkan added_at agar tidak tertinggal.
          sql = 'SELECT * FROM "transaction_items" WHERE transaction_id IN '
              '(SELECT id FROM "transactions" WHERE created_at >= ?) '
              'OR added_at >= ?';
          varCount = 2;
        case 'transaction_payments':
          sql = 'SELECT * FROM "transaction_payments" WHERE paid_at >= ?';
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
    if (includeMasterData) {
      for (final t in masterData) {
        final hasUpdated = t == 'products' || t == 'customers';
        if (hasUpdated) {
          final rows = await customSelect(
            'SELECT * FROM "$t" WHERE updated_at >= ? OR created_at >= ?',
            variables: [Variable.withInt(sinceSec), Variable.withInt(sinceSec)],
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
    }
    return dump;
  }

  /// Merge rows from sync payload (INSERT OR IGNORE for ledger, last-write-wins for master).
  Future<int> mergeRows(String tableName, List<Map<String, Object?>> rows,
      bool isAppendOnly) async {
    var count = 0;
    await transaction(() async {
      for (var row in rows) {
        if (row.isEmpty) continue;

        if (isAppendOnly) {
          // Append-only: skip if PK already exists.
          final pkVal = row['id'];
          if (pkVal != null) {
            final exists = await customSelect(
              'SELECT 1 FROM "$tableName" WHERE id = ?',
              variables: [Variable<Object>(pkVal)],
            ).getSingleOrNull();
            if (exists != null) continue;
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
                await customStatement(
                  'DELETE FROM price_tiers WHERE id = ?',
                  [e.data['id']!],
                );
              }
            }
          }
        }

        final cols = row.keys.map((k) => '"$k"').join(', ');
        final placeholders = row.values.map((_) => '?').join(', ');
        final variables = _rowToVars(row);
        final mode = isAppendOnly ? 'INSERT OR IGNORE' : 'INSERT OR REPLACE';
        final inserted = await customInsert(
          '$mode INTO "$tableName" ($cols) VALUES ($placeholders)',
          variables: variables,
        );
        if (inserted > 0) count++;
      }
    });
    return count;
  }
}

/// Hasil agregat top-produk untuk laporan (JOIN query).
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
        // besar + mmap menjaga query tetap cepat walau data menumpuk.
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA synchronous = NORMAL;');
        rawDb.execute('PRAGMA cache_size = -65536;'); // 64 MB page cache
        rawDb.execute('PRAGMA mmap_size = 268435456;'); // 256 MB mmap
        rawDb.execute('PRAGMA temp_store = MEMORY;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
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
