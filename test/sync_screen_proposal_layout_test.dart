import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';

import 'helpers/pump_app.dart';

/// Bug ditemukan user via screenshot: kartu "Usulan Harga/Produk" di layar
/// Sync WiFi menampilkan IP host & subtitle TERPOTONG VERTIKAL — tiap
/// karakter jadi baris sendiri, menutupi seluruh kartu. Root cause: tombol
/// "Tinjau" (`FilledButton.tonal`) di slot `trailing` ListTile memakai
/// `minimumSize` LEBAR PENUH bawaan `AppTheme` — ListTile menghitung
/// trailing butuh lebar nyaris tak terbatas, meremas title/subtitle jadi
/// ~0px sehingga teks wrap per-karakter (sama pola dgn gotcha CLAUDE.md soal
/// tombol lebar-penuh dalam Row, tapi di sini lewat slot trailing ListTile).
///
/// SENGAJA TIDAK pakai host/HTTP sungguhan (beda dari
/// product_proposal_review_screen_test.dart) — seed `LanSyncService.
/// pendingProposals` langsung via `debugAddProposal` (seam test-only).
/// Beberapa file test lain di suite ini bind port sync tetap (8625) via
/// socket sungguhan; kalau ikut dijalankan konkuren di full-suite (banyak
/// worker paralel), risiko tabrakan/hang di port yang sama — lihat catatan
/// serupa di HANDOFF.md soal lan_sync_*_test.dart. Test render murni ini
/// tidak butuh network sama sekali, jadi hindari risiko itu sepenuhnya.
void main() {
  tearDown(() => LanSyncService.debugClearProposals());

  testWidgets(
      'kartu Usulan Harga/Produk TIDAK overflow di HP sempit — IP & '
      'subtitle tetap 1 baris, bukan terpotong per-karakter', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    // Bangun 1 usulan nyata (row-set asli hasil dumpLocalProposals, bukan
    // data palsu) dari DB asisten simulasi, TANPA sync HTTP sungguhan.
    final asistenDb = AppDatabase(NativeDatabase.memory());
    await asistenDb.into(asistenDb.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Gula'));
    await asistenDb.into(asistenDb.productUnits).insert(
        ProductUnitsCompanion.insert(
            id: 'p1-u', productId: 'p1', isBaseUnit: const Value(true)));
    await asistenDb.into(asistenDb.priceTiers).insert(
        PriceTiersCompanion.insert(
            id: 'p1-t', productUnitId: 'p1-u', price: 12000));
    await asistenDb.markProductLocallyModified('p1');
    final rows = await asistenDb.dumpLocalProposals();
    await asistenDb.close();

    LanSyncService.debugAddProposal(PendingProductProposal(
      id: 'prop1',
      fromIp: '192.168.2.186',
      arrivedAt: DateTime.now(),
      rows: rows,
      productCount: 1,
    ));

    // Layar HP asli (sempit) — surface default flutter_test (~800x600)
    // TIDAK menangkap bug lebar sempit ini, lihat gotcha CLAUDE.md.
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpWithFakeApp(
      tester,
      db: db,
      device: const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Owner',
          deviceCode: 'O1',
          deviceRole: 'owner'),
      child: const SyncScreen(),
    );

    expect(tester.takeException(), isNull,
        reason: 'render overflow/exception krn tombol Tinjau lebar penuh');

    // IP host harus tampil UTUH dalam 1 Text widget (bukan wrap per-karakter
    // jadi berbagai Text 1-huruf) — cari widget Text yg data-nya PERSIS IP.
    final ipTexts = find
        .byWidgetPredicate((w) => w is Text && w.data == '192.168.2.186')
        .evaluate();
    expect(ipTexts, isNotEmpty,
        reason: 'IP host harus tampil sbg 1 baris teks utuh, bukan '
            'terpotong per-karakter (baris demi baris)');

    await db.close();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
