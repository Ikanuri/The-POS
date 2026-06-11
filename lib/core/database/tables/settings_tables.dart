import 'package:drift/drift.dart';

/// Permission global untuk role kasir (bukan per-user).
/// Keys: input_stok, tambah_pelanggan, input_pengeluaran,
///       input_pembelian, override_harga
class KasirPermissions extends Table {
  TextColumn get permissionKey => text()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {permissionKey};
}

/// Konfigurasi metode pembayaran (dari mockup Pengaturan).
/// type: tunai | qris | bank | ewallet
class PaymentMethods extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get type => text()();
  TextColumn get name => text()(); // "BRI", "BCA", "OVO", "QRIS"
  TextColumn get data => text().nullable()(); // no rekening / nomor HP
  TextColumn get qrValue => text().nullable()(); // payload QRIS statis
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
