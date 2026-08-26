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

    // 2b. Guard KRITIS (ditemukan lewat audit efisiensi storage) — Laci Meja
    // (`left_behind_items`/`borrowed_items`/`preorder_entries`) punya kolom
    // `transaction_id` yang FK ke `transactions.id` TANPA `ON DELETE CASCADE`,
    // dan `PRAGMA foreign_keys = ON` aktif. Kalau ADA nota dalam periode yang
    // diarsipkan yang masih punya baris Laci Meja BELUM SELESAI (titip/
    // ketinggalan belum diambil, pinjaman belum kembali penuh, pre-order
    // belum dipenuhi/dibatalkan), menghapus `transactions`-nya akan
    // menabrak "FOREIGN KEY constraint failed" DAN diam-diam membuang jejak
    // tugas operasional yang masih aktif. Blokir dulu, minta owner
    // menyelesaikan/membatalkannya — baris yang SUDAH selesai aman dihapus
    // bersama notanya di langkah 4 (riwayatnya tetap ada di file arsip, yang
    // sudah disalin utuh SEBELUM baris apa pun dihapus).
    final openLaciMejaRow = await db.customSelect(
      'SELECT '
      '(SELECT COUNT(*) FROM left_behind_items lbi '
      '  JOIN transactions t ON t.id = lbi.transaction_id '
      '  WHERE t.created_at >= $periodStartSec AND t.created_at < $periodEndExclusiveSec '
      '  AND lbi.collected_at IS NULL) AS titip, '
      '(SELECT COUNT(*) FROM borrowed_items bi '
      '  JOIN transactions t ON t.id = bi.transaction_id '
      '  WHERE t.created_at >= $periodStartSec AND t.created_at < $periodEndExclusiveSec '
      '  AND bi.fully_returned_at IS NULL) AS pinjaman, '
      '(SELECT COUNT(*) FROM preorder_entries pe '
      '  JOIN transactions t ON t.id = pe.transaction_id '
      '  WHERE t.created_at >= $periodStartSec AND t.created_at < $periodEndExclusiveSec '
      '  AND pe.fulfilled_at IS NULL AND pe.cancelled_at IS NULL) AS preorder',
    ).getSingle();
    final openTitip = (openLaciMejaRow.data['titip'] as int?) ?? 0;
    final openPinjaman = (openLaciMejaRow.data['pinjaman'] as int?) ?? 0;
    final openPreorder = (openLaciMejaRow.data['preorder'] as int?) ?? 0;
    if (openTitip + openPinjaman + openPreorder > 0) {
      final parts = <String>[
        if (openTitip > 0) '$openTitip titip/ketinggalan',
        if (openPinjaman > 0) '$openPinjaman pinjaman belum kembali',
        if (openPreorder > 0) '$openPreorder pre-order belum dipenuhi',
      ];
      throw TutupBukuException(
          'Ada nota dalam periode ini yang masih punya catatan Laci Meja '
          'belum selesai (${parts.join(', ')}). Selesaikan atau batalkan '
          'dulu di Laci Meja sebelum tutup buku periode ini.');
    }

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
      // Snapshot SEBELUM penghapusan, per satuan yang PUNYA baris di periode
      // yang diarsipkan: (a) total qty_change baris² itu (deletedSum) — ini
      // persis kontribusi yang akan HILANG dari total kumulatif kalau nanti
      // `rebuildStockAfterForUnits` (dipanggil sync host/client, lihat dok
      // di sana) menjumlah ulang stock_after dari NOL memakai baris yang
      // TERSISA saja; (b) saldo baris terakhir SEBELUM periode ini
      // (priorBalance) — basis kumulatif sebelum deletedSum ditambahkan.
      // Item 59 fix: SEBELUMNYA baris carry-forward cuma dibuat kalau
      // SELURUH riwayat satuan itu habis terhapus (`remain == null`) —
      // beralasan "saldo tetap benar" utk PEMBACA (`_rawBaseStock` ambil
      // baris TERAKHIR apa adanya, benar walau baris lama dihapus). Tapi
      // itu SALAH utk `rebuildStockAfterForUnits`, yang menjumlah ulang qty
      // dari nol — kalau ada baris SEBELUM/SESUDAH periode yang bertahan,
      // kontribusi baris yang dihapus tetap harus dibawa (deletedSum),
      // bukan cuma dilewati begitu saja. Sekarang SELALU sisipkan 1 baris
      // penyeimbang per satuan yang punya deletedSum != 0, terlepas dari
      // ada/tidaknya baris yang bertahan.
      final deletedSumRows = await db.customSelect(
        'SELECT product_unit_id AS uid, SUM(qty_change) AS total '
        'FROM stock_ledger '
        'WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec '
        'GROUP BY product_unit_id',
      ).get();
      final deletedSums = <String, double>{
        for (final r in deletedSumRows)
          r.data['uid'] as String: (r.data['total'] as num?)?.toDouble() ?? 0,
      };

      final priorBalanceRows = await db.customSelect(
        'SELECT sl.product_unit_id AS uid, sl.stock_after AS bal '
        'FROM stock_ledger sl '
        'WHERE sl.created_at < $periodStartSec '
        'AND NOT EXISTS ('
        '  SELECT 1 FROM stock_ledger s2 '
        '  WHERE s2.product_unit_id = sl.product_unit_id '
        '  AND s2.created_at < $periodStartSec '
        '  AND (s2.created_at > sl.created_at '
        '       OR (s2.created_at = sl.created_at AND s2.id > sl.id)))',
      ).get();
      final priorBalances = <String, double>{
        for (final r in priorBalanceRows)
          r.data['uid'] as String: (r.data['bal'] as num?)?.toDouble() ?? 0,
      };

      // Hapus child tables dulu (FK). Laci Meja SELALU aman dihapus di sini
      // — guard di langkah 2b sudah memastikan TIDAK ADA baris yang masih
      // terbuka (belum selesai) di antara nota-nota periode ini.
      //
      // Log kejadian DULUAN sebelum 3 tabel induknya (PLAN.md Item 54):
      // `entry_id` menunjuk baris induk tapi BUKAN FK fisik (polimorfik),
      // jadi SQLite tidak akan menghalangi maupun membersihkan sendiri —
      // kalau induknya dihapus lebih dulu, baris log ini tertinggal jadi
      // yatim PERMANEN dan menumpuk tiap tutup buku. Riwayatnya sendiri
      // tetap utuh di file arsip (sudah disalin SEBELUM penghapusan apa pun).
      await db.customUpdate(
        'DELETE FROM laci_meja_events WHERE entry_id IN ('
        ' SELECT id FROM left_behind_items WHERE transaction_id IN '
        '  (SELECT id FROM transactions '
        '   WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec)'
        ' UNION ALL'
        ' SELECT id FROM borrowed_items WHERE transaction_id IN '
        '  (SELECT id FROM transactions '
        '   WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec)'
        ' UNION ALL'
        ' SELECT id FROM preorder_entries WHERE transaction_id IN '
        '  (SELECT id FROM transactions '
        '   WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec)'
        ')',
      );
      await db.customUpdate(
        'DELETE FROM left_behind_items WHERE transaction_id IN '
        '(SELECT id FROM transactions '
        ' WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec)',
      );
      await db.customUpdate(
        'DELETE FROM borrowed_items WHERE transaction_id IN '
        '(SELECT id FROM transactions '
        ' WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec)',
      );
      await db.customUpdate(
        'DELETE FROM preorder_entries WHERE transaction_id IN '
        '(SELECT id FROM transactions '
        ' WHERE created_at >= $periodStartSec AND created_at < $periodEndExclusiveSec)',
      );
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

      // Bawa kontribusi baris yang terhapus ke SATU baris penyeimbang per
      // satuan, ditanggal PAS di batas akhir periode (bukan `DateTime.now()`
      // — WAJIB lebih awal dari baris apa pun yang bertahan SETELAH periode
      // ini, supaya urutan kronologis `rebuildStockAfterForUnits` benar).
      final carryForwardSec = periodEndExclusiveSec - 1;
      for (final entry in deletedSums.entries) {
        if (entry.value == 0) continue;
        final prior = priorBalances[entry.key] ?? 0;
        final newStockAfter = prior + entry.value;
        await db.customInsert(
          'INSERT INTO stock_ledger '
          '(id, product_unit_id, type, qty_change, stock_after, note, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          variables: [
            Variable.withString(const Uuid().v4()),
            Variable.withString(entry.key),
            Variable.withString('adjustment'),
            Variable.withReal(entry.value),
            Variable.withReal(newStockAfter),
            Variable.withString('Saldo dibawa dari tutup buku $year'),
            Variable.withInt(carryForwardSec),
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
