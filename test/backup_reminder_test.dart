import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/backup_reminder.dart';

/// Item 13 — logika pengingat backup (cek saat app dibuka).
void main() {
  final now = DateTime(2026, 7, 10, 12);

  group('isOverdue (pure)', () {
    test('belum pernah backup (null) → overdue', () {
      expect(
          BackupReminder.isOverdue(last: null, intervalDays: 7, now: now),
          isTrue);
    });
    test('backup 3 hari lalu, interval 7 → belum overdue', () {
      expect(
          BackupReminder.isOverdue(
              last: now.subtract(const Duration(days: 3)),
              intervalDays: 7,
              now: now),
          isFalse);
    });
    test('backup 7 hari lalu, interval 7 → overdue (>=)', () {
      expect(
          BackupReminder.isOverdue(
              last: now.subtract(const Duration(days: 7)),
              intervalDays: 7,
              now: now),
          isTrue);
    });
    test('backup 2 hari lalu, interval harian(1) → overdue', () {
      expect(
          BackupReminder.isOverdue(
              last: now.subtract(const Duration(days: 2)),
              intervalDays: 1,
              now: now),
          isTrue);
    });
  });

  group('load / record round-trip', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('default: belum pernah backup, otomatis mati, interval 7', () async {
      final s = await BackupReminder.load(db);
      expect(s.last, isNull);
      expect(s.autoEnabled, isFalse);
      expect(s.intervalDays, 7);
      // overdue false karena otomatis MATI (walau belum pernah backup).
      expect(s.overdue, isFalse);
    });

    test('recordBackupNow menyimpan waktu; daysSince ~0', () async {
      await BackupReminder.recordBackupNow(db);
      final s = await BackupReminder.load(db);
      expect(s.last, isNotNull);
      expect(s.daysSince, 0);
    });

    test('otomatis aktif + belum pernah backup → overdue true', () async {
      await BackupReminder.setAutoEnabled(db, true);
      await BackupReminder.setIntervalDays(db, 1);
      final s = await BackupReminder.load(db);
      expect(s.autoEnabled, isTrue);
      expect(s.intervalDays, 1);
      expect(s.overdue, isTrue);
    });

    test('otomatis aktif + baru backup → tidak overdue', () async {
      await BackupReminder.setAutoEnabled(db, true);
      await BackupReminder.recordBackupNow(db);
      final s = await BackupReminder.load(db);
      expect(s.overdue, isFalse);
    });
  });
}
