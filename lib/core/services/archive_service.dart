import 'dart:io';

import 'package:drift/native.dart';

import '../database/app_database.dart';
import 'tutup_buku_service.dart';

/// Informasi ringkasan satu file arsip.
class ArchiveInfo {
  const ArchiveInfo({
    required this.year,
    required this.path,
    required this.sizeBytes,
    required this.summaryCount,
    required this.txCount,
  });

  final int year;
  final String path;
  final int sizeBytes;
  final int summaryCount;
  final int txCount;
}

/// Buka file arsip tahunan sebagai AppDatabase read-only.
///
/// SQLCipher sudah dimuat di main isolat (via applyWorkaroundToOpenSqlCipher…
/// di main.dart), sehingga NativeDatabase langsung bekerja tanpa isolateSetup.
class ArchiveService {
  ArchiveService._();

  static AppDatabase? _current;
  static int? _currentYear;

  static int? get openYear => _currentYear;
  static AppDatabase? get db => _current;

  /// Buka arsip [year] sebagai AppDatabase.
  /// Jika arsip lain sedang terbuka, akan ditutup terlebih dahulu.
  static Future<AppDatabase> open(int year, String encryptionKey) async {
    await close();
    final path = await TutupBukuService.archivePath(year);
    if (!File(path).existsSync()) {
      throw TutupBukuException('Arsip tahun $year tidak ditemukan.');
    }
    final executor = NativeDatabase(
      File(path),
      setup: (rawDb) {
        // Key arsip selalu hex murni; validasi mencegah injeksi via PRAGMA.
        if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(encryptionKey)) {
          throw ArgumentError(
              'Encryption key harus hex murni; nilai tidak valid ditolak.');
        }
        rawDb.execute("PRAGMA key = '$encryptionKey';");
        rawDb.execute('PRAGMA query_only = ON;');
        rawDb.execute('PRAGMA cache_size = -8192;');
        rawDb.execute('PRAGMA temp_store = MEMORY;');
      },
    );
    _current = AppDatabase(executor, readOnly: true);
    _currentYear = year;
    return _current!;
  }

  /// Tutup koneksi arsip yang sedang terbuka.
  static Future<void> close() async {
    if (_current != null) {
      await _current!.close();
      _current = null;
      _currentYear = null;
    }
  }

  /// Buat daftar ArchiveInfo untuk semua arsip yang ada.
  static Future<List<ArchiveInfo>> listArchives(String encryptionKey) async {
    final years = await TutupBukuService.listArchivedYears();
    final infos = <ArchiveInfo>[];
    for (final year in years) {
      final path = await TutupBukuService.archivePath(year);
      final file = File(path);
      final size = file.existsSync() ? await file.length() : 0;
      int summaryCount = 0, txCount = 0;
      try {
        final archiveDb = await open(year, encryptionKey);
        final sRow = await archiveDb
            .customSelect('SELECT COUNT(*) AS cnt FROM daily_summaries')
            .getSingle();
        summaryCount = (sRow.data['cnt'] as int?) ?? 0;
        final tRow = await archiveDb
            .customSelect('SELECT COUNT(*) AS cnt FROM transactions')
            .getSingle();
        txCount = (tRow.data['cnt'] as int?) ?? 0;
      } catch (_) {
      } finally {
        await close();
      }
      infos.add(ArchiveInfo(
        year: year,
        path: path,
        sizeBytes: size,
        summaryCount: summaryCount,
        txCount: txCount,
      ));
    }
    return infos;
  }
}
