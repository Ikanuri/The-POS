import 'package:drift/drift.dart';

/// Status: lunas | kurang_bayar | tempo | void
class Transactions extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get localId => text().unique()(); // K1-20260611-0001
  TextColumn get kasirId => text().nullable()(); // device_code
  TextColumn get customerId => text().nullable()();

  /// Nama pembeli ad-hoc (bukan pelanggan terdaftar).
  /// customerId != null  -> pelanggan terdaftar (customerName diabaikan)
  /// customerName != null -> pembeli umum bernama, TIDAK masuk tabel customers
  /// keduanya null        -> ditampilkan sebagai "Umum"
  TextColumn get customerName => text().nullable()();

  TextColumn get status => text()();
  IntColumn get total => integer()();
  IntColumn get paid => integer()();
  IntColumn get changeAmount => integer()();
  TextColumn get paymentMethod => text()(); // tunai | transfer | qris | ewallet | tempo
  TextColumn get internalNote => text().nullable()();
  TextColumn get strukNote => text().nullable()();
  IntColumn get pointsEarned => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TransactionItems extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(Transactions, #id)();
  TextColumn get productId => text()();
  TextColumn get productUnitId => text()();
  RealColumn get qty => real()(); // support desimal: 0.25, 0.5 kg
  IntColumn get priceAtSale => integer()(); // harga final setelah override
  IntColumn get originalPrice => integer()(); // harga dari algoritma
  BoolColumn get priceOverridden => boolean().withDefault(const Constant(false))();
  IntColumn get costAtSale => integer().withDefault(const Constant(0))();
  TextColumn get itemNote => text().nullable()(); // catatan item, muncul di struk
  IntColumn get subtotal => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pembayaran bertahap untuk transaksi kurang_bayar / tempo.
class TransactionPayments extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(Transactions, #id)();
  IntColumn get amount => integer()();
  TextColumn get method => text()();
  DateTimeColumn get paidAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get kasirId => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pesanan ditahan (hold) — bisa dilanjutkan kapan saja, lokal per device.
class HeldOrders extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()(); // nama pembeli / penanda
  TextColumn get cartJson => text()(); // serialized cart state
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
