import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Kasir gaya BARU (kasir_modern.dart): landing, kolom cari yang naik saat
/// mengetik, tanpa Terlaris, logika kasir tetap (stepper, select-all, dst.).
int _seq = 0;

Future<String> _addProduct(AppDatabase db, String name,
    {String? parentProductId,
    bool isActive = true,
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
        price: 10000,
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
    bool reduced = false}) async {
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
          ..state = const DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            deviceName: 'Kasir Uji',
            deviceCode: 'K1',
            deviceRole: 'owner',
          )),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
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

  testWidgets('default = Klasik (tanpa kolom cari gaya Baru)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, 'Gula Pasir');
    await _pumpKasir(tester, db);
    expect(find.byKey(const Key('modern-search')), findsNothing);
    await _drain(tester);
    await db.close();
  });

  testWidgets(
      'gaya Baru: landing + kolom cari; kolom cari NAIK saat '
      'mengetik, teks & fokus tetap', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final a = await _addProduct(db, 'Gula Pasir');
    await _addProduct(db, 'Beras Rojolele');
    await _sale(db, DateTime.now(), [(a, 1)]);
    await _pumpKasir(tester, db, prefs: modern);

    expect(find.byKey(const Key('modern-search')), findsOneWidget);
    expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
    expect(find.text('Mau jual apa hari ini?'), findsOneWidget);
    expect(find.text('Terlaris'), findsNothing,
        reason: 'Terlaris dihapus di gaya Baru');
    expect(find.text('Terakhir dijual'), findsOneWidget);
    final yLanding =
        tester.getTopLeft(find.byKey(const Key('modern-search'))).dy;

    await tester.tap(find.byKey(const Key('modern-search')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
    await tester.pumpAndSettle();

    expect(find.text('Mau jual apa hari ini?'), findsNothing);
    expect(find.byKey(const Key('kasir-landing')), findsNothing);
    final yTop = tester.getTopLeft(find.byKey(const Key('modern-search'))).dy;
    expect(yTop, lessThan(yLanding - 20),
        reason: 'kolom cari harus pindah ke atas setelah mengetik');
    expect(find.text('Gula Pasir'), findsOneWidget);
    expect(find.text('Beras Rojolele'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('modern-search')))
            .controller!
            .text,
        'gula');

    // Hapus -> kembali ke landing, kolom cari turun lagi.
    await tester.tap(find.byKey(const Key('modern-search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('modern-search'))).dy,
        closeTo(yLanding, 2));

    await _drain(tester);
    await db.close();
  });

  testWidgets('"Semua produk" -> daftar penuh; Beranda kembali ke landing',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, 'Gula Pasir');
    await _addProduct(db, 'Sabun Mandi');
    await _pumpKasir(tester, db, prefs: modern);
    await tester.tap(find.byKey(const Key('landing-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kasir-landing')), findsNothing);
    expect(find.text('Sabun Mandi'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kasir-home-chip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
    await _drain(tester);
    await db.close();
  });

  testWidgets(
      'stepper "+" di daftar gaya Baru menambah ke keranjang '
      '(jari menempel beberapa frame) dan select-all pencarian tetap '
      'berjalan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, 'Gula Pasir');
    await _pumpKasir(tester, db, prefs: modern);
    await tester.tap(find.byKey(const Key('modern-search')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
    await tester.pumpAndSettle();

    final g = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.add_rounded).first));
    await tester.pump(const Duration(milliseconds: 60));
    await g.up();
    await tester.pumpAndSettle();

    expect(find.text('1'), findsWidgets);
    final ctrl = tester
        .widget<TextField>(find.byKey(const Key('modern-search')))
        .controller!;
    expect(ctrl.text, 'gula', reason: 'teks cari tidak boleh terhapus');
    expect(ctrl.selection.start, 0);
    expect(ctrl.selection.end, 4,
        reason: 'select-all setelah tap + supaya ketik berikutnya menimpa');
    await _drain(tester);
    await db.close();
  });
}
