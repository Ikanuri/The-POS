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
  1: 'Biji',
  2: 'Pak',
  3: 'Dos',
  4: 'Ret',
  5: 'Sak',
  6: 'Kg',
  9: 'Lusin',
  10: 'Bal',
  11: 'Botol',
  12: 'Galon',
  13: 'Sachet',
  14: 'Renteng',
  15: 'Kaleng',
  16: 'Batang',
  17: 'Bungkus',
  18: 'Liter',
  19: 'Meter',
  20: 'Roll',
  21: 'Set',
  22: 'Pasang',
  23: 'Lembar',
  24: 'Ikat',
  25: 'Slop',
};

const kKasirPermissionKeys = <String>[
  'input_stok',
  'tambah_pelanggan',
  'input_pengeluaran',
  'input_pembelian',
  'override_harga',
  'batal_transaksi',
];

@DriftDatabase(tables: [
  AppSettings,
  Products,
  ProductGroups,
  UnitTypes,
  ProductUnits,
  ProductBarcodes,
  PriceTiers,
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e, {this.readOnly = false});

  /// true untuk koneksi arsip (PRAGMA query_only = ON). Saat read-only,
  /// `beforeOpen` tidak boleh menulis (seed batch) karena DB tidak bisa ditulis.
  final bool readOnly;

  static AppDatabase open(String encryptionKey) =>
      AppDatabase(_openConnection(encryptionKey));

  @override
  int get schemaVersion => 6;

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
                (e) => UnitTypesCompanion.insert(id: Value(e.key), name: e.value),
              ),
              mode: InsertMode.insertOrIgnore,
            );
            b.insertAll(
              kasirPermissions,
              kKasirPermissionKeys
                  .map((k) => KasirPermissionsCompanion.insert(permissionKey: k)),
              mode: InsertMode.insertOrIgnore,
            );
          });
        },
      );

  Future<void> _seedDefaults() async {
    await batch((b) {
      // Satuan legacy. ID 7 & 8 di sistem lama = 'Biji', merge ke ID 1.
      b.insertAll(
        unitTypes,
        _kDefaultUnitTypes.entries
            .map((e) => UnitTypesCompanion.insert(id: Value(e.key), name: e.value)),
        mode: InsertMode.insertOrIgnore,
      );
      // Group produk legacy 3–20, nama diisi manual.
      b.insertAll(
        productGroups,
        [for (var i = 3; i <= 20; i++) ProductGroupsCompanion.insert(id: Value(i))],
        mode: InsertMode.insertOrIgnore,
      );
      // Permission kasir, semua default OFF.
      b.insertAll(
        kasirPermissions,
        kKasirPermissionKeys
            .map((k) => KasirPermissionsCompanion.insert(permissionKey: k)),
        mode: InsertMode.insertOrIgnore,
      );
      // Metode bayar bawaan: tunai selalu ada, tidak bisa dihapus di UI.
      b.insert(
        paymentMethods,
        PaymentMethodsCompanion.insert(id: 'pm-tunai', type: 'tunai', name: 'Tunai'),
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

  // ───────────────────────── Stock queries ─────────────────────────

  /// Lookup satuan dasar dan rasio dari sembarang productUnitId.
  /// Mengembalikan (id: baseUnitId, ratio: ratioToBase).
  Future<({String id, double ratio})> _baseUnitOf(String productUnitId) async {
    final unit = await (select(productUnits)
          ..where((t) => t.id.equals(productUnitId)))
        .getSingleOrNull();
    if (unit == null || unit.isBaseUnit) {
      return (id: productUnitId, ratio: unit?.ratioToBase ?? 1.0);
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
  Future<double> currentStock(String productUnitId) async {
    final info = await _baseUnitOf(productUnitId);
    final base = await _rawBaseStock(info.id);
    return info.ratio <= 1.0 ? base : base / info.ratio;
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
      return info.ratio <= 1.0 ? deltaBase : deltaBase / info.ratio;
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
      final currentBase =
          baseLastRow != null ? (baseLastRow.data['stock_after'] as num).toDouble() : 0.0;

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

  Future<int> countTodayTransactions(String deviceCode) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final c = transactions.id.count();
    final q = selectOnly(transactions)
      ..addColumns([c])
      ..where(transactions.kasirId.equals(deviceCode) &
          transactions.createdAt.isBiggerOrEqualValue(start));
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  /// Nomor nota harian yang dijamin unik. Penjualan dan retur berbagi ruang
  /// penghitung yang sama, sehingga memakai countTodayTransactions+1 mentah
  /// bisa bertabrakan. Method ini mencari sequence bebas berikutnya dengan
  /// memeriksa localId yang sudah ada.
  Future<String> generateUniqueLocalId(String deviceCode, [DateTime? at]) async {
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
      'WHERE t.internal_note = ? '
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
      q.where((t) => t.name.lower().contains(query.toLowerCase()));
    }
    if (groupId != null) {
      q.where((t) => t.productGroupId.equals(groupId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
  }

  /// Varian (produk anak) aktif milik [parentProductId], urut nama.
  Future<List<Product>> getVariants(String parentProductId) =>
      (select(products)
            ..where((t) =>
                t.parentProductId.equals(parentProductId) &
                t.isActive.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

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
          ..where((t) =>
              t.id.isIn(productIds) & t.parentProductId.isNotNull()))
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
      final unit = units.firstWhere((u) => u.isBaseUnit,
          orElse: () => units.first);

      if (isNonStock != null) {
        await (update(productUnits)..where((t) => t.id.equals(unit.id)))
            .write(ProductUnitsCompanion(isNonStock: Value(isNonStock)));
      }

      // Tier harga dasar (minQty == 1): update bila ada, selainnya buat baru.
      final baseTier = await (select(priceTiers)
            ..where((t) =>
                t.productUnitId.equals(unit.id) & t.minQty.equals(1)))
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
          await (delete(productBarcodes)..where((t) => t.id.equals(existing.id)))
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

  Future<List<ProductGroup>> getAllProductGroups() =>
      (select(productGroups)
            ..where((t) => t.name.isNotNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<void> addProductGroup(String name) async {
    final emptySlot = await (select(productGroups)
          ..where((t) => t.name.isNull())
          ..limit(1))
        .getSingleOrNull();
    if (emptySlot != null) {
      await (update(productGroups)..where((t) => t.id.equals(emptySlot.id)))
          .write(ProductGroupsCompanion(name: Value(name)));
    } else {
      final rows = await customSelect(
              'SELECT MAX(id) as mx FROM product_groups')
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
    await (update(products)
          ..where((t) => t.productGroupId.equals(id)))
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
        await (delete(priceTiers)
              ..where((t) => t.productUnitId.equals(unitId)))
            .go();
        final tiers = tiersByUnitTempId[unitId] ?? [];
        if (tiers.isNotEmpty) {
          await batch((b) => b.insertAll(priceTiers, tiers));
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
        if (payment != null) b.insert(transactionPayments, payment);
      });

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

    final isTempo = tx.status == 'tempo' && newPaid == 0;
    final newStatus = isTempo
        ? 'tempo'
        : (newPaid < newTotal ? 'kurang_bayar' : 'lunas');
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
    if (ids.isEmpty) return;
    await transaction(() async {
      for (final id in ids) {
        await _reconcileTransactionTotals(id);
      }
    });
  }

  Future<void> voidTransaction(String txId, String kasirId) async {
    await transaction(() async {
      // Baca items untuk reverse stock.
      final items = await (select(transactionItems)
            ..where((t) => t.transactionId.equals(txId)))
          .get();
      final tx = await (select(transactions)
            ..where((t) => t.id.equals(txId)))
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
        await into(loyaltyPointLedger).insert(LoyaltyPointLedgerCompanion.insert(
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
        final pointsToReverse =
            (orig.pointsEarned * proportion).round().clamp(0, orig.pointsEarned);
        if (pointsToReverse > 0) {
          await customUpdate(
            'UPDATE customers SET loyalty_points = loyalty_points - ? WHERE id = ?',
            variables: [
              Variable.withInt(pointsToReverse),
              Variable.withString(orig.customerId!),
            ],
            updates: {customers},
          );
          await into(loyaltyPointLedger).insert(
              LoyaltyPointLedgerCompanion.insert(
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

  // ───────────────────────── Customer debt ─────────────────────────

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
      for (final tx in txs) {
        if (remaining <= 0) break;
        final sisa = tx.total - tx.paid;
        if (sisa <= 0) continue; // sudah lunas → lewati
        final applied = remaining < sisa ? remaining : sisa;
        await into(transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
            id: const Uuid().v4(),
            transactionId: tx.id,
            amount: applied,
            method: method,
            paidAt: Value(now),
            kasirId: Value(kasirId),
            note: Value('Gabung: $label'),
          ),
        );
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
      't.kasir_id AS kasir, t.created_at AS created '
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
          ),
        );
      }
    });
  }

  // ───────────────────────── History filter ─────────────────────────

  /// Set id transaksi yang memuat produk dengan nama mengandung [q].
  Future<Set<String>> findTxIdsWithProduct(String q) async {
    if (q.trim().isEmpty) return <String>{};
    final rows = await customSelect(
      'SELECT DISTINCT ti.transaction_id AS tid FROM transaction_items ti '
      'JOIN products p ON p.id = ti.product_id '
      'WHERE LOWER(p.name) LIKE ?',
      variables: [Variable.withString('%${q.toLowerCase()}%')],
      readsFrom: {transactionItems, products},
    ).get();
    return rows.map((r) => r.data['tid'] as String).toSet();
  }

  // ───────────────────────── Daily summary ─────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
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
    final allDates = rows
        .map((r) => r.data['d'] as String?)
        .whereType<String>()
        .toSet();

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
        dates.add(_dateKey(
            DateTime.fromMillisecondsSinceEpoch(ca * 1000)));
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
    'app_settings', 'products', 'product_groups', 'unit_types',
    'product_units', 'product_barcodes', 'price_tiers',
    'customer_groups', 'customer_group_prices', 'customers',
    'transactions', 'transaction_items', 'transaction_payments', 'held_orders',
    'stock_ledger', 'expenses', 'loyalty_point_ledger',
    'suppliers', 'purchases', 'purchase_items',
    'kasir_permissions', 'payment_methods', 'daily_summaries',
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
    await transaction(() async {
      // Delete children before parents to avoid FK violations.
      for (final tableName in _allTables.reversed) {
        await customStatement('DELETE FROM "$tableName"');
      }
      // Insert in forward (parent-first) order.
      for (final tableName in _allTables) {
        final rows = dump[tableName] ?? [];
        for (final row in rows) {
          if (row.isEmpty) continue;
          final cols = row.keys.map((k) => '"$k"').join(', ');
          final placeholders = row.values.map((_) => '?').join(', ');
          final variables = _rowToVars(row);
          await customInsert(
            'INSERT OR REPLACE INTO "$tableName" ($cols) VALUES ($placeholders)',
            variables: variables,
          );
        }
      }
    });
  }

  // ───────────────────────── Sync helpers ─────────────────────────

  /// Dump only syncable rows since [since] for WiFi sync.
  Future<Map<String, List<Map<String, Object?>>>> dumpSince(
      DateTime since) async {
    const appendOnly = [
      'transactions', 'transaction_items', 'transaction_payments',
      'stock_ledger', 'loyalty_point_ledger', 'expenses',
    ];
    const masterData = [
      'products', 'product_units', 'price_tiers', 'product_barcodes',
      'customers', 'customer_groups', 'customer_group_prices',
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
      switch (t) {
        case 'transaction_items':
          sql = 'SELECT * FROM "transaction_items" WHERE transaction_id IN '
              '(SELECT id FROM "transactions" WHERE created_at >= ?)';
        case 'transaction_payments':
          sql = 'SELECT * FROM "transaction_payments" WHERE paid_at >= ?';
        default:
          sql = 'SELECT * FROM "$t" WHERE created_at >= ?';
      }
      final rows = await customSelect(
        sql,
        variables: [Variable.withInt(sinceSec)],
      ).get();
      dump[t] = rows.map((r) => r.data).toList();
    }
    for (final t in masterData) {
      final hasUpdated = t == 'products' || t == 'product_units' || t == 'customers';
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
    // Ikut tersinkron agar perubahan izin dari owner langsung berlaku di HP kasir.
    {
      final rows = await customSelect(
        'SELECT * FROM "kasir_permissions" WHERE updated_at >= ?',
        variables: [Variable.withInt(sinceSec)],
      ).get();
      dump['kasir_permissions'] = rows.map((r) => r.data).toList();
    }
    return dump;
  }

  /// Merge rows from sync payload (INSERT OR IGNORE for ledger, last-write-wins for master).
  Future<int> mergeRows(
      String tableName, List<Map<String, Object?>> rows, bool isAppendOnly) async {
    var count = 0;
    await transaction(() async {
      for (final row in rows) {
        if (row.isEmpty) continue;
        // Last-write-wins for master tables with updated_at.
        // Cari PK: kolom 'id' (UUID) untuk tabel utama, atau 'permission_key'
        // untuk kasir_permissions (yang tidak punya kolom id).
        if (!isAppendOnly && row.containsKey('updated_at')) {
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
