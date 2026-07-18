import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/ringkasan/ringkasan_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: kartu Ringkasan/Laporan/Pengaturan diberi aksen warna
/// soft sesuai fungsi (Varian B dari mockup — latar kartu penuh ditint,
/// bukan cuma garis/ikon). Test ini membuktikan kartu KPI (uang) dan kartu
/// Kontrol Stok (stok) memakai warna latar yang benar, BUKAN cuma cek teks.
void main() {
  testWidgets(
      'kartu KPI (Hari Ini/Minggu Ini/dst) pakai latar hijau (uang), '
      'kartu Kontrol Stok pakai latar amber (stok)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const RingkasanScreen());

    const isDark = false; // pumpWithFakeApp pakai AppTheme.light()
    final uangBg = AppTheme.changeBg(isDark);
    final stokBg = AppTheme.stockWarnBg(isDark);

    final kpiCards = tester
        .widgetList<Card>(find.byWidgetPredicate((w) => w is Card))
        .where((c) => c.color == uangBg)
        .toList();
    expect(kpiCards.length, 4,
        reason:
            'ke-4 kartu KPI (Hari Ini/Minggu Ini/Bulan Ini/Rata-rata) harus '
            'pakai latar hijau (fungsi Uang & Kas)');

    final stockCards = tester
        .widgetList<Card>(find.byWidgetPredicate((w) => w is Card))
        .where((c) => c.color == stokBg)
        .toList();
    expect(stockCards.length, 1,
        reason: 'kartu Kontrol Stok harus pakai latar amber (fungsi Stok)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
