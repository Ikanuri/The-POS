import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/crypto_service.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Lihat catatan sama di lan_sync_watermark_test.dart soal kenapa perlu
/// escape ganda HttpOverrides di sini.
Future<T> _withRealHttp<T>(Future<T> Function() body) => HttpOverrides.runZoned(
      body,
      createHttpClient: (context) => Zone.root.run(() {
        final prevGlobal = HttpOverrides.current;
        HttpOverrides.global = null;
        try {
          return HttpClient(context: context);
        } finally {
          HttpOverrides.global = prevGlobal;
        }
      }),
    );

/// Bug dilaporkan user SETELAH fix timeout pertama (939048a): transfer yang
/// SEDANG AKTIF mengalir (toko dgn data besar / WiFi lambat) tetap terputus
/// paksa kalau total durasinya melebihi timeout — padahal datanya terus
/// nyampe, bukan macet. Root cause: `.timeout()` dipasang di atas
/// `Future<List<int>>` hasil `.toList()` (deadline TOTAL, tidak peduli
/// progres), seharusnya di atas `Stream<int>` SEBELUM `.toList()` (timeout
/// PER-EVENT/idle, reset tiap ada chunk baru lewat).
void main() {
  test(
      'syncToHost TIDAK memutus transfer yang lambat tapi terus mengalir '
      '(total durasi > timeout, tapi tiap jeda antar-chunk < timeout)',
      () async {
    const storeKey = 'shared-store-key';
    const syncToken = 'TESTTOKEN';
    final key = CryptoService.deriveSyncKey(storeKey, syncToken);

    final respPayload = {
      'tables': <String, Object?>{},
      'since': DateTime.now().toIso8601String(),
      'pendingId': 'p1',
      'status': 'ok',
    };
    final encrypted = CryptoService.encryptText(jsonEncode(respPayload), key);
    final bodyBytes = base64Decode(encrypted);

    final header = utf8.encode('HTTP/1.1 200 OK\r\n'
        'Content-Type: application/octet-stream\r\n'
        'Content-Length: ${bodyBytes.length}\r\n'
        'Connection: close\r\n'
        '\r\n');

    final raw = await ServerSocket.bind('127.0.0.1', 8625);
    final sub = raw.listen((socket) async {
      // Habiskan request masuk (tidak perlu diparse utk test ini).
      await socket.first.catchError((_) => Uint8List(0));
      socket.add(header);
      await socket.flush();
      // Kirim body dalam beberapa potongan kecil dgn jeda ANTAR-chunk yang
      // masing-masing < idle timeout, tapi TOTAL semua jeda > total timeout
      // gaya lama — buktikan transfer lambat-tapi-progresif tetap selesai.
      const chunks = 5;
      final chunkSize = (bodyBytes.length / chunks).ceil();
      for (var i = 0; i < bodyBytes.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, bodyBytes.length);
        socket.add(bodyBytes.sublist(i, end));
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      await socket.close();
    });

    final clientDb = AppDatabase(NativeDatabase.memory());

    // Idle timeout 800ms: tiap jeda antar-chunk (300ms) di bawahnya, TAPI
    // total waktu transfer (5 chunk x 300ms = ~1.5s) MELEBIHI 800ms —
    // dgn fix (Stream.timeout SEBELUM toList), ini harus tetap SUKSES.
    final result = await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: storeKey,
          hostIp: '127.0.0.1',
          syncToken: syncToken,
          connectTimeout: const Duration(seconds: 2),
          responseTimeout: const Duration(milliseconds: 800),
        ));

    expect(result.pendingApproval, isFalse);

    await sub.cancel();
    await raw.close();
    await clientDb.close();
  }, timeout: const Timeout(Duration(seconds: 15)));
}
