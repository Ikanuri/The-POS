import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Jaring pengaman diagnosis crash: menangkap error yang tidak tertangani
/// (startup maupun pemakaian normal) dan menulisnya ke file lokal di HP —
/// TANPA internet, TANPA minta izin tambahan (folder khusus app yang sudah
/// diizinkan otomatis oleh Android), supaya tetap bisa dibaca via File
/// Manager walau app crash sebelum sempat menampilkan UI apa pun.
///
/// Format JSONL (satu objek JSON per baris) & SELALU append — sengaja
/// TIDAK membaca file lama dulu sebelum menulis, supaya penulisan secepat
/// mungkin dan tahan terhadap jeda sangat singkat sebelum OS benar-benar
/// menghentikan proses yang crash.
class CrashLogService {
  CrashLogService._();

  static const fileName = 'the_pos_crash_log.jsonl';

  /// Bagian JSON murni (testable tanpa I/O nyata).
  static String buildEntry({
    required Object error,
    StackTrace? stack,
    required DateTime time,
    required String context,
  }) {
    return jsonEncode({
      'waktu': time.toIso8601String(),
      'context': context,
      'jenis': error.runtimeType.toString(),
      'pesan': error.toString(),
      'stackTrace': stack?.toString() ?? '',
      'platform': defaultTargetPlatform.name,
    });
  }

  /// Tulis satu entri crash. Best-effort — kegagalan menulis log itu
  /// sendiri TIDAK boleh melempar error baru (bisa bikin loop crash).
  static Future<void> record(
    Object error,
    StackTrace? stack, {
    String context = 'unknown',
  }) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final file = File('${dir.path}/$fileName');
      final line = buildEntry(
        error: error,
        stack: stack,
        time: DateTime.now(),
        context: context,
      );
      file.writeAsStringSync('$line\n',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // Diam saja — ini murni jaring pengaman, bukan fitur inti.
    }
  }

  /// Baca seluruh log tersimpan (utk layar "Log Error Terakhir" di
  /// Pengaturan). null bila belum pernah ada crash tercatat.
  static Future<String?> readAll() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return content.trim().isEmpty ? null : content;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) await file.delete();
    } catch (_) {/* best-effort */}
  }
}
