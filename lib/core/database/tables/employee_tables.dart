import 'package:drift/drift.dart';

/// Pegawai toko (yang melayani / mengambilkan barang). Dicatat per nota agar
/// bila ada salah ambil / salah input, bisa ditelusuri siapa yang melayani
/// saat itu. Master data dikelola di Pengaturan → Toko.
class Employees extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
