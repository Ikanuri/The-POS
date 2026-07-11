import 'package:drift/drift.dart';

/// Item 15 — Tutup Kasir harian (rekap kas fisik vs sistem). BEDA dari
/// "Tutup Buku" (arsip tahunan). Satu entri per device per hari (keputusan
/// user); [date] disimpan sebagai 'yyyy-MM-dd' agar unik per hari.
class CashClosings extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get date => text()(); // 'yyyy-MM-dd'
  TextColumn get deviceCode => text().nullable()();

  /// Kas tunai yang diharapkan (dari penjualan tunai hari itu).
  IntColumn get systemCash => integer()();

  /// Total non-tunai (transfer/QRIS/dll) — informasi, tidak masuk selisih laci.
  IntColumn get systemNonCash => integer().withDefault(const Constant(0))();
  IntColumn get txCount => integer().withDefault(const Constant(0))();

  /// Uang fisik yang dihitung di laci.
  IntColumn get physicalCash => integer()();

  /// physicalCash − systemCash (positif = lebih, negatif = kurang).
  IntColumn get difference => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  /// Satu entri per (tanggal, device).
  @override
  List<Set<Column>> get uniqueKeys => [
        {date, deviceCode}
      ];
}
