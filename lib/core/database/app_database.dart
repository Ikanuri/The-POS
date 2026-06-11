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
};

const kKasirPermissionKeys = <String>[
  'input_stok',
  'tambah_pelanggan',
  'input_pengeluaran',
  'input_pembelian',
  'override_harga',
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
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  static AppDatabase open(String encryptionKey) =>
      AppDatabase(_openConnection(encryptionKey));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaults();
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
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
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
    final q = (select(products)..where((t) => t.isActive.equals(true)));
    if (query.isNotEmpty) {
      q.where((t) => t.name.lower().contains(query.toLowerCase()));
    }
    if (groupId != null) {
      q.where((t) => t.productGroupId.equals(groupId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
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

  Future<String> saveProduct({
    required ProductsCompanion product,
    required List<ProductUnitsCompanion> units,
    required Map<String, List<PriceTiersCompanion>> tiersByUnitTempId,
    required Map<String, List<ProductBarcodesCompanion>> barcodesByUnitTempId,
  }) async {
    return transaction(() async {
      final productId = product.id.value;
      await into(products).insertOnConflictUpdate(product);

      for (final unit in units) {
        final unitId = unit.id.value;
        await into(productUnits).insertOnConflictUpdate(unit);

        final tiers = tiersByUnitTempId[unitId] ?? [];
        if (tiers.isNotEmpty) {
          await (delete(priceTiers)
                ..where((t) => t.productUnitId.equals(unitId)))
              .go();
          await batch((b) => b.insertAll(priceTiers, tiers));
        }

        final barcodes = barcodesByUnitTempId[unitId] ?? [];
        for (final bc in barcodes) {
          await into(productBarcodes).insertOnConflictUpdate(bc);
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
    required List<StockLedgerCompanion> stockEntries,
    LoyaltyPointLedgerCompanion? loyaltyEntry,
  }) async {
    await transaction(() async {
      await into(transactions).insert(tx);
      await batch((b) {
        b.insertAll(transactionItems, items);
        if (payments.isNotEmpty) b.insertAll(transactionPayments, payments);
        b.insertAll(stockLedger, stockEntries);
        if (loyaltyEntry != null) {
          b.insert(loyaltyPointLedger, loyaltyEntry);
        }
      });
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
    });
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
}

QueryExecutor _openConnection(String encryptionKey) {
  return LazyDatabase(() async {
    // Pastikan native library SQLCipher yang terpakai, bukan sqlite3 polos.
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'the_pos.db'));
    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        final escaped = encryptionKey.replaceAll("'", "''");
        rawDb.execute("PRAGMA key = '$escaped';");
      },
    );
  });
}

/// Turunkan key DB dari store_key. Dipanggil sebelum [AppDatabase.open].
String deriveDatabaseKey(String storeKeyBase64) =>
    CryptoService.deriveDbKeyHex(storeKeyBase64);
