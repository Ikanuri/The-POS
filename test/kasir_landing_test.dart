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

/// Landing layar Kasir: query "terakhir dijual" (DB nyata) + perilaku layar
/// (landing saat kosong, daftar saat mengetik/kategori/"Semua produk",
/// kembali lewat chip Beranda, pengaturan Daftar-langsung).
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
    Size size = const Size(430, 2400)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(
      {'kasir_swipe_hint_count': 3, ...prefs});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = const DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            deviceName: 'Kasir Uji',
            deviceCode: 'K1',
            deviceRole: 'owner',
          )),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const KasirScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  group('getRecentlySoldParentProductIds', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('terbaru dulu, tanpa duplikat, varian digabung ke induk', () async {
      final now = DateTime(2026, 10, 8, 12);
      final a = await _addProduct(db, 'A');
      final b = await _addProduct(db, 'B');
      final parent = await _addProduct(db, 'Induk');
      final v = await _addProduct(db, 'Varian', parentProductId: parent);
      await _sale(db, now.subtract(const Duration(days: 5)), [(a, 1)]);
      await _sale(db, now.subtract(const Duration(days: 4)), [(b, 1)]);
      await _sale(db, now.subtract(const Duration(days: 3)), [(v, 1)]);
      await _sale(db, now.subtract(const Duration(days: 1)), [(a, 1)]);
      final r = await db.getRecentlySoldParentProductIds();
      expect(r, [a, parent, b]);
      expect(r.contains(v), isFalse);
    });

    test('void, retur, nonaktif & habis-manual dikecualikan; batas N',
        () async {
      final now = DateTime(2026, 10, 8, 12);
      final ok = await _addProduct(db, 'OK');
      final off = await _addProduct(db, 'Off', isActive: false);
      final oos = await _addProduct(db, 'Habis', markedOutOfStock: true);
      final voided = await _addProduct(db, 'Void');
      final ret = await _addProduct(db, 'Retur');
      await _sale(db, now, [(ok, 1), (off, 1), (oos, 1), (ret, -1)]);
      await _sale(db, now, [(voided, 1)], status: 'void');
      expect(await db.getRecentlySoldParentProductIds(), [ok]);
      final many = <String>[];
      for (var i = 0; i < 5; i++) {
        many.add(await _addProduct(db, 'M$i'));
        await _sale(db, now.add(Duration(minutes: i + 1)), [(many.last, 1)]);
      }
      expect((await db.getRecentlySoldParentProductIds(limit: 3)).length, 3);
    });
  });

  group('layar Kasir', () {
    testWidgets(
        'kolom cari kosong -> landing (Terlaris + Terakhir dijual); '
        'ketik -> daftar; hapus -> landing lagi', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final a = await _addProduct(db, 'Gula Pasir');
      final b = await _addProduct(db, 'Beras Rojolele');
      final now = DateTime.now();
      await _sale(db, now.subtract(const Duration(days: 2)), [(a, 1)]);
      await _sale(db, now.subtract(const Duration(days: 1)), [(a, 1)]);
      await _sale(db, now.subtract(const Duration(hours: 1)), [(b, 1)]);
      await _pumpKasir(tester, db);

      expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
      expect(find.text('Mau jual apa hari ini?'), findsOneWidget);
      expect(find.byKey(const Key('landing-top')), findsOneWidget);
      expect(find.text('Terlaris'), findsOneWidget);
      // B hanya ada di "Terakhir dijual" bila tidak ikut Terlaris — di sini
      // keduanya terlaris, jadi bagian recent disembunyikan (tanpa duplikat).
      expect(find.text('Gula Pasir'), findsOneWidget);
      expect(find.text('Beras Rojolele'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'gula');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kasir-landing')), findsNothing);
      expect(find.text('Gula Pasir'), findsOneWidget);
      expect(find.text('Beras Rojolele'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kasir-landing')), findsOneWidget);

      await _drain(tester);
      await db.close();
    });

    testWidgets(
        '"Semua produk" membuka daftar penuh; chip Beranda kembali '
        'ke landing', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _addProduct(db, 'Sabun Mandi');
      await _pumpKasir(tester, db);

      // Belum ada penjualan: tidak ada Terlaris/Terakhir, produk tak tampil.
      expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
      expect(find.text('Sabun Mandi'), findsNothing);

      await tester.tap(find.byKey(const Key('landing-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kasir-landing')), findsNothing);
      expect(find.text('Gula Pasir'), findsOneWidget);
      expect(find.text('Sabun Mandi'), findsOneWidget);

      await tester.tap(find.byKey(const Key('kasir-home-chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kasir-landing')), findsOneWidget);

      await _drain(tester);
      await db.close();
    });

    testWidgets('stepper "+" di landing (Terlaris) menambah ke keranjang',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final a = await _addProduct(db, 'Gula Pasir');
      await _sale(db, DateTime.now(), [(a, 1)]);
      await _pumpKasir(tester, db);

      final g = await tester
          .startGesture(tester.getCenter(find.byIcon(Icons.add_rounded).first));
      await tester.pump(const Duration(milliseconds: 60));
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('1'), findsWidgets);

      await _drain(tester);
      await db.close();
    });

    testWidgets('pengaturan "Langsung daftar": tanpa landing', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db,
          prefs: {'kasir_landing_view': false, 'kasir_swipe_hint_count': 3});

      expect(find.byKey(const Key('kasir-landing')), findsNothing);
      expect(find.text('Gula Pasir'), findsOneWidget);

      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'lebar HP sempit (360x800): landing tanpa overflow, banyak '
        'kategori membungkus', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final a = await _addProduct(db, 'Gula Pasir');
      await _sale(db, DateTime.now(), [(a, 1)]);
      for (var i = 0; i < 8; i++) {
        await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
              id: Value(100 + i),
              name: Value('Kategori Panjang Nomor $i'),
            ));
      }
      await _pumpKasir(tester, db, size: const Size(360, 800));
      expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _drain(tester);
      await db.close();
    });
  });
}
