import 'package:drift/drift.dart';

/// Ringkasan harian ter-materialisasi. Diisi/diperbarui setiap kali transaksi
/// dibuat atau dibatalkan, sehingga layar laporan tidak perlu memindai seluruh
/// tabel transaksi/item (O(transaksi)) melainkan cukup membaca per-hari
/// (O(hari)). Tetap konsisten walau data menumpuk bertahun-tahun.
///
/// Pembayaran disederhanakan ke 4 bucket. Metode di luar tunai/qris/transfer
/// (mis. ewallet, tempo) dimasukkan ke [pembayaranLainnya].
class DailySummaries extends Table {
  /// 'YYYY-MM-DD' (zona waktu lokal device).
  TextColumn get date => text()();

  IntColumn get omzet => integer().withDefault(const Constant(0))();
  IntColumn get hpp => integer().withDefault(const Constant(0))();
  IntColumn get labaKotor => integer().withDefault(const Constant(0))();
  IntColumn get jumlahTransaksi => integer().withDefault(const Constant(0))();
  IntColumn get jumlahItem => integer().withDefault(const Constant(0))();
  IntColumn get pembayaranTunai => integer().withDefault(const Constant(0))();
  IntColumn get pembayaranQris => integer().withDefault(const Constant(0))();
  IntColumn get pembayaranTransfer => integer().withDefault(const Constant(0))();
  IntColumn get pembayaranLainnya => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {date};
}
