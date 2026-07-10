import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

import 'helpers/pump_app.dart';

/// Test Tier 2 (widget) — membuktikan topbar kasir TIDAK overflow setelah
/// tombol baru "Tempel Pesanan" (fitur eksperimental Fase 2) ditambahkan ke
/// baris ikon. CLAUDE.md mencatat baris ikon topbar ini historis rawan
/// overflow ketika tombol baru ditambahkan tanpa dites di layar sempit.
void main() {
  testWidgets(
      'topbar kasir tidak overflow di lebar HP sempit (360dp) setelah '
      'tombol Tempel Pesanan ditambahkan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    FlutterError? caughtError;
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      caughtError ??= details.exception is FlutterError
          ? details.exception as FlutterError
          : null;
      originalOnError?.call(details);
    };

    await pumpWithFakeApp(
      tester,
      db: db,
      child: const KasirScreen(),
      surfaceSize: const Size(360, 800),
    );

    FlutterError.onError = originalOnError;

    expect(find.byIcon(Icons.content_paste_go_rounded), findsOneWidget,
        reason: 'tombol Tempel Pesanan harus tampil di mode kasir normal');
    expect(caughtError, isNull,
        reason: 'topbar tidak boleh melempar RenderFlex overflow di lebar '
            'sempit');

    await db.close();
  });
}
