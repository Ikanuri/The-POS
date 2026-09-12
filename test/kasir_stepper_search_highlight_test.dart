import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Tap "+"/"-" (stepper) di kartu/tile/varian produk — kalau field cari
/// sedang expanded (fokus) & masih berisi teks sisa pencarian sebelumnya,
/// teksnya otomatis ter-select-all supaya kasir bisa langsung ketik ulang
/// produk berikutnya tanpa hapus manual. Kalau field cari collapsed/tidak
/// fokus, tap stepper TIDAK boleh menyentuhnya sama sekali.
///
/// Dites di 3 mode widget (kartu grid, tile daftar, baris varian dropdown)
/// supaya konsisten — itu inti dari laporan bug aslinya.
void main() {
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

  Future<void> pumpKasir(WidgetTester tester) async {
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
  }

  Future<void> seedSimpleProduct() async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Minyak Goreng 2 Liter'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't1', productUnitId: 'u1', price: 25000));
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

  TextField searchField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);

  Future<void> focusAndType(WidgetTester tester, String text) async {
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    if (text.isNotEmpty) {
      await tester.enterText(find.byType(TextField).first, text);
      await tester.pumpAndSettle();
    }
  }

  Future<void> unfocusSearch(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> tapPlus(WidgetTester tester, int addControlIndex) async {
    final control = find.byType(AddControl).at(addControlIndex);
    await tester.tap(
        find.descendant(of: control, matching: find.byIcon(Icons.add_rounded)));
    await tester.pumpAndSettle();
  }

  Future<void> tapMinus(WidgetTester tester, int addControlIndex) async {
    final control = find.byType(AddControl).at(addControlIndex);
    await tester.tap(find.descendant(
        of: control, matching: find.byIcon(Icons.remove_rounded)));
    await tester.pumpAndSettle();
  }

  group('kartu grid', () {
    testWidgets(
        'field fokus + ada teks lama → tap "+" select-all teks pencarian',
        (tester) async {
      await seedSimpleProduct();
      await pumpKasir(tester);

      await focusAndType(tester, 'minyak');
      await tapPlus(tester, 0);

      expect(searchField(tester).focusNode!.hasFocus, isTrue);
      final sel = searchField(tester).controller!.selection;
      expect(sel.baseOffset, 0);
      expect(sel.extentOffset, 'minyak'.length);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('field fokus + KOSONG → tap "+" tidak error, tidak ada select',
        (tester) async {
      await seedSimpleProduct();
      await pumpKasir(tester);

      await focusAndType(tester, '');
      await tapPlus(tester, 0);
      expect(tester.takeException(), isNull);

      final sel = searchField(tester).controller!.selection;
      expect(sel.baseOffset == sel.extentOffset, isTrue,
          reason: 'tidak ada teks utk di-select, selection tidak boleh '
              'merentang');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'field collapsed/tidak fokus + ada teks lama → tap "+" TIDAK '
        'menyentuh field cari sama sekali', (tester) async {
      await seedSimpleProduct();
      await pumpKasir(tester);

      await focusAndType(tester, 'minyak');
      await unfocusSearch(tester);
      expect(searchField(tester).focusNode!.hasFocus, isFalse,
          reason: 'prasyarat: field harus sudah collapse/tidak fokus');
      final selBefore = searchField(tester).controller!.selection;

      await tapPlus(tester, 0);

      expect(searchField(tester).focusNode!.hasFocus, isFalse,
          reason: 'tap stepper saat field collapsed TIDAK boleh memicu fokus');
      final selAfter = searchField(tester).controller!.selection;
      expect(selAfter, equals(selBefore));
      expect(searchField(tester).controller!.text, 'minyak');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'field fokus + ada teks lama → tap "-" (setelah qty>0) select-all '
        'juga', (tester) async {
      await seedSimpleProduct();
      await pumpKasir(tester);

      // Bentuk qty>0 dulu tanpa peduli state field cari.
      await tapPlus(tester, 0);

      await focusAndType(tester, 'minyak');
      await tapMinus(tester, 0);

      expect(searchField(tester).focusNode!.hasFocus, isTrue);
      final sel = searchField(tester).controller!.selection;
      expect(sel.baseOffset, 0);
      expect(sel.extentOffset, 'minyak'.length);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('tile daftar (mode list)', () {
    Future<void> switchToList(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'field fokus + ada teks lama → tap "+" select-all teks pencarian',
        (tester) async {
      await seedSimpleProduct();
      await pumpKasir(tester);
      await switchToList(tester);

      await focusAndType(tester, 'minyak');
      await tapPlus(tester, 0);

      expect(searchField(tester).focusNode!.hasFocus, isTrue);
      final sel = searchField(tester).controller!.selection;
      expect(sel.baseOffset, 0);
      expect(sel.extentOffset, 'minyak'.length);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('field fokus + KOSONG → tap "+" tidak error, tidak ada select',
        (tester) async {
      await seedSimpleProduct();
      await pumpKasir(tester);
      await switchToList(tester);

      await focusAndType(tester, '');
      await tapPlus(tester, 0);
      expect(tester.takeException(), isNull);

      final sel = searchField(tester).controller!.selection;
      expect(sel.baseOffset == sel.extentOffset, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'field collapsed/tidak fokus + ada teks lama → tap "+" TIDAK '
        'menyentuh field cari sama sekali', (tester) async {
      await seedSimpleProduct();
      await pumpKasir(tester);
      await switchToList(tester);

      await focusAndType(tester, 'minyak');
      await unfocusSearch(tester);
      final selBefore = searchField(tester).controller!.selection;

      await tapPlus(tester, 0);

      expect(searchField(tester).focusNode!.hasFocus, isFalse);
      final selAfter = searchField(tester).controller!.selection;
      expect(selAfter, equals(selBefore));
      expect(searchField(tester).controller!.text, 'minyak');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('baris varian (dropdown inline)', () {
    Future<void> switchToList(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();
    }

    // longPress SETELAH ketik query cari (bukan sebelum) — mengetik memicu
    // rebuild list (filter query) yang mereset state `_expanded` tile kalau
    // longPress dilakukan sebelum itu. Ganti mode grid->list juga wajib
    // dilakukan SEBELUM field cari fokus/expanded — tombol toggle grid/list
    // ada di topbar yang jadi tertutup/offscreen saat field cari melebar.
    Future<void> expandVariant(WidgetTester tester) async {
      await tester.longPress(find.text('Pop Ice'));
      await tester.pumpAndSettle();
      expect(find.text('Coklat'), findsOneWidget);
    }

    testWidgets(
        'field fokus + ada teks lama → tap "+" baris varian select-all teks '
        'pencarian', (tester) async {
      await seedParentWithVariant();
      await pumpKasir(tester);
      await switchToList(tester);

      // Teks pencarian sengaja tetap cocok dgn "Pop Ice" (bukan produk lain)
      // supaya baris varian TETAP tampil setelah difilter oleh query ini —
      // beda dgn skenario nyata (mencari produk lain), tapi disini yang mau
      // dibuktikan cuma perilaku highlight-nya, bukan filter pencariannya.
      await focusAndType(tester, 'pop ice');
      await expandVariant(tester);
      // AddControl index 1 = baris varian (index 0 = induk).
      await tapPlus(tester, 1);

      expect(searchField(tester).focusNode!.hasFocus, isTrue);
      final sel = searchField(tester).controller!.selection;
      expect(sel.baseOffset, 0);
      expect(sel.extentOffset, 'pop ice'.length);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('field fokus + KOSONG → tap "+" baris varian tidak error',
        (tester) async {
      await seedParentWithVariant();
      await pumpKasir(tester);
      await switchToList(tester);

      await focusAndType(tester, '');
      await expandVariant(tester);
      await tapPlus(tester, 1);
      expect(tester.takeException(), isNull);

      final sel = searchField(tester).controller!.selection;
      expect(sel.baseOffset == sel.extentOffset, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'field collapsed/tidak fokus + ada teks lama → tap "+" baris varian '
        'TIDAK menyentuh field cari sama sekali', (tester) async {
      await seedParentWithVariant();
      await pumpKasir(tester);
      await switchToList(tester);

      await focusAndType(tester, 'pop ice');
      await expandVariant(tester);
      await unfocusSearch(tester);
      final selBefore = searchField(tester).controller!.selection;

      await tapPlus(tester, 1);

      expect(searchField(tester).focusNode!.hasFocus, isFalse);
      final selAfter = searchField(tester).controller!.selection;
      expect(selAfter, equals(selBefore));
      expect(searchField(tester).controller!.text, 'pop ice');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });
}
