import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:the_pos/core/diagnostics/perf_diag.dart';
import 'package:the_pos/core/widgets/press_scale.dart';
import 'package:the_pos/features/pengaturan/perf_diag_screen.dart';
import 'package:the_pos/features/shell/main_shell.dart'
    show shellResizesForKeyboard;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Diagnostik performa: saklar per fitur + efeknya pada layar Kasir gaya Baru.
/// (turunan kerangka kasir_modern_test.dart)
/// Kasir gaya BARU (kasir_modern.dart): landing, kolom cari yang naik saat
/// mengetik, tanpa Terlaris, logika kasir tetap (stepper, select-all, dst.).
int _seq = 0;

Future<String> _addProduct(AppDatabase db, String name,
    {String? parentProductId,
    bool isActive = true,
    int price = 10000,
    bool markedOutOfStock = false}) async {
  final id = 'p${_seq++}';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: id,
        name: name,
        isActive: Value(isActive),
        parentProductId: Value(parentProductId),
        markedOutOfStock: Value(markedOutOfStock),
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: '$id-u',
        productId: id,
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: '$id-u-t1',
        productUnitId: '$id-u',
        price: price,
      ));
  return id;
}

Future<void> _sale(AppDatabase db, DateTime at, List<(String, double)> lines,
    {String status = 'lunas'}) async {
  final txId = 't${_seq++}';
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: txId,
        localId: 'K-$txId',
        status: status,
        total: 1000,
        paid: 1000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(at),
      ));
  var n = 0;
  for (final l in lines) {
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: '$txId-${n++}',
          transactionId: txId,
          productId: l.$1,
          productUnitId: '${l.$1}-u',
          qty: l.$2,
          priceAtSale: 1000,
          originalPrice: 1000,
          subtotal: 1000,
        ));
  }
}

Future<void> _pumpKasir(WidgetTester tester, AppDatabase db,
    {Map<String, Object> prefs = const {},
    Size size = const Size(430, 2400),
    bool stickers = false,
    bool reduced = false,
    double textScale = 1.0,
    String deviceRole = 'owner'}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(
      {'kasir_swipe_hint_count': 3, ...prefs});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Stiker berulang selamanya -> pumpAndSettle tak pernah selesai.
        // Test umum mematikannya; test stiker khusus menyalakannya.
        if (!stickers)
          kasirStickerProvider.overrideWith((ref, slot) async => null),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            deviceName: 'Kasir Uji',
            deviceCode: 'K1',
            deviceRole: deviceRole,
          )),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
                disableAnimations: reduced,
                textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: const KasirScreen(),
      ),
    ),
  );
  if (stickers) {
    // Stiker berulang: jangan pumpAndSettle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  const modern = {'kasir_style': 'modern'};

  tearDown(() => PerfDiag.notifier.value = PerfDiagState.normal);

  test('PerfDiag: simpan/baca prefs, ringkasan, kembali normal', () async {
    SharedPreferences.setMockInitialValues({});
    await PerfDiag.set(const PerfDiagState(shadows: false, meter: true));
    expect(PerfDiag.s.shadows, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PerfDiag.prefKey), isNotNull);

    PerfDiag.notifier.value = PerfDiagState.normal;
    await PerfDiag.load();
    expect(PerfDiag.s.shadows, isFalse);
    expect(PerfDiag.s.meter, isTrue);
    expect(PerfDiag.s.summary(), 'shadows=OFF, meter=ON');

    await PerfDiag.set(PerfDiagState.normal);
    expect(prefs.getString(PerfDiag.prefKey), isNull,
        reason: 'normal = tidak menyimpan apa-apa');
    expect(PerfDiag.s.summary(), isEmpty);
  });

  testWidgets('layar Diagnostik: saklar mengubah PerfDiag; reset normal',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: const PerfDiagScreen()));
    await tester.pumpAndSettle();

    for (final k in [
      'stickers',
      'shadows',
      'blobs',
      'pressScale',
      'pageFade',
      'heroAnim',
      'hintRotate',
      'tileDecor',
      'recentQuery',
      'keyboardResize',
      'hideCart',
      'meter',
      'overlay',
    ]) {
      expect(find.byKey(Key('diag-$k')), findsOneWidget, reason: k);
    }
    await tester.tap(find.byKey(const Key('diag-stickers')));
    await tester.pumpAndSettle();
    expect(PerfDiag.s.stickers, isFalse);
    await tester.tap(find.byKey(const Key('diag-hideCart')));
    await tester.pumpAndSettle();
    expect(PerfDiag.s.hideCartWhileTyping, isTrue);

    await tester.tap(find.byKey(const Key('diag-reset')));
    await tester.pumpAndSettle();
    expect(PerfDiag.s, isA<PerfDiagState>());
    expect(PerfDiag.s.summary(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  test('summaryAll: SEMUA saklar tampil, yang beda dari normal bertanda *', () {
    final all =
        const PerfDiagState(keyboardResize: false, meter: true).summaryAll();
    expect(all, contains('stickers=ON,'));
    expect(all, contains('keyboardResize=OFF*'));
    expect(all, contains('meter=ON*'));
    expect(all, contains('perfOverlay=OFF,'),
        reason: 'saklar uji yang normalnya OFF tetap tercantum');
    expect(all.split(',').length, 13);
    expect(PerfDiagState.normal.summaryAll().contains('*'), isFalse);
  });

  test(
      'Scaffold shell: hanya TIDAK mengecil bila Kasir gaya Baru + saklar '
      'keyboardResize dimatikan', () {
    const off = PerfDiagState(keyboardResize: false);
    bool f(bool kasir, bool modern, PerfDiagState d) => shellResizesForKeyboard(
        onKasirTab: kasir, modernStyle: modern, diag: d);
    expect(f(true, true, PerfDiagState.normal), isTrue);
    expect(f(true, true, off), isFalse);
    expect(f(true, false, off), isTrue, reason: 'Klasik tidak terpengaruh');
    expect(f(false, true, off), isTrue, reason: 'tab lain tidak terpengaruh');
  });

  group('efek saklar pada layar Kasir gaya Baru', () {
    testWidgets(
        'stiker & PressScale sudah mati SEJAK AWAL: dispose aman '
        '(tanpa galat ticker)', (tester) async {
      PerfDiag.notifier.value =
          const PerfDiagState(stickers: false, pressScale: false);
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern, stickers: true);
      expect(find.byType(Lottie), findsNothing);
      await _drain(tester); // unmount -> dispose
      expect(tester.takeException(), isNull);
      await db.close();
    });

    testWidgets('blob & stiker & bayangan: mati lewat saklar', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern, stickers: true);
      expect(find.byType(Lottie), findsOneWidget);
      final shadowedBefore = _countShadowed(tester);
      expect(shadowedBefore, greaterThan(0));

      PerfDiag.notifier.value =
          const PerfDiagState(stickers: false, shadows: false, blobs: false);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(Lottie), findsNothing);
      expect(_countShadowed(tester), 0,
          reason: 'semua BoxShadow modern dimatikan');
      await _drain(tester);
      await db.close();
    });

    testWidgets('keyboardResize=false: Scaffold tidak mengecil oleh keyboard',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      bool resize() => tester
          .widget<Scaffold>(find.descendant(
              of: find.byType(KasirScreen), matching: find.byType(Scaffold)))
          .resizeToAvoidBottomInset!;
      expect(resize(), isTrue);
      PerfDiag.notifier.value = const PerfDiagState(keyboardResize: false);
      await tester.pump();
      expect(resize(), isFalse);
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'hideCartWhileTyping: cart bar hilang selagi keyboard '
        'terbuka', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modern-cart-bar')), findsOneWidget);

      PerfDiag.notifier.value = const PerfDiagState(hideCartWhileTyping: true);
      tester.view.viewInsets = const FakeViewPadding(bottom: 600);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modern-cart-bar')), findsNothing);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modern-cart-bar')), findsOneWidget);
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'pressScale=false: tanpa Transform pembungkus; hint & '
        'tileDecor & hero mengikuti saklar', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final a = await _addProduct(db, 'Gula Pasir');
      await _sale(db, DateTime.now(), [(a, 1)]);
      await _pumpKasir(tester, db,
          prefs: {...modern, 'kasir_grid_view': false});
      expect(find.byType(PressScale), findsWidgets);
      // Anak langsung PressScale: Listener (aktif) atau langsung isi (mati).
      Iterable<Type> childTypes() =>
          find.byType(PressScale).evaluate().map((e) {
            late Type t;
            e.visitChildren((c) => t = c.widget.runtimeType);
            return t;
          });
      expect(childTypes().every((t) => t == Listener), isTrue);

      PerfDiag.notifier.value = const PerfDiagState(
          pressScale: false, tileDecor: false, heroAnim: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(childTypes().any((t) => t == Listener), isFalse,
          reason: 'PressScale mati = tanpa Listener/Transform pembungkus');
      // Kartu produk polos: tidak ada ClipRRect pembungkus tile.
      final tileClip = find.descendant(
          of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_ModernTileCard'),
          matching: find.byType(ClipRRect));
      expect(tileClip, findsNothing);
      await _drain(tester);
      await db.close();
    });
  });
}

/// Jumlah Container/DecoratedBox bergaya `boxShadow` tak kosong di pohon.
int _countShadowed(WidgetTester tester) {
  var n = 0;
  for (final w in tester.allWidgets) {
    BoxDecoration? d;
    if (w is Container && w.decoration is BoxDecoration) {
      d = w.decoration as BoxDecoration;
    } else if (w is AnimatedContainer && w.decoration is BoxDecoration) {
      d = w.decoration as BoxDecoration;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      d = w.decoration as BoxDecoration;
    }
    if (d?.boxShadow != null && d!.boxShadow!.isNotEmpty) n++;
  }
  return n;
}
