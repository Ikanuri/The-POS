import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Usulan user — produk bervarian di daftar kasir dibuka/ditutup dengan TAP
/// tombol chevron (dulu hanya tahan item). Tahan tetap jalan sbg jalan
/// pintas; produk tanpa varian tidak punya tombol.
void main() {
  // Layar Kasir default = landing; test ini menguji DAFTAR produk langsung.
  setUp(() => SharedPreferences.setMockInitialValues(
      {'kasir_landing_view': false}));

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const fakeDevice = DeviceIdentity(
    storeUuid: 's',
    storeKey: 'k',
    storeName: 'Toko',
    deviceName: 'Kasir',
    deviceCode: 'K1',
    deviceRole: 'owner',
  );

  Future<void> pumpKasirList(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider
            .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pumpAndSettle();
  }

  Future<void> seedParentWithVariant() async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v1', name: 'Coklat', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu1', productId: 'v1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt1', productUnitId: 'vu1', price: 5500));
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  const toggle = ValueKey('variant-toggle');

  testWidgets('tap chevron membuka lalu menutup daftar varian',
      (tester) async {
    await seedParentWithVariant();
    await pumpKasirList(tester);

    expect(find.byKey(toggle), findsOneWidget);
    expect(find.text('Coklat'), findsNothing);

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(find.text('Coklat'), findsOneWidget,
        reason: 'tanpa tombol: varian hanya bisa dibuka dgn tahan item');

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(find.text('Coklat'), findsNothing);
    await drain(tester);
  });

  testWidgets('area sentuh chevron >= 40dp', (tester) async {
    await seedParentWithVariant();
    await pumpKasirList(tester);
    final size = tester.getSize(find.byKey(toggle));
    expect(size.width, greaterThanOrEqualTo(40));
    expect(size.height, greaterThanOrEqualTo(40));
    await drain(tester);
  });

  testWidgets('tahan item tetap membuka varian (jalan pintas)',
      (tester) async {
    await seedParentWithVariant();
    await pumpKasirList(tester);
    await tester.longPress(find.text('Pop Ice'));
    await tester.pumpAndSettle();
    expect(find.text('Coklat'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('produk TANPA varian tidak punya tombol chevron',
      (tester) async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p9', name: 'Minyak Goreng'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u9', productId: 'p9', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't9', productUnitId: 'u9', price: 25000));
    await pumpKasirList(tester);
    expect(find.byKey(toggle), findsNothing);
    await drain(tester);
  });

  testWidgets('membuka/menutup varian dianimasikan (tinggi + fade), chevron '
      'berputar, varian tetap terpasang selama animasi tutup', (tester) async {
    await seedParentWithVariant();
    await pumpKasirList(tester);

    SizeTransition sizeT() => tester.widget<SizeTransition>(find
        .ancestor(
            of: find.text('Coklat', skipOffstage: false),
            matching: find.byType(SizeTransition))
        .first);
    double turns() => tester
        .widget<AnimatedRotation>(find.descendant(
            of: find.byKey(toggle), matching: find.byType(AnimatedRotation)))
        .turns;

    expect(turns(), 0);
    await tester.tap(find.byKey(toggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(sizeT().sizeFactor.value, inExclusiveRange(0, 1));
    expect(turns(), 0.5);
    await tester.pumpAndSettle();
    expect(sizeT().sizeFactor.value, 1);

    await tester.tap(find.byKey(toggle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Coklat'), findsOneWidget); // masih terlihat saat menutup
    expect(sizeT().sizeFactor.value, inExclusiveRange(0, 1));
    expect(turns(), 0);
    await tester.pumpAndSettle();
    expect(find.text('Coklat'), findsNothing);
    await drain(tester);
  });
}
