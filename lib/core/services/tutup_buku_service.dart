import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Hasil eksekusi tutup buku.
class TutupBukuResult {
  const TutupBukuResult({
    required this.archivedYear,
    required this.periodStart,
    required this.periodEnd,
    required this.archivePath,
    required this.txArchived,
  });

  /// Label tahun arsip (`periodEnd.year`) — dipakai sbg nama file
  /// `archive_$archivedYear.db`, tidak berubah dari skema lama walau
  /// periodenya sekarang bisa custom (Item 31: tutup buku tetap SEKALI
  /// PER TAHUN, cuma tanggal akhirnya bisa geser ikut Hari Raya).
  final int archivedYear;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String archivePath;
  final int txArchived;
}

/// Info satu arsip utk ditampilkan di UI (Item 31) — gabungan manifest
/// (kalau ada, presisi) atau fallback kalender-tahun-penuh (arsip lama
/// sebelum fitur tanggal custom ada).
class ArchiveManifestEntry {
  const ArchiveManifestEntry({
    required this.year,
    required this.periodStart,
    required this.periodEnd,
    required this.txCount,
    required this.isLegacyFallback,
  });

  final int year;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int? txCount;

  /// true kalau arsip ini dibuat SEBELUM Item 31 (tidak ada baris manifest
  /// tersimpan) — periodStart/periodEnd di sini cuma ASUMSI kalender-tahun-
  /// penuh (1 Jan–31 Des), bukan tanggal presisi asli.
  final bool isLegacyFallback;
}

/// Service tutup buku.
///
/// Alur:
///   1. Pastikan DailySummaries lengkap untuk periode yang ditutup.
///   2. Salin the_pos.db → archive_YYYY.db (enkripsi identik) — YYYY = tahun
///      `periodEnd`, tetap SEKALI PER TAHUN (Item 31: tanggal custom, bukan
///      selalu 1 Jan, tapi TIDAK berkali-kali setahun).
///   3. Hapus transaksi dalam [periodStart, periodEnd] dari main.db; data
///      master tetap.
///   4. VACUUM main.db agar file mengecil.
///   5. Catat `last_archive_date` (bukan lagi `last_archive_year`) + baris
///      manifest (tanggal presisi + jumlah transaksi) di app_settings.
class TutupBukuService {
  TutupBukuService._();

  static Future<Directory> _appDir() => getApplicationDocumentsDirectory();

  static String _archiveFileName(int year) => 'archive_$year.db';

  static Future<String> archivePath(int year) async {
    final dir = await _appDir();
    return p.join(dir.path, _archiveFileName(year));
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Saran `periodStart` utk tutup buku berikutnya — hari setelah
  /// `periodEnd` tutup buku TERAKHIR (`last_archive_date`), supaya periode
  /// selalu nyambung pas tanpa celah/tumpang tindih. Kalau belum pernah
  /// tutup buku sama sekali, pakai tanggal transaksi PALING LAMA di
  /// database (bukan 1 Januari/tanggal setup toko — hindari rentang kosong
  /// tak berguna di awal). Null kalau database benar-benar belum punya
  /// transaksi sama sekali (tidak ada dasar tanggal apa pun).
  static Future<DateTime?> suggestPeriodStart(AppDatabase db) async {
    final lastDateStr = await db.getSetting('last_archive_date');
    if (lastDateStr != null) {
      final lastDate = DateTime.tryParse(lastDateStr);
      if (lastDate != null) {
        return _dateOnly(lastDate).add(const Duration(days: 1));
      }
    }
    final row = await db
        .customSelect('SELECT MIN(created_at) AS m FROM transactions')
        .getSingleOrNull();
    final minSec = row?.data['m'] as int?;
    if (minSec == null) return null;
    return _dateOnly(DateTime.fromMillisecondsSinceEpoch(minSec * 1000));
  }

  /// Tutup buku periode [periodStart]–[periodEnd] (keduanya INKLUSIF,
  /// dinormalisasi ke tanggal saja — waktu-of-day diabaikan).
  ///
  /// [db] — koneksi ke main.db yang sudah dibuka.
  static Future<TutupBukuResult> execute({
    required AppDatabase db,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final start = _dateOnly(periodStart);
    final end = _dateOnly(periodEnd);
    if (!end.isAfter(start)) {
      throw const TutupBukuException(
          'Tanggal akhir harus setelah tanggal mulai.');
    }
    final year = end.year;

    final dir = await _appDir();
    final mainFile = File(p.join(dir.path, 'the_pos.db'));
    final archiveFile = File(p.join(dir.path, _archiveFileName(year)));

    if (archiveFile.existsSync()) {
      throw TutupBukuException('Arsip tahun $year sudah ada.');
    }

    // 1. Lengkapi DailySummaries agar arsip memiliki ringkasan lengkap.
    await db.backfillMissingSummaries();

    // 2. Hitung jumlah transaksi periode itu sebelum dihapus. periodEnd
    //    INKLUSIF → batas atas eksklusif adalah awal hari SETELAHNYA.
    final periodStartSec = start.millisecondsSinceEpoch ~/ 1000;
    final periodEndExclusiveSec =
        end.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

    final countRow = await db.customSelect(
      'SELECT COUNT(*) AS cnt FROM transactions '
      'WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec',
    ).getSingle();
    final txArchived = (countRow.data['cnt'] as int?) ?? 0;

    // 3. Salin file DB ke arsip (enkripsi identik karena ini copy langsung).
    //    Tutup WAL dulu agar file konsisten saat disalin.
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    await mainFile.copy(archiveFile.path);

    // 4. Hapus data operasional periode itu dari main.db.
    await db.transaction(() async {
      // Snapshot saldo stok terakhir per satuan SEBELUM penghapusan. Produk
      // yang seluruh riwayat stoknya berada di periode yang diarsipkan akan
      // kehilangan semua barisnya — saldonya harus dibawa ke entri baru agar
      // stok tidak ter-reset ke 0.
      final balanceRows = await db.customSelect(
        'SELECT sl.product_unit_id AS uid, sl.stock_after AS bal '
        'FROM stock_ledger sl '
        'WHERE NOT EXISTS ('
        '  SELECT 1 FROM stock_ledger s2 '
        '  WHERE s2.product_unit_id = sl.product_unit_id '
        '  AND (s2.created_at > sl.created_at '
        '       OR (s2.created_at = sl.created_at AND s2.id > sl.id)))',
      ).get();
      final balances = <String, double>{
        for (final r in balanceRows)
          r.data['uid'] as String: (r.data['bal'] as num?)?.toDouble() ?? 0,
      };

      // Hapus child tables dulu (FK).
      await db.customUpdate(
        'DELETE FROM transaction_items WHERE transaction_id IN '
        '(SELECT id FROM transactions '
        ' WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec)',
      );
      await db.customUpdate(
        'DELETE FROM transaction_payments WHERE transaction_id IN '
        '(SELECT id FROM transactions '
        ' WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec)',
      );
      await db.customUpdate(
        'DELETE FROM loyalty_point_ledger '
        'WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec',
      );
      await db.customUpdate(
        'DELETE FROM stock_ledger '
        'WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec',
      );
      await db.customUpdate(
        'DELETE FROM expenses '
        'WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec',
      );
      await db.customUpdate(
        'DELETE FROM transactions '
        'WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec',
      );

      // Bawa saldo stok untuk satuan yang ledger-nya habis terhapus
      // (pergerakan terakhirnya ada di periode yang diarsipkan).
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (final entry in balances.entries) {
        if (entry.value == 0) continue;
        final remain = await db.customSelect(
          'SELECT 1 FROM stock_ledger WHERE product_unit_id = ? LIMIT 1',
          variables: [Variable.withString(entry.key)],
        ).getSingleOrNull();
        if (remain != null) continue; // masih ada riwayat → saldo tetap benar
        await db.customInsert(
          'INSERT INTO stock_ledger '
          '(id, product_unit_id, type, qty_change, stock_after, note, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(const Uuid().v4()),
            Variable.withString(entry.key),
            Variable.withString('adjustment'),
            Variable.withReal(entry.value),
            Variable.withReal(entry.value),
            Variable.withString('Saldo dibawa dari tutup buku $year'),
            Variable.withInt(nowSec),
          ],
        );
      }
    });

    // 5. VACUUM main.db agar file mengecil setelah penghapusan massal.
    await db.customStatement('VACUUM;');

    // 6. Tandai arsip selesai: watermark utk periode BERIKUTNYA + manifest
    //    (tanggal presisi & jumlah transaksi) utk ditampilkan di UI.
    await db.setSetting('last_archive_date', end.toIso8601String());
    await _saveManifestEntry(db,
        year: year, periodStart: start, periodEnd: end, txCount: txArchived);

    return TutupBukuResult(
      archivedYear: year,
      periodStart: start,
      periodEnd: end,
      archivePath: archiveFile.path,
      txArchived: txArchived,
    );
  }

  static const _manifestKey = 'archive_manifest';

  static Future<void> _saveManifestEntry(
    AppDatabase db, {
    required int year,
    required DateTime periodStart,
    required DateTime periodEnd,
    required int txCount,
  }) async {
    final raw = await db.getSetting(_manifestKey);
    final Map<String, dynamic> manifest =
        raw != null ? jsonDecode(raw) as Map<String, dynamic> : {};
    manifest[year.toString()] = {
      'start': periodStart.toIso8601String(),
      'end': periodEnd.toIso8601String(),
      'txCount': txCount,
    };
    await db.setSetting(_manifestKey, jsonEncode(manifest));
  }

  /// Ambil manifest tersimpan (kalau ada) utk tahun arsip [year].
  static Future<Map<String, dynamic>?> _manifestFor(
      AppDatabase db, int year) async {
    final raw = await db.getSetting(_manifestKey);
    if (raw == null) return null;
    final manifest = jsonDecode(raw) as Map<String, dynamic>;
    return manifest[year.toString()] as Map<String, dynamic>?;
  }

  /// Daftar arsip lengkap dgn info tanggal presisi (dari manifest) atau
  /// fallback kalender-tahun-penuh (arsip lama sebelum Item 31 — TETAP
  /// tampil, tidak hilang, cuma ditandai [ArchiveManifestEntry.isLegacyFallback]).
  static Future<List<ArchiveManifestEntry>> listArchiveEntries(
      AppDatabase db) async {
    final years = await listArchivedYears();
    final entries = <ArchiveManifestEntry>[];
    for (final year in years) {
      final m = await _manifestFor(db, year);
      if (m != null) {
        entries.add(ArchiveManifestEntry(
          year: year,
          periodStart: DateTime.parse(m['start'] as String),
          periodEnd: DateTime.parse(m['end'] as String),
          txCount: m['txCount'] as int?,
          isLegacyFallback: false,
        ));
      } else {
        entries.add(ArchiveManifestEntry(
          year: year,
          periodStart: DateTime(year),
          periodEnd: DateTime(year, 12, 31),
          txCount: null,
          isLegacyFallback: true,
        ));
      }
    }
    return entries;
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
