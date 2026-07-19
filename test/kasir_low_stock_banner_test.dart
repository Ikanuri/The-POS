import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/low_stock_alert_provider.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

import 'helpers/pump_app.dart';

/// Item 46 — saat antrian `pendingLowStockAlertsProvider` terisi (di-set oleh
/// payment_screen setelah checkout) DAN kasir jadi rute teratas, banner inline
/// stok menipis muncul di layar kasir, lalu antriannya dikuras.
void main() {
  testWidgets(
      'antrian stok menipis terisi → banner muncul di kasir & antrian dikuras',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
        tester.element(find.byType(KasirScreen)),
        listen: false);

    // Belum ada peringatan → tidak ada banner.
    expect(find.textContaining('stok menipis'), findsNothing);

    // Simulasikan payment_screen mengisi antrian pasca-checkout.
    container.read(pendingLowStockAlertsProvider.notifier).state = [
      'Stok Gula menipis: sisa 5 Biji (0.25 Pak)'
    ];
    // Rebuild (watch) + post-frame drain + setState banner.
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Stok Gula menipis: sisa 5 Biji'),
        findsOneWidget,
        reason: 'banner stok menipis harus tampil di kasir');
    expect(container.read(pendingLowStockAlertsProvider), isEmpty,
        reason: 'antrian dikuras setelah ditampilkan (tidak muncul 2x)');

    // Drain drift StreamProvider + banner timer sebelum test selesai.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
