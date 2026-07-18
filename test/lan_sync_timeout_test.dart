import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
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

/// Bug dilaporkan user: klien (asisten) tekan "Sync" -> LOADING SELAMANYA,
/// tidak pernah sukses maupun gagal, owner pun tidak pernah lihat konfirmasi
/// apa pun. Root cause: syncToHost() TIDAK PERNAH punya timeout di HTTP
/// request-nya — kalau paket dibuang diam-diam (mis. AP client isolation di
/// WiFi publik/router tertentu) atau host freeze, Future-nya menggantung
/// selamanya.
void main() {
  test(
      'syncToHost timeout kalau host tidak pernah membalas (bukan hang '
      'selamanya) — melempar Exception dalam batas waktu custom',
      () async {
    // Server TCP mentah yang terima koneksi tapi SENGAJA tidak pernah
    // membalas apa pun — simulasi paket dibuang diam-diam / host freeze.
    final raw = await ServerSocket.bind('127.0.0.1', 8625);
    final sub = raw.listen((socket) {
      // Sengaja tidak menulis apa pun & tidak menutup koneksi.
    });

    final clientDb = AppDatabase(NativeDatabase.memory());

    await expectLater(
      _withRealHttp(() => LanSyncService.syncToHost(
            db: clientDb,
            storeKey: 'shared-store-key',
            hostIp: '127.0.0.1',
            syncToken: 'TOKEN',
            connectTimeout: const Duration(milliseconds: 500),
            responseTimeout: const Duration(milliseconds: 500),
          )),
      throwsA(isA<Exception>()),
      reason: 'harus throw (bukan hang selamanya) begitu host tidak '
          'membalas dalam batas waktu',
    );

    await sub.cancel();
    await raw.close();
    await clientDb.close();
  }, timeout: const Timeout(Duration(seconds: 15)));
}
