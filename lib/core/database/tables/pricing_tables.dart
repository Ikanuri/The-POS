import 'package:drift/drift.dart';

import 'customer_tables.dart';
import 'product_tables.dart';

/// Harga berjenjang per varian. Tier dengan minQty terbesar yang <= qty menang.
class PriceTiers extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get productUnitId => text().references(ProductUnits, #id)();
  IntColumn get minQty => integer().withDefault(const Constant(1))();
  IntColumn get price => integer()(); // Rupiah bulat
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Harga khusus per group pelanggan — prioritas tertinggi di price resolver.
class CustomerGroupPrices extends Table {
  TextColumn get id => text()();
  TextColumn get productUnitId => text().references(ProductUnits, #id)();
  TextColumn get customerGroupId => text().references(CustomerGroups, #id)();
  IntColumn get price => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {productUnitId, customerGroupId},
      ];
}
