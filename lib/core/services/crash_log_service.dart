import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Jaring pengaman diagnosis crash: menangkap error yang tidak tertangani
/// (startup maupun pemakaian normal) dan menulisnya ke file lokal di HP —
/// TANPA internet, TANPA minta izin tambahan.
///
/// Ditulis di 2 lokasi:
/// 1. Folder khusus app via `path_provider` (`getExternalStorageDirectory`)
///    — cara awal, TANPA platform channel jadi tetap jalan walau
///    MethodChannel gagal (mis. Flutter engine sedang teardown). TAPI:
///    Android 11+ MEMBLOKIR File Manager pihak ketiga (termasuk "Files by
///    Google") dari melihat ISI folder `Android/data/<package>/` app lain
///    — biasanya tampil "kosong" walau filenya beneran ada. Ini akar
///    masalah nyata yang ditemukan user: melapor filenya "tidak ada
///    sama sekali" padahal cuma tersembunyi oleh restriksi OS.
/// 2. Folder Downloads PUBLIK via native (`CrashLogWriter.kt`, MediaStore
///    API 29+, lewat MethodChannel `com.thepos/crash_log`) — TIDAK kena
///    restriksi di atas, terlihat File Manager mana pun tanpa syarat.
///    `readAll()` PRIORITASKAN sumber ini (lebih pasti terlihat user).
///
/// Format JSONL (satu objek JSON per baris) & SELALU append — sengaja
/// TIDAK membaca file lama dulu sebelum menulis, supaya penulisan secepat
/// mungkin dan tahan terhadap jeda sangat singkat sebelum OS benar-benar
/// menghentikan proses yang crash.
class CrashLogService {
  CrashLogService._();

  static const fileName = 'the_pos_crash_log.jsonl';
  static const _channel = MethodChannel('com.thepos/crash_log');

  /// Item 41 B.4 — file log ada di Downloads PUBLIK (keputusan sadar agar
  /// pasti terlihat user, lihat dok kelas); batasi panjang pesan & stack
  /// supaya exception yang kebetulan membawa data (mis. isi SQL) tidak
  /// menumpahkan data toko bulat-bulat ke file publik. Batasnya longgar —
  /// cukup utk diagnosis, bukan sensor.
  static const _maxPesanChars = 2000;
  static const _maxStackChars = 6000;

  static String _cap(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...[dipotong]';

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
      'pesan': _cap(error.toString(), _maxPesanChars),
      'stackTrace': _cap(stack?.toString() ?? '', _maxStackChars),
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
    final line = buildEntry(
      error: error,
      stack: stack,
      time: DateTime.now(),
      context: context,
    );

    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final file = File('${dir.path}/$fileName');
        file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
      }
    } catch (_) {
      // Diam saja — ini murni jaring pengaman, bukan fitur inti.
    }

    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('append', {'json': line});
      } catch (_) {
        // Best-effort — mis. engine sedang teardown saat crash terjadi.
      }
    }
  }

  /// Baca seluruh log tersimpan (utk layar "Log Error Terakhir" di
  /// Pengaturan). null bila belum pernah ada crash tercatat. Prioritaskan
  /// folder Downloads publik (lebih pasti terlihat user), jatuh ke folder
  /// khusus app kalau itu tidak tersedia/kosong.
  static Future<String?> readAll() async {
    if (Platform.isAndroid) {
      try {
        final downloads = await _channel.invokeMethod<String>('readDownloads');
        if (downloads != null && downloads.trim().isNotEmpty) return downloads;
      } catch (_) {
        // Jatuh ke folder khusus app di bawah.
      }
    }
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
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('clearDownloads');
      } catch (_) {/* best-effort */}
    }
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) await file.delete();
    } catch (_) {/* best-effort */}
  }
}
