import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Widget test — pengecualian "tap + / badan produk TIDAK mengecilkan field
/// cari" saat field sedang expanded & berisi teks (lihat
/// `_markSkipSearchCollapse` di kasir_screen.dart). Tanpa pengecualian ini,
/// tap "+" pada hasil pencarian akan langsung menutup/mengecilkan field —
/// mengganggu alur tap-berulang saat memilih beberapa barang hasil cari.
Future<void> _addProduct(AppDatabase db,
    {required String name, required int price}) async {
  final productId = 'p-$name';
  final unitId = '$productId-u';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: productId,
        name: name,
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId,
        productId: productId,
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: '$unitId-t1',
        productUnitId: unitId,
        price: price,
      ));
}

Future<double> _searchFieldWidth(WidgetTester tester) async {
  final box = tester.renderObject<RenderBox>(find.byType(TextField).first);
  return box.size.width;
}

/// Sama seperti `pumpWithFakeApp`, tapi mem-pre-set contoh "swipe hint
/// keranjang" sudah lewat 3x (`kasir_swipe_hint_count`) — menghindari baris
/// hint "Geser ke atas..." di `_CartBar` yang overflow pada lebar test
/// (bug pre-existing tak terkait fitur ini, sudah ada sebelum sesi ini).
Future<void> _pumpKasir(WidgetTester tester, AppDatabase db) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({'kasir_swipe_hint_count': 3});

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = const DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            storeName: 'Toko Uji',
            deviceName: 'Kasir Uji',
            deviceCode: 'K1',
            deviceRole: 'owner',
          )),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const KasirScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'tap "+" pada kartu produk SAAT field cari expanded & berisi teks '
      'TIDAK mengecilkan/menghapus field — barang tetap masuk keranjang',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, name: 'Gula Pasir', price: 15000);
    await _pumpKasir(tester, db);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'gula');
    await tester.pumpAndSettle();

    expect(find.text('Gula Pasir'), findsOneWidget,
        reason: 'prasyarat: produk hasil cari harus tampil');
    final widthBeforeTap = await _searchFieldWidth(tester);
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget,
        reason: 'prasyarat: field masih expanded sebelum tap +');

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    final widthAfterTap = await _searchFieldWidth(tester);
    expect(widthAfterTap, closeTo(widthBeforeTap, 1),
        reason: 'field TIDAK boleh mengecil akibat tap + saat berisi teks');
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget,
        reason: 'field harus tetap expanded (fokus tidak hilang)');
    final ctrlText =
        tester.widget<TextField>(find.byType(TextField).first).controller!.text;
    expect(ctrlText, 'gula', reason: 'teks pencarian tidak boleh terhapus');

    await db.close();
  });

  testWidgets(
      'tap badan kartu produk (buka modal pilih harga) SAAT field cari '
      'expanded & berisi teks TIDAK mengecilkan field', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, name: 'Gula Pasir', price: 15000);
    await _pumpKasir(tester, db);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'gula');
    await tester.pumpAndSettle();

    final widthBeforeTap = await _searchFieldWidth(tester);

    await tester.tap(find.text('Gula Pasir'));
    await tester.pumpAndSettle();

    final widthAfterTap = await _searchFieldWidth(tester);
    expect(widthAfterTap, closeTo(widthBeforeTap, 1),
        reason: 'field TIDAK boleh mengecil akibat tap badan kartu produk '
            '(walau tap itu membuka modal ItemEntrySheet)');

    await db.close();
  });

  testWidgets(
      'tap + saat field cari expanded TAPI KOSONG (tanpa teks) tetap '
      'mengecilkan field seperti biasa — pengecualian hanya berlaku bila '
      'ada karakter di dalamnya', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, name: 'Gula Pasir', price: 15000);
    await _pumpKasir(tester, db);

    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    // Tidak mengetik apa pun — field expanded tapi kosong.
    expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();

    final width = await _searchFieldWidth(tester);
    expect(width, lessThan(200),
        reason: 'tanpa teks, tap + di luar field tetap mengecilkan field '
            'seperti perilaku normal (tidak ada yang perlu dipertahankan)');

    await db.close();
  });
}
