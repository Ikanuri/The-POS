import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

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
