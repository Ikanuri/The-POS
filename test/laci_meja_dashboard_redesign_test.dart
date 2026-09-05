import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';

/// Redesain dashboard Laci Meja (permintaan user, mockup disetujui):
/// - 3 kartu ringkasan besar -> 3 ikon kotak kecil (gaya `_TbBtn` kasir)
///   dgn Badge count, tap = pindah kategori aktif.
/// - Warna aksen beda per kategori (Titip/Ketinggalan = laciFg/laciBg lama,
///   Pinjaman = pinjamanFg/pinjamanBg baru, Pre-order = preorderFg/
///   preorderBg baru).
/// - SATU field cari dipakai bersama ketiga kategori, tidak reset saat
///   pindah kategori — Titip/Ketinggalan & Pinjaman SEKARANG ikut punya
///   filter pencarian (sebelumnya cuma Pre-order).
/// - Container besar pembungkus baris statistik pre-order dihapus.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/laci-meja',
      routes: [
        GoRoute(
          path: '/laci-meja',
          builder: (_, __) => const LaciMejaDashboardScreen(),
        ),
        GoRoute(
          path: '/kasir/struk/:txId',
          builder: (_, state) => Scaffold(
              body: Text('Layar Struk ${state.pathParameters['txId']}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> seedTransaction(String id) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
  }

  /// Tombol kategori _CategoryIconBtn yang labelnya persis [label].
  Finder categoryBtn(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_CategoryIconBtn'));

  /// Kotak 36x36 (border radius 10) di dalam tombol kategori [label] —
  /// dipakai utk membaca warna/lebar border aktif vs tidak aktif.
  BoxDecoration boxDecorationFor(WidgetTester tester, String label) {
    final boxFinder = find.descendant(
        of: categoryBtn(label),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(10)));
    return tester.widget<Container>(boxFinder).decoration as BoxDecoration;
  }

  /// Angka di `Badge` tombol kategori [label], null kalau tidak ada Badge
  /// (count 0, badge disembunyikan — pola sama `_TbBtn`).
  String? badgeTextFor(WidgetTester tester, String label) {
    final badgeFinder =
        find.descendant(of: categoryBtn(label), matching: find.byType(Badge));
    if (badgeFinder.evaluate().isEmpty) return null;
    final badge = tester.widget<Badge>(badgeFinder);
    return (badge.label as Text).data;
  }

  Future<void> expandSearch(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cari'));
    await tester.pumpAndSettle();
  }

  group('Ikon kategori (redesain, gaya _TbBtn)', () {
    testWidgets(
        'tap ikon kategori memindahkan kategori aktif (daftar yg tampil '
        'berubah) + visual aktif ikut berubah (bingkai lebih tebal & '
        'berwarna)', (tester) async {
      await seedTransaction('tx1');
      await seedTransaction('tx2');
      await seedTransaction('tx3');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Barang Titip Unik',
          jenis: 'titip');
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: 'tx2',
          itemName: 'Barang Pinjam Unik',
          qty: 1);
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Pemesan Unik',
          qtyOrdered: 1,
          transactionId: 'tx3');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Default: Titip/Ketinggalan aktif.
      expect(find.text('Barang Titip Unik'), findsOneWidget);
      expect(find.textContaining('Barang Pinjam Unik'), findsNothing);
      expect(find.text('Pemesan Unik'), findsNothing);

      final titipActive = boxDecorationFor(tester, 'Titip/Ketinggalan');
      final pinjamanInactive = boxDecorationFor(tester, 'Pinjaman');
      expect(titipActive.border!.top.width, greaterThan(1),
          reason: 'kategori aktif harus punya bingkai lebih tebal');
      expect(pinjamanInactive.border!.top.width, lessThan(1),
          reason: 'kategori tidak aktif bingkainya tipis (0.75)');
      expect(titipActive.color, isNot(equals(Colors.transparent)),
          reason: 'kategori aktif diberi latar warna aksennya (bg)');
      expect(pinjamanInactive.color, equals(Colors.transparent),
          reason: 'kategori tidak aktif latar transparan');

      await tester.tap(find.text('Pinjaman'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Barang Pinjam Unik'), findsOneWidget);
      expect(find.text('Barang Titip Unik'), findsNothing);

      final pinjamanNowActive = boxDecorationFor(tester, 'Pinjaman');
      final titipNowInactive = boxDecorationFor(tester, 'Titip/Ketinggalan');
      expect(pinjamanNowActive.border!.top.width, greaterThan(1));
      expect(titipNowInactive.border!.top.width, lessThan(1));

      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();
      expect(find.text('Pemesan Unik'), findsOneWidget);
      expect(find.textContaining('Barang Pinjam Unik'), findsNothing);

      await drain(tester);
    });

    testWidgets(
        'badge di tiap ikon menampilkan count kategori masing2 sesuai data '
        'seed (2 titip, 1 pinjaman, 3 pre-order)', (tester) async {
      await seedTransaction('tx1');
      await db.addLeftBehindItem(
          id: 'l1', transactionId: 'tx1', itemName: 'A', jenis: 'titip');
      await db.addLeftBehindItem(
          id: 'l2', transactionId: 'tx1', itemName: 'B', jenis: 'titip');
      await db.addBorrowedItem(
          id: 'b1', transactionId: 'tx1', itemName: 'C', qty: 1);
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Cust1',
          qtyOrdered: 1,
          transactionId: 'tx1');
      await db.addPreorderEntry(
          id: 'p2',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Cust2',
          qtyOrdered: 1,
          transactionId: 'tx1');
      await db.addPreorderEntry(
          id: 'p3',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Cust3',
          qtyOrdered: 1,
          transactionId: 'tx1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(badgeTextFor(tester, 'Titip/Ketinggalan'), '2');
      expect(badgeTextFor(tester, 'Pinjaman'), '1');
      expect(badgeTextFor(tester, 'Pre-order'), '3');

      await drain(tester);
    });

    testWidgets(
        'kategori dgn count 0 TIDAK menampilkan Badge sama sekali (pola '
        'sama _TbBtn)', (tester) async {
      await seedTransaction('tx1');
      await db.addLeftBehindItem(
          id: 'l1', transactionId: 'tx1', itemName: 'A', jenis: 'titip');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(badgeTextFor(tester, 'Titip/Ketinggalan'), '1');
      expect(badgeTextFor(tester, 'Pinjaman'), isNull);
      expect(badgeTextFor(tester, 'Pre-order'), isNull);

      await drain(tester);
    });
  });

  group('Field cari BERSAMA ketiga kategori (redesain)', () {
    Future<void> seedAllThree() async {
      await seedTransaction('tx1');
      await seedTransaction('tx2');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Galon Aqua',
          jenis: 'titip',
          customerNameText: 'Budi');
      await db.addLeftBehindItem(
          id: 'l2',
          transactionId: 'tx2',
          itemName: 'Payung',
          jenis: 'titip',
          customerNameText: 'Sari');
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: 'tx1',
          itemName: 'Tabung Gas',
          qty: 1,
          customerNameText: 'Budi');
      await db.addBorrowedItem(
          id: 'b2',
          transactionId: 'tx2',
          itemName: 'Ember',
          qty: 1,
          customerNameText: 'Sari');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Budi',
          qtyOrdered: 1,
          transactionId: 'tx1');
      await db.addPreorderEntry(
          id: 'p2',
          productId: 'prod1',
          productUnitId: 'unit1',
          customerName: 'Sari',
          qtyOrdered: 1,
          transactionId: 'tx2');
    }

    testWidgets(
        'cari "Budi" menyaring daftar Titip/Ketinggalan (kategori yg '
        'SEBELUMNYA sama sekali tidak punya filter pencarian)',
        (tester) async {
      await seedAllThree();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await expandSearch(tester);
      await tester.enterText(find.byType(TextField), 'Budi');
      await tester.pumpAndSettle();

      expect(find.textContaining('Galon Aqua'), findsOneWidget);
      expect(find.textContaining('Payung'), findsNothing);

      await drain(tester);
    });

    testWidgets(
        'cari "Budi" menyaring daftar Pinjaman (kategori yg SEBELUMNYA '
        'sama sekali tidak punya filter pencarian)', (tester) async {
      await seedAllThree();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pinjaman'));
      await tester.pumpAndSettle();
      await expandSearch(tester);
      await tester.enterText(find.byType(TextField), 'Budi');
      await tester.pumpAndSettle();

      expect(find.textContaining('Tabung Gas'), findsOneWidget);
      expect(find.textContaining('Ember'), findsNothing);

      await drain(tester);
    });

    testWidgets('cari "Budi" tetap menyaring daftar Pre-order seperti dulu',
        (tester) async {
      await seedAllThree();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();
      await expandSearch(tester);
      await tester.enterText(find.byType(TextField), 'Budi');
      await tester.pumpAndSettle();
      // Unfocus (spt test pre-order lama) supaya field cari mengecil balik
      // -> hanya SATU widget teks "Budi" tersisa (header kartu), tidak
      // ambigu dgn `EditableText` internal field cari yg sedang expanded.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(find.text('Budi'), findsOneWidget);
      expect(find.text('Sari'), findsNothing);

      await drain(tester);
    });

    testWidgets(
        'pindah kategori TIDAK me-reset teks field cari — filter tetap '
        '"Budi" walau berpindah dari Titip/Ketinggalan ke Pinjaman ke '
        'Pre-order TANPA perlu ketik ulang; teks juga tetap tersimpan kalau '
        'field cari dibuka lagi', (tester) async {
      await seedAllThree();
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await expandSearch(tester);
      await tester.enterText(find.byType(TextField), 'Budi');
      await tester.pumpAndSettle();
      expect(find.textContaining('Galon Aqua'), findsOneWidget);

      // Tap ikon kategori lain = tap DI LUAR field cari -> field cari boleh
      // mengecil balik (perilaku wajar expand/collapse, sama semangat dgn
      // toolbar kasir), TAPI teksnya sendiri (provider level-dashboard)
      // TIDAK BOLEH ikut hilang — filter harus tetap aktif TANPA mengetik
      // ulang.
      await tester.tap(find.text('Pinjaman'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tabung Gas'), findsOneWidget,
          reason: 'filter tetap aktif tanpa perlu ketik ulang');
      expect(find.textContaining('Ember'), findsNothing);
      await expandSearch(tester);
      expect(find.widgetWithText(TextField, 'Budi'), findsOneWidget,
          reason: 'teks "Budi" masih tersimpan begitu field dibuka lagi');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();
      expect(find.text('Budi'), findsOneWidget);
      expect(find.text('Sari'), findsNothing);
      await expandSearch(tester);
      expect(find.widgetWithText(TextField, 'Budi'), findsOneWidget,
          reason: 'teks "Budi" masih tersimpan begitu field dibuka lagi');

      await drain(tester);
    });
  });

  testWidgets(
      'tidak overflow di layar sempit 360dp (baris ikon+badge+cari padat)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedTransaction('tx1');
    await db.addLeftBehindItem(
        id: 'l1', transactionId: 'tx1', itemName: 'A', jenis: 'titip');
    await db.addBorrowedItem(id: 'b1', transactionId: 'tx1', itemName: 'B', qty: 1);
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        customerName: 'C',
        qtyOrdered: 1,
        transactionId: 'tx1');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Buka field cari (melebar penuh) — kondisi paling padat.
    await expandSearch(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await drain(tester);
  });

  testWidgets(
      'statistik pre-order (chip "N entri"/"Produk: N") TIDAK dibungkus '
      'Container besar berwarna (permintaan user: hapus bingkai pembungkus '
      '— berlanjut di redesain lanjutan: `_PreorderStatsLine` sendiri sudah '
      'dihapus total, isinya terpecah ke baris atas [Kuota/Salin] & baris '
      'dropdown filter produk [entri/Produk/Jaminan])', (tester) async {
    await seedTransaction('tx1');
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        customerName: 'Cust1',
        qtyOrdered: 2,
        transactionId: 'tx1');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();

    final entriChip = find.textContaining('entri');
    expect(entriChip, findsOneWidget);

    // Sebelumnya ada Container ancestor dgn `color` terisi (laciBg opacity
    // 0.5) yg membungkus SELURUH baris statistik — redesain menghapusnya,
    // tiap atribut di dalamnya (chip/tombol) py bingkai sendiri2, tapi
    // TIDAK ADA LAGI satu Container besar berwarna yg jadi ancestor-nya.
    final coloredAncestor = find.ancestor(
        of: entriChip,
        matching:
            find.byWidgetPredicate((w) => w is Container && w.color != null));
    expect(coloredAncestor, findsNothing,
        reason: 'container besar pembungkus (dgn warna latar) sudah harus '
            'dihapus, tiap atribut bingkai sendiri-sendiri');

    await drain(tester);
  });
}
