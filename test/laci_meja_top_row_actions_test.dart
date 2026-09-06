import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';

/// Revisi lanjutan (permintaan user):
/// - 1b: field cari jadi SATU ikon 36×36 (persis `_CategoryIconBtn`), bukan
///   lagi kotak lebar `Expanded`.
/// - 1c: tombol Kuota & Salin Laporan PINDAH ke baris atas (satu baris dgn
///   3 ikon kategori + search), CUMA tampil di tab Pre-order, dan
///   "ketimpa" begitu field cari melebar.
/// - 2: SEMUA kotak ikon 36×36 di baris ini (kategori, search, Kuota,
///   Salin) WAJIB ikonnya TERPUSAT, bukan nempel pojok.
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

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
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

  Future<void> seedOnePreorder(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seedTransaction('tx1');
    await db.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        customerName: 'Cust1',
        qtyOrdered: 2,
        transactionId: 'tx1');
  }

  testWidgets('ikon cari collapsed berukuran PERSIS 36x36', (tester) async {
    await seedOnePreorder(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    final searchBtn = find.ancestor(
        of: find.byIcon(Icons.search), matching: find.byType(IconButton));
    expect(searchBtn, findsOneWidget);
    expect(tester.getSize(searchBtn), const Size(36, 36));

    await drain(tester);
  });

  testWidgets(
      'tombol Kuota & Salin Laporan HANYA tampil di tab Pre-order, tidak '
      'di Titip/Ketinggalan maupun Pinjaman', (tester) async {
    await seedOnePreorder(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Default kategori aktif: Titip/Ketinggalan.
    expect(find.byTooltip('Kuota'), findsNothing);
    expect(find.byTooltip('Salin Laporan'), findsNothing);

    await tester.tap(find.text('Pinjaman'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kuota'), findsNothing);
    expect(find.byTooltip('Salin Laporan'), findsNothing);

    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Kuota'), findsOneWidget);
    expect(find.byTooltip('Salin Laporan'), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'begitu field cari di tab Pre-order di-expand, tombol Kuota & Salin '
      'jadi non-tappable & pudar (IgnorePointer+AnimatedOpacity, pola '
      '_KasirTopbar) — ketimpa field cari yang melebar', (tester) async {
    await seedOnePreorder(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cari'));
    await tester.pumpAndSettle();

    final ignorePointer = tester.widgetList<IgnorePointer>(find.descendant(
        of: find.byWidgetPredicate((w) => w is Row),
        matching: find.byWidgetPredicate((w) =>
            w is IgnorePointer &&
            find
                .descendant(
                    of: find.byWidget(w), matching: find.byTooltip('Kuota'))
                .evaluate()
                .isNotEmpty)));
    expect(ignorePointer, isNotEmpty,
        reason: 'tombol Kuota/Salin dibungkus IgnorePointer begitu field '
            'cari expanded');
    expect(ignorePointer.first.ignoring, isTrue,
        reason: 'ignoring=true begitu search expanded -> tombol tidak bisa '
            'ditap walau ketutup');

    final opacityAncestor = tester
        .widget<AnimatedOpacity>(find.ancestor(
            of: find.byTooltip('Kuota'), matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(opacityAncestor, 0,
        reason: 'tombol Kuota/Salin pudar total (opacity 0) begitu ketutup '
            'field cari');

    await drain(tester);
  });

  group('Revisi 2: ikon 36x36 di baris atas WAJIB terpusat', () {
    /// Bandingkan titik tengah kotak 36x36 [boxFinder] dgn titik tengah
    /// ikon di dalamnya [iconFinder] — harus (nyaris) sama persis kalau
    /// `alignment: Alignment.center` terpasang; bug lama (tanpa alignment)
    /// membuat ikon nempel ke pojok kiri-atas, jadi titik tengahnya BEDA
    /// jauh dari titik tengah kotak.
    void expectCentered(WidgetTester tester, Finder boxFinder, Finder iconFinder) {
      final boxCenter = tester.getCenter(boxFinder);
      final iconCenter = tester.getCenter(iconFinder);
      expect((boxCenter - iconCenter).distance, lessThan(1.0),
          reason: 'ikon harus TERPUSAT di kotaknya (bug lama: nempel pojok '
              'kiri-atas krn Container tanpa `alignment`)');
    }

    testWidgets('ikon kategori (_CategoryIconBtn) TERPUSAT di kotak 36x36',
        (tester) async {
      await seedOnePreorder(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final box = find.ancestor(
          of: find.byIcon(Icons.hourglass_empty),
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(10)));
      expectCentered(tester, box.first, find.byIcon(Icons.hourglass_empty));

      await drain(tester);
    });

    testWidgets('ikon search collapsed TERPUSAT di kotak 36x36',
        (tester) async {
      await seedOnePreorder(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final searchBox = find.ancestor(
          of: find.byIcon(Icons.search), matching: find.byType(IconButton));
      expectCentered(tester, searchBox, find.byIcon(Icons.search));

      await drain(tester);
    });

    testWidgets('ikon Kuota & Salin Laporan TERPUSAT di kotak 36x36',
        (tester) async {
      await seedOnePreorder(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();

      final kuotaBox = find.ancestor(
          of: find.byIcon(Icons.rule), matching: find.byType(IconButton));
      final salinBox = find.ancestor(
          of: find.byIcon(Icons.content_copy),
          matching: find.byType(IconButton));
      expectCentered(tester, kuotaBox, find.byIcon(Icons.rule));
      expectCentered(tester, salinBox, find.byIcon(Icons.content_copy));

      await drain(tester);
    });

    testWidgets(
        'badge notif jumlah TIDAK menutupi ikon — digeser ke pojok kotak, '
        'bukan numpuk di tengah ikon yang sekarang sudah terpusat',
        (tester) async {
      await seedOnePreorder(tester);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final badge = tester.widget<Badge>(find.ancestor(
          of: find.byIcon(Icons.hourglass_empty), matching: find.byType(Badge)));
      expect(badge.offset, const Offset(10, -10),
          reason: 'tanpa offset, Badge default numpuk di glyph ikon yang '
              'sekarang sudah di-tengah kotak (bug baru ditemukan user) — '
              'harus digeser keluar ke arah pojok kotak 36x36');

      await drain(tester);
    });
  });
}
