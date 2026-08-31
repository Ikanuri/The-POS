import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';
import 'package:the_pos/features/laci_meja/preorder_quota_store.dart';

/// Fitur baru (permintaan user): garis pembatas kuota per produk di dashboard
/// pre-order — "kiriman normal dari pangkalan itu 70 biji, yang lebih dari 70
/// diberi garis pembatas supaya user tau siapa saja yang harus diprioritaskan".
///
/// Poin kritis yang diuji di sini: garis itu DINAMIS. Kalau ada entri yang
/// dipenuhi di luar urutan, posisi garisnya harus ikut menyesuaikan antrian
/// yang tersisa — bukan angka yang dibekukan sekali saat kuota disetel.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  PreorderEntry entry(String id, double qty, {String productId = 'P1'}) =>
      PreorderEntry(
        id: id,
        productId: productId,
        productUnitId: 'U1',
        customerName: 'Umum',
        qtyOrdered: qty,
        depositQty: 0,
        paid: false,
        locallyModified: false,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  group('preorderIdsBeyondQuota', () {
    test('entri yang melewati kuota ditandai, yang di dalam kuota tidak', () {
      final antrian = [
        entry('a', 30),
        entry('b', 30),
        entry('c', 20), // kumulatif 80 > 70 -> di luar kuota
        entry('d', 5),
      ];
      final beyond = preorderIdsBeyondQuota(antrian, 'P1', 70);
      expect(beyond, {'c', 'd'});
    });

    test('produk lain tidak ikut menghabiskan kuota produk ini', () {
      final antrian = [
        entry('a', 60),
        entry('x', 100, productId: 'P2'),
        entry('b', 5),
      ];
      expect(preorderIdsBeyondQuota(antrian, 'P1', 70), isEmpty,
          reason: 'P2 tidak boleh ikut terhitung ke kuota P1');
    });

    test(
        'DINAMIS: entri di TENGAH antrian dipenuhi (hilang dari daftar '
        'terbuka) -> garis maju, entri yang tadinya di luar kuota masuk',
        () {
      final semula = [entry('a', 30), entry('b', 30), entry('c', 20)];
      expect(preorderIdsBeyondQuota(semula, 'P1', 70), {'c'});

      // 'b' dipenuhi lebih dulu di luar urutan -> hilang dari antrian terbuka.
      final setelahDipenuhi = [entry('a', 30), entry('c', 20)];
      expect(preorderIdsBeyondQuota(setelahDipenuhi, 'P1', 70), isEmpty,
          reason: 'kumulatif tinggal 50, garis pembatas ikut bergeser — '
              'bukan tetap menandai "c" seperti hitungan lama');
    });
  });

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/laci-meja',
      routes: [
        GoRoute(
            path: '/laci-meja',
            builder: (_, __) => const LaciMejaDashboardScreen()),
        GoRoute(
            path: '/kasir/struk/:txId',
            builder: (_, state) => Scaffold(
                body: Text('Struk ${state.pathParameters['txId']}'))),
      ],
    );
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> seedProduct(String id, String name) async {
    await db.into(db.products).insert(ProductsCompanion.insert(id: id, name: name));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U-$id', productId: id, isBaseUnit: const Value(true)));
  }

  testWidgets(
      'kuota aktif + filter produk -> garis "Batas kiriman normal" muncul '
      'di daftar', timeout: const Timeout(Duration(seconds: 40)), (tester) async {
    await seedProduct('P1', 'LPG 3kg');
    // Produk kedua supaya chip filter memang dirender (dgn satu produk saja
    // chip-nya sengaja disembunyikan — tidak ada yang perlu disaring).
    await seedProduct('P2', 'Galon');
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'lain',
          productId: 'P2',
          productUnitId: 'U-P2',
          customerName: 'Pelanggan lain',
          qtyOrdered: 100,
          createdAt: Value(DateTime(2026, 1, 1)),
        ));
    await db.setSetting('preorder_quota_thresholds', '{"P1": 70}');
    for (var i = 0; i < 3; i++) {
      // createdAt ditulis EKSPLISIT (bukan mengandalkan jeda antar insert):
      // `testWidgets` berjalan di fake-clock, jadi `Future.delayed` di dalam
      // body-nya TIDAK PERNAH selesai dan test menggantung sampai timeout.
      await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
            id: 'po$i',
            productId: 'P1',
            productUnitId: 'U-P1',
            customerName: 'Pelanggan $i',
            qtyOrdered: 30, // kumulatif 30/60/90 -> entri ke-3 melewati 70
            createdAt: Value(DateTime(2026, 1, 1 + i)),
          ));
    }

    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Pindah ke kategori Pre-order.
    await tester.tap(find.text('Pre-order').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Tanpa filter produk garis TIDAK muncul (kuota itu per produk).
    final garisSebelumFilter =
        find.textContaining('Batas kiriman normal').evaluate().length;

    // Chip filter produk: labelnya ikut menampilkan kuota yang aktif.
    await tester.tap(find.text('LPG 3kg · maks 70'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final garisSetelahFilter =
        find.text('Batas kiriman normal (70)').evaluate().length;
    final nomorAntrian = find.textContaining('#3').evaluate().length;

    // Drain WAJIB sebelum assert: layar ini punya StreamProvider, dan
    // `tearDown` yang menutup DB saat widget masih mounted bikin test
    // menggantung TANPA BATAS kalau salah satu assert gagal duluan
    // (gotcha CLAUDE.md).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));

    expect(garisSebelumFilter, 0,
        reason: 'kuota itu per produk — tanpa filter produk garisnya tidak '
            'punya makna');
    expect(garisSetelahFilter, 1);
    expect(nomorAntrian, 1,
        reason: 'nomor antrian muncul saat difilter ke satu produk');
  });
}
