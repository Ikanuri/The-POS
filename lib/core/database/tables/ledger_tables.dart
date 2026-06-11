import 'package:drift/drift.dart';

/// Append-only. Stok terkini = stockAfter dari entry terbaru per productUnitId.
/// type: opening | sale | purchase | return_in | return_out | adjustment
class StockLedger extends Table {
  TextColumn get id => text()();
  TextColumn get productUnitId => text()();
  TextColumn get type => text()();
  RealColumn get qtyChange => real()(); // positif = masuk, negatif = keluar
  RealColumn get stockAfter => real()(); // running balance
  TextColumn get referenceId => text().nullable()();
  TextColumn get kasirId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// type: daily_expense | owner_withdrawal | supplier_payment | change_given
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get localId => text().unique()();
  TextColumn get type => text()();
  IntColumn get amount => integer()();
  TextColumn get note => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get kasirId => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// type: earn | redeem | adjust
class LoyaltyPointLedger extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get type => text()();
  IntColumn get points => integer()(); // positif atau negatif
  TextColumn get referenceId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
