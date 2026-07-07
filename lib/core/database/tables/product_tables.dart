import 'package:drift/drift.dart';

class Products extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  IntColumn get productGroupId => integer().nullable()();
  TextColumn get kodeProduk => text().nullable()();
  /// Bila terisi, produk ini adalah VARIAN dari produk induk (mis. Pop Ice →
  /// Coklat). Varian disembunyikan dari katalog utama dan muncul sebagai
  /// pilihan add-on di modal entri item induk.
  TextColumn get parentProductId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Group produk legacy (ID 3–20), nama diisi manual oleh owner.
class ProductGroups extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Satuan legacy (ID 1–25): Kg, Pcs, Pak, Bal, Sak, Slop, Biji, Dos, dll.
class UnitTypes extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  TextColumn get abbrev => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Varian produk: tiap produk bisa punya beberapa satuan jual
/// (mis. Indomie: pcs / renteng 10 / dus 40) dengan rasio ke satuan dasar.
class ProductUnits extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get unitTypeId => integer().nullable()();
  BoolColumn get isBaseUnit => boolean().withDefault(const Constant(false))();
  RealColumn get ratioToBase => real().withDefault(const Constant(1.0))();
  BoolColumn get isNonStock => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Barcode per varian — satu varian bisa punya beberapa barcode.
class ProductBarcodes extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get productUnitId => text().references(ProductUnits, #id)();
  TextColumn get barcode => text().unique()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  BoolColumn get isGenerated => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
