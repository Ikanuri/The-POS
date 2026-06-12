import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

/// Hasil eksekusi tutup buku.
class TutupBukuResult {
  const TutupBukuResult({
    required this.archivedYear,
    required this.archivePath,
    required this.txArchived,
  });

  final int archivedYear;
  final String archivePath;
  final int txArchived;
}

/// Service tutup buku tahunan.
///
/// Alur:
///   1. Pastikan DailySummaries lengkap untuk tahun yang ditutup.
///   2. Salin the_pos.db → archive_YYYY.db (enkripsi identik).
///   3. Hapus transaksi tahun itu dari main.db; data master tetap.
///   4. VACUUM main.db agar file mengecil.
///   5. Catat last_archive_year di app_settings.
class TutupBukuService {
  TutupBukuService._();

  static Future<Directory> _appDir() => getApplicationDocumentsDirectory();

  static String _archiveFileName(int year) => 'archive_$year.db';

  static Future<String> archivePath(int year) async {
    final dir = await _appDir();
    return p.join(dir.path, _archiveFileName(year));
  }

  /// Tutup buku tahun [year].
  ///
  /// [db] — koneksi ke main.db yang sudah dibuka.
  static Future<TutupBukuResult> execute({
    required AppDatabase db,
    required int year,
  }) async {
    final dir = await _appDir();
    final mainFile = File(p.join(dir.path, 'the_pos.db'));
    final archiveFile = File(p.join(dir.path, _archiveFileName(year)));

    if (archiveFile.existsSync()) {
      throw TutupBukuException('Arsip tahun $year sudah ada.');
    }

    // 1. Lengkapi DailySummaries agar arsip memiliki ringkasan lengkap.
    await db.backfillMissingSummaries();

    // 2. Hitung jumlah transaksi tahun itu sebelum dihapus.
    final yearStartSec = DateTime(year).millisecondsSinceEpoch ~/ 1000;
    final yearEndSec = DateTime(year + 1).millisecondsSinceEpoch ~/ 1000;

    final countRow = await db.customSelect(
      'SELECT COUNT(*) AS cnt FROM transactions '
      'WHERE created_at >= $yearStartSec AND created_at < $yearEndSec',
    ).getSingle();
    final txArchived = (countRow.data['cnt'] as int?) ?? 0;

    // 3. Salin file DB ke arsip (enkripsi identik karena ini copy langsung).
    //    Tutup WAL dulu agar file konsisten saat disalin.
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    await mainFile.copy(archiveFile.path);

    // 4. Hapus data operasional tahun itu dari main.db.
    await db.transaction(() async {
      // Hapus child tables dulu (FK).
      await db.customUpdate(
        'DELETE FROM transaction_items WHERE transaction_id IN '
        '(SELECT id FROM transactions '
        ' WHERE created_at >= $yearStartSec AND created_at < $yearEndSec)',
      );
      await db.customUpdate(
        'DELETE FROM transaction_payments WHERE transaction_id IN '
        '(SELECT id FROM transactions '
        ' WHERE created_at >= $yearStartSec AND created_at < $yearEndSec)',
      );
      await db.customUpdate(
        'DELETE FROM loyalty_point_ledger '
        'WHERE created_at >= $yearStartSec AND created_at < $yearEndSec',
      );
      await db.customUpdate(
        'DELETE FROM stock_ledger '
        'WHERE created_at >= $yearStartSec AND created_at < $yearEndSec',
      );
      await db.customUpdate(
        'DELETE FROM expenses '
        'WHERE created_at >= $yearStartSec AND created_at < $yearEndSec',
      );
      await db.customUpdate(
        'DELETE FROM transactions '
        'WHERE created_at >= $yearStartSec AND created_at < $yearEndSec',
      );
    });

    // 5. VACUUM main.db agar file mengecil setelah penghapusan massal.
    await db.customStatement('VACUUM;');

    // 6. Tandai arsip selesai.
    await db.setSetting('last_archive_year', year.toString());

    return TutupBukuResult(
      archivedYear: year,
      archivePath: archiveFile.path,
      txArchived: txArchived,
    );
  }

  /// Cek apakah arsip untuk tahun tertentu sudah ada.
  static Future<bool> archiveExists(int year) async {
    final path = await archivePath(year);
    return File(path).existsSync();
  }

  /// Daftar semua tahun yang sudah diarsipkan.
  static Future<List<int>> listArchivedYears() async {
    final dir = await _appDir();
    final years = <int>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          final match = RegExp(r'^archive_(\d{4})\.db$').firstMatch(name);
          if (match != null) {
            years.add(int.parse(match.group(1)!));
          }
        }
      }
    } catch (_) {}
    years.sort();
    return years;
  }

  /// Hapus file arsip tahun tertentu (konfirmasi manual dari user sebelum dipanggil).
  static Future<void> deleteArchive(int year) async {
    final path = await archivePath(year);
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}

class TutupBukuException implements Exception {
  const TutupBukuException(this.message);
  final String message;
  @override
  String toString() => 'TutupBukuException: $message';
}
