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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  static AppDatabase open(String encryptionKey, {String? oldKeyForMigration}) =>
      AppDatabase(_openConnection(encryptionKey,
          oldKeyForMigration: oldKeyForMigration));

  @override
  int get schemaVersion => 3;

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
        },
        beforeOpen: (details) async {
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

  /// Stok terkini = stockAfter dari entry ledger terbaru.
  Future<double> currentStock(String productUnitId) async {
    final row = await (select(stockLedger)
          ..where((t) => t.productUnitId.equals(productUnitId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row?.stockAfter ?? 0;
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
  Future<void> createVariant({
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
  }

  /// Soft-delete varian (set isActive=false).
  Future<void> deleteVariant(String variantProductId) =>
      (update(products)..where((t) => t.id.equals(variantProductId))).write(
        ProductsCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );

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
      // Compute stockAfter inside the transaction for consistency.
      for (final s in stockItems) {
        final prev = await currentStock(s.productUnitId);
        await into(stockLedger).insert(StockLedgerCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: s.productUnitId,
          type: 'sale',
          qtyChange: -s.qty,
          stockAfter: prev - s.qty,
          note: Value(s.note),
          createdAt: Value(ts),
        ));
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
      // Reverse stock entries.
      for (final item in items) {
        final lastStock = await currentStock(item.productUnitId);
        await into(stockLedger).insert(StockLedgerCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: item.productUnitId,
          type: 'return_in',
          qtyChange: item.qty,
          stockAfter: lastStock + item.qty,
          note: Value('Void ${tx.localId}'),
          createdAt: Value(now),
        ));
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
      // Kembalikan stok untuk tiap item.
      for (final item in returnItems) {
        final prev = await currentStock(item.productUnitId);
        await into(stockLedger).insert(StockLedgerCompanion.insert(
          id: const Uuid().v4(),
          productUnitId: item.productUnitId,
          type: 'return_in',
          qtyChange: item.qty,
          stockAfter: prev + item.qty,
          referenceId: Value(originalTxId),
          kasirId: Value(kasirId),
          note: const Value('Retur'),
          createdAt: Value(now),
        ));
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
    final sinceMs = since.millisecondsSinceEpoch;

    for (final t in appendOnly) {
      final rows = await customSelect(
        'SELECT * FROM "$t" WHERE created_at >= ?',
        variables: [Variable.withInt(sinceMs)],
      ).get();
      dump[t] = rows.map((r) => r.data).toList();
    }
    for (final t in masterData) {
      final hasUpdated = t == 'products' || t == 'product_units' || t == 'customers';
      if (hasUpdated) {
        final rows = await customSelect(
          'SELECT * FROM "$t" WHERE updated_at >= ? OR created_at >= ?',
          variables: [Variable.withInt(sinceMs), Variable.withInt(sinceMs)],
        ).get();
        dump[t] = rows.map((r) => r.data).toList();
      } else {
        final rows = await customSelect('SELECT * FROM "$t"').get();
        dump[t] = rows.map((r) => r.data).toList();
      }
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
        if (!isAppendOnly && row.containsKey('updated_at')) {
          final id = row['id'];
          final incomingTs = row['updated_at'];
          if (id != null && incomingTs is int) {
            final existing = await customSelect(
              'SELECT updated_at FROM "$tableName" WHERE id = ?',
              variables: [Variable<Object>(id)],
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

/// Buka koneksi SQLCipher. [encryptionKey] = kunci aktif.
/// [oldKeyForMigration] ada bila perlu PRAGMA rekey (B-5 migration).
QueryExecutor _openConnection(String encryptionKey,
    {String? oldKeyForMigration}) {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'the_pos.db'));
    final openKey = oldKeyForMigration ?? encryptionKey;
    final needsRekey = oldKeyForMigration != null;

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
        // Key turunan selalu hex 64-char. Validasi ketat memastikan tidak ada
        // karakter kutip/escape yang bisa menyusup ke PRAGMA.
        final hexRe = RegExp(r'^[0-9a-fA-F]+$');
        if (!hexRe.hasMatch(openKey)) {
          throw ArgumentError(
              'Encryption key harus hex murni; nilai tidak valid ditolak.');
        }
        rawDb.execute("PRAGMA key = '$openKey';");

        if (needsRekey) {
          // B-5: Upgrade ke 210 000 iterasi. PRAGMA rekey berjalan atomik.
          if (!hexRe.hasMatch(encryptionKey)) {
            throw ArgumentError('New encryption key harus hex murni.');
          }
          rawDb.execute("PRAGMA rekey = '$encryptionKey';");
        }

        // Performance tuning — dipasang setiap koneksi dibuka.
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA synchronous = NORMAL;');
        rawDb.execute('PRAGMA cache_size = -65536;'); // 64 MB
        rawDb.execute('PRAGMA mmap_size = 268435456;'); // 256 MB
        rawDb.execute('PRAGMA temp_store = MEMORY;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
      },
    );
  });
}

/// Turunkan key DB v1 dari store_key (10 000 iter). Backward-compat.
String deriveDatabaseKey(String storeKeyBase64) =>
    CryptoService.deriveDbKeyHex(storeKeyBase64);
