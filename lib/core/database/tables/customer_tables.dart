import 'package:drift/drift.dart';

class CustomerGroups extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  TextColumn get color => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Customers extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get customerGroupId => text().nullable()();
  IntColumn get creditLimit => integer().withDefault(const Constant(0))();
  IntColumn get outstandingDebt => integer().withDefault(const Constant(0))();
  IntColumn get loyaltyPoints => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Item 40 utk pelanggan (susulan permintaan user) — pola SAMA PERSIS dgn
  /// `Products.locallyModified`: device non-owner yang tambah/ubah pelanggan
  /// menandai baris ini `true` (lihat `markCustomerLocallyModified`), lalu
  /// dikirim sbg "usulan" ke host via sync (`dumpLocalCustomerProposals`) utk
  /// ditinjau/disetujui owner (`applyCustomerProposals`) — BUKAN otomatis
  /// menimpa data pelanggan di host. Device owner TIDAK PERNAH set true.
  BoolColumn get locallyModified =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
