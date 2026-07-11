import '../database/app_database.dart';

/// Item 13 — pengingat backup berbasis "cek saat app dibuka" (tanpa background
/// service). Menyimpan kapan backup terakhir & apakah pengingat otomatis aktif;
/// bila lewat tenggat, UI menampilkan pengingat (bukan menulis file senyap,
/// yang butuh password tersimpan & path tetap — sengaja dihindari).
class BackupReminder {
  static const kLastBackupKey = 'last_backup_at';
  static const kAutoEnabledKey = 'auto_backup_enabled';
  static const kIntervalKey = 'auto_backup_interval_days';

  /// Catat bahwa backup baru saja berhasil (dipanggil dari alur backup manual).
  static Future<void> recordBackupNow(AppDatabase db) =>
      db.setSetting(kLastBackupKey, DateTime.now().toIso8601String());

  /// Murni: apakah sudah lewat tenggat backup. [last] null = belum pernah.
  static bool isOverdue({
    required DateTime? last,
    required int intervalDays,
    required DateTime now,
  }) {
    if (last == null) return true;
    return now.difference(last).inDays >= intervalDays;
  }

  static Future<BackupStatus> load(AppDatabase db) async {
    final lastRaw = await db.getSetting(kLastBackupKey);
    final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
    final enabled = (await db.getSetting(kAutoEnabledKey)) == '1';
    final interval =
        int.tryParse(await db.getSetting(kIntervalKey) ?? '') ?? 7;
    return BackupStatus(
        last: last, autoEnabled: enabled, intervalDays: interval);
  }

  static Future<void> setAutoEnabled(AppDatabase db, bool v) =>
      db.setSetting(kAutoEnabledKey, v ? '1' : '0');

  static Future<void> setIntervalDays(AppDatabase db, int days) =>
      db.setSetting(kIntervalKey, days.toString());
}

class BackupStatus {
  const BackupStatus({
    required this.last,
    required this.autoEnabled,
    required this.intervalDays,
  });

  final DateTime? last;
  final bool autoEnabled;
  final int intervalDays;

  int? get daysSince =>
      last == null ? null : DateTime.now().difference(last!).inDays;

  /// Pengingat perlu ditampilkan: otomatis aktif DAN sudah lewat tenggat.
  bool get overdue =>
      autoEnabled &&
      BackupReminder.isOverdue(
          last: last, intervalDays: intervalDays, now: DateTime.now());
}
