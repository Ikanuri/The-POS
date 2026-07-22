import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';
import 'package:the_pos/features/ringkasan/ringkasan_screen.dart';
import 'package:the_pos/features/shell/sync_status_banner.dart';

import 'helpers/pump_app.dart';

/// Follow-up posisi (laporan nyata user): `SyncStatusBanner` dulu dipasang
/// SEKALI di `MainShell`, mengambang di ATAS setiap layar tab (termasuk di
/// atas AppBar/toolbar masing-masing) — user bilang ini "belum inline"
/// dibanding notifikasi lain (mis. banner "Pesanan ditahan" yg tampil DI
/// BAWAH toolbar Kasir). Sekarang dipasang LANGSUNG di tiap layar tab, tepat
/// di bawah AppBar/toolbar masing-masing — test ini membuktikan posisinya
/// (bukan cuma keberadaannya) di 3 layar dgn struktur body berbeda (Kasir:
/// toolbar custom, Pengaturan: ListView, Ringkasan: RefreshIndicator).
void main() {
  tearDown(() => LanSyncService.debugClearProposals());

  Future<void> seedOngoingProposal() async {
    LanSyncService.debugAddProposal(PendingProductProposal(
      id: 'p1',
      fromIp: '192.168.1.50',
      arrivedAt: DateTime.now(),
      rows: const {},
      productCount: 1,
    ));
  }

  testWidgets(
      'Kasir: SyncStatusBanner tampil DI BAWAH toolbar (bukan di atas '
      'layar/AppBar)', (tester) async {
    await seedOngoingProposal();
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    expect(find.byType(SyncStatusBanner), findsOneWidget);
    final bannerTop = tester.getTopLeft(find.byType(SyncStatusBanner)).dy;
    final searchFieldTop =
        tester.getTopLeft(find.byType(TextField).first).dy;
    // Toolbar (berisi search field) HARUS berada DI ATAS banner — banner
    // muncul setelahnya, bukan menutupi/mendorongnya dari atas layar.
    expect(bannerTop, greaterThan(searchFieldTop),
        reason: 'banner sync harus di BAWAH toolbar kasir (spt notifikasi '
            'inline lain di layar ini), bukan mengambang di atas segalanya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'Pengaturan: SyncStatusBanner tampil DI BAWAH AppBar', (tester) async {
    await seedOngoingProposal();
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());

    expect(find.byType(SyncStatusBanner), findsOneWidget);
    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final bannerTop = tester.getTopLeft(find.byType(SyncStatusBanner)).dy;
    expect(bannerTop, greaterThanOrEqualTo(appBarBottom),
        reason: 'banner sync harus di bawah AppBar, bukan menimpanya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'Ringkasan: SyncStatusBanner tampil DI BAWAH AppBar', (tester) async {
    await seedOngoingProposal();
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const RingkasanScreen());

    expect(find.byType(SyncStatusBanner), findsOneWidget);
    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final bannerTop = tester.getTopLeft(find.byType(SyncStatusBanner)).dy;
    expect(bannerTop, greaterThanOrEqualTo(appBarBottom),
        reason: 'banner sync harus di bawah AppBar, bukan menimpanya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
