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

    test(
        'PEMENUHAN SEBAGIAN (bukan hilang dari daftar) juga mengurangi '
        'kumulatif — bukan cuma pemenuhan penuh',
        () {
      // Dilaporkan user via screenshot: entri ke-3 (5 dari kuota 4) tetap
      // "tidak naik" walau salah satu entri SEBELUMNYA sudah dipenuhi
      // sebagian (bukan penuh, jadi tetap ada di daftar terbuka).
      final antrian = [entry('a', 1), entry('b', 1), entry('c', 5)];
      expect(preorderIdsBeyondQuota(antrian, 'P1', 4), {'c'},
          reason: 'kumulatif penuh 1+1+5=7 > 4');

      // 'c' sendiri dipenuhi 4 dari 5 (progress bar "Dipenuhi 4 dari 5") —
      // sisa yang MASIH membebani kuota tinggal 1, bukan 5 lagi.
      expect(
          preorderIdsBeyondQuota(antrian, 'P1', 4,
              takenQty: {'c': 4}),
          isEmpty,
          reason: 'sisa "c" tinggal 1 -> kumulatif sisa 1+1+1=3, tidak lagi '
              'melewati kuota 4');
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
      'HANYA SATU produk yang diantri (chip filter sengaja disembunyikan) -> '
      'garis pembatas TETAP muncul tanpa perlu memilih filter apa pun',
      timeout: const Timeout(Duration(seconds: 40)), (tester) async {
    // Kondisi paling lazim di toko: cuma LPG yang punya antrian. Dulu garis
    // pembatasnya tidak pernah muncul di sini krn perhitungannya menunggu
    // filter produk dipilih, padahal chip-nya memang tidak dirender.
    await seedProduct('P1', 'LPG 3kg');
    await db.setSetting('preorder_quota_thresholds', '{"P1": 2}');
    for (var i = 0; i < 3; i++) {
      await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
            id: 'po$i',
            productId: 'P1',
            productUnitId: 'U-P1',
            customerName: 'Pelanggan $i',
            qtyOrdered: 1, // kumulatif 1/2/3 -> entri ke-3 melewati 2
            createdAt: Value(DateTime(2026, 1, 1 + i)),
          ));
    }

    // Surface generus (konvensi CLAUDE.md) — panel filter+statistik yang
    // lebih tinggi (redesain permintaan user) bisa mendorong entri terakhir
    // di ListView keluar viewport 800x600 default, dan ListView.separated
    // lazy-build item di luar viewport (tidak akan ditemukan finder).
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Pre-order').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final chips = find.byType(ChoiceChip).evaluate().length;
    final garis = find.text('Batas kiriman (2)').evaluate().length;
    final nomorAntrian = find.textContaining('#3').evaluate().length;

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));

    expect(chips, 0, reason: 'satu produk saja -> chip filter disembunyikan');
    expect(garis, 1,
        reason: 'garis pembatas tetap harus muncul walau filter produk tidak '
            'bisa dipilih');
    expect(nomorAntrian, 1, reason: 'nomor antrian ikut muncul');
  });

  testWidgets(
      'kuota aktif + filter produk -> garis "Batas kiriman" muncul '
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

    // Surface generus (konvensi CLAUDE.md) — panel filter+statistik yang
    // lebih tinggi (redesain permintaan user) bisa mendorong entri terakhir
    // di ListView keluar viewport 800x600 default, dan ListView.separated
    // lazy-build item di luar viewport (tidak akan ditemukan finder).
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Pindah ke kategori Pre-order.
    await tester.tap(find.text('Pre-order').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Tanpa filter produk garis TIDAK muncul (kuota itu per produk).
    final garisSebelumFilter =
        find.textContaining('Batas kiriman').evaluate().length;

    // Chip filter produk: labelnya ikut menampilkan kuota yang aktif.
    // `ensureVisible` WAJIB — chip ada di dalam `SingleChildScrollView`
    // horizontal yang bisa memotong kontennya di luar viewport awal; tap ke
    // posisi ter-clip itu jatuh ke widget LAIN yang kebetulan ada di
    // koordinat yang sama (di sini: tombol "Kuota" di sebelahnya).
    await tester.ensureVisible(find.text('LPG 3kg · maks 70'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('LPG 3kg · maks 70'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final garisSetelahFilter =
        find.text('Batas kiriman (70)').evaluate().length;
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

  testWidgets(
      'pemenuhan sebagian: baris & statistik tampilkan SISA (bukan angka '
      'awal), dan entri di bawah kuota ikut naik kalau sisanya sudah cukup',
      timeout: const Timeout(Duration(seconds: 40)), (tester) async {
    // Reproduksi skenario screenshot user: kuota 4, tiga entri (1, 1, 5) —
    // entri ke-3 (Abdul Ghani) awalnya di bawah garis krn kumulatif penuh
    // 1+1+5=7 > 4. Begitu 4 dari 5 tabungnya sendiri dipenuhi (progress bar
    // "Dipenuhi 4 dari 5"), sisa yang membebani kuota tinggal 1 — kumulatif
    // sisa jadi 1+1+1=3, harusnya TIDAK lagi melewati kuota.
    await seedProduct('P1', 'Lpg');
    await db.setSetting('preorder_quota_thresholds', '{"P1": 4}');
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'sum',
          productId: 'P1',
          productUnitId: 'U-P1',
          customerName: 'Sum',
          qtyOrdered: 1,
          depositQty: const Value(1),
          createdAt: Value(DateTime(2026, 1, 1)),
        ));
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'kampong',
          productId: 'P1',
          productUnitId: 'U-P1',
          customerName: 'Buk Kampong',
          qtyOrdered: 1,
          depositQty: const Value(1),
          createdAt: Value(DateTime(2026, 1, 2)),
        ));
    await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
          id: 'ghani',
          productId: 'P1',
          productUnitId: 'U-P1',
          customerName: 'Abdul Ghani',
          qtyOrdered: 5,
          depositQty: const Value(5),
          createdAt: Value(DateTime(2026, 1, 3)),
        ));

    // Surface generus (konvensi CLAUDE.md) — panel filter+statistik yang
    // lebih tinggi (redesain permintaan user) bisa mendorong entri terakhir
    // di ListView keluar viewport 800x600 default, dan ListView.separated
    // lazy-build item di luar viewport (tidak akan ditemukan finder).
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Pre-order').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Statistik sekarang chip mini "Produk: N" (`_StatChip`) + chip jaminan
    // yang menampilkan LANGSUNG satu produk ("Lpg: N", produk tunggal di
    // sini jadi tanpa dropdown) + total keseluruhan sbg teks polos "N
    // jaminan" di sebelahnya — lihat `_PreorderStatsLine`/`_JaminanDropdown
    // Chip`. Sebelum dipenuhi: total penuh (1+1+5=7 produk, jaminan sama).
    final produkAwal =
        find.textContaining('Produk: 7', findRichText: true).evaluate().length;
    final chipJaminanAwal =
        find.textContaining('Lpg: 7', findRichText: true).evaluate().length;
    final totalJaminanAwal =
        find.textContaining('7 jaminan').evaluate().length;

    await db.fulfillPreorderQty('ghani', 4,
        locallyModified: false, deviceCode: null);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final sisaBaris = find.textContaining('1 Lpg - 1 jaminan').evaluate().length;
    // "5 Lpg" (angka awal) TIDAK boleh tampil lagi — harus sudah jadi sisa.
    final angkaAwalMasihAda = find.textContaining('5 Lpg').evaluate().length;
    final produkSetelah =
        find.textContaining('Produk: 3', findRichText: true).evaluate().length;
    final chipJaminanSetelah =
        find.textContaining('Lpg: 3', findRichText: true).evaluate().length;
    final totalJaminanSetelah =
        find.textContaining('3 jaminan').evaluate().length;
    final garisMasihAda = find.textContaining('Batas kiriman').evaluate().length;

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));

    expect(produkAwal, 1,
        reason: 'Total produk = 7 sebelum ada pemenuhan');
    expect(chipJaminanAwal, 1,
        reason: 'chip jaminan menampilkan Lpg: 7 sebelum ada pemenuhan');
    expect(totalJaminanAwal, greaterThanOrEqualTo(1),
        reason: 'total keseluruhan jaminan = 7 sbg teks polos');
    expect(angkaAwalMasihAda, 0,
        reason: 'kartu Abdul Ghani harus menampilkan SISA (1), bukan qty '
            'pesanan awal (5) yang sudah basi begitu dipenuhi sebagian');
    expect(sisaBaris, greaterThanOrEqualTo(1),
        reason: 'sisa Abdul Ghani (1 Lpg - 1 jaminan) harus tampil di kartu');
    expect(produkSetelah, 1,
        reason: 'Total produk turun jadi 1+1+1=3 (sinkron dgn sisa per '
            'kartu, bukan angka penuh 7 yang sudah tidak akurat)');
    expect(chipJaminanSetelah, 1,
        reason: 'chip jaminan ikut turun jadi Lpg: 3');
    expect(totalJaminanSetelah, greaterThanOrEqualTo(1),
        reason: 'total keseluruhan jaminan turun jadi 3 dgn alasan yang sama');
    expect(garisMasihAda, 0,
        reason: 'sisa kumulatif tinggal 3 (<=4) -> tidak ada lagi yang '
            'melewati kuota, garis pembatas hilang');
  });
}
