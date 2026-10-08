import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/kasir_sticker_service.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';
import 'package:the_pos/features/pengaturan/kasir_sticker_sheet.dart';

/// Lembar "Stiker Animasi Kasir": dua tempat, status Bawaan/Unggahan sendiri,
/// tombol Bawaan (reset) hanya muncul untuk unggahan. Pemilih berkas asli
/// tidak diuji (platform); validasi/simpan diuji di kasir_landing_test.
void main() {
  testWidgets('dua slot tampil; reset muncul hanya untuk unggahan sendiri',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Tanpa animasi berulang di test; thumbnail memakai ikon cadangan.
        kasirStickerProvider.overrideWith((ref, slot) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirStickerSheet()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Landing Kasir'), findsOneWidget);
    expect(find.text('Produk tidak ditemukan'), findsOneWidget);
    expect(find.text('Bawaan'), findsNWidgets(2)); // subtitle status
    expect(find.byKey(const ValueKey('kasir-sticker-pick-landing')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('kasir-sticker-reset-landing')),
        findsNothing);

    // Simulasikan unggahan lalu buka ulang lembar.
    await KasirStickerService.setCustom(db, KasirStickerSlot.landing,
        File('assets/stickers/closed.tgs').readAsBytesSync());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        kasirStickerProvider.overrideWith((ref, slot) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirStickerSheet()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Unggahan sendiri'), findsOneWidget);
    expect(find.byKey(const ValueKey('kasir-sticker-reset-landing')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kasir-sticker-reset-landing')));
    await tester.pumpAndSettle();
    expect(await KasirStickerService.isCustom(db, KasirStickerSlot.landing),
        isFalse);
    expect(find.byKey(const ValueKey('kasir-sticker-reset-landing')),
        findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
