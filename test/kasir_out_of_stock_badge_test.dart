import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Item 25a — badge "Habis" kosmetik di kartu produk kasir. HARUS tetap
/// bisa tap tombol tambah (tidak dinonaktifkan) — beda dari katalog HTML
/// yang benar-benar menonaktifkan tombolnya.
void main() {
  testWidgets(
      'produk ditandai stok habis → badge "Habis" tampil di kartu, tombol '
      '+ TETAP berfungsi normal', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1',
          productUnitId: 'u1',
          minQty: const Value(1),
          price: 2500,
        ));
    await db.setMarkedOutOfStock('p1', true);

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Kasir',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

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

    expect(find.text('Sedap Goreng · Habis'), findsOneWidget);
    expect(find.text('Sedap Goreng'), findsNothing);

    // Tombol tambah (lingkaran "+") tetap berfungsi — kosmetik saja, bukan
    // blokir fungsi (beda dari katalog HTML yang benar-benar menonaktifkan).
    final addIcon = find.byIcon(Icons.add_rounded);
    expect(addIcon, findsWidgets);
    await tester.tap(addIcon.first);
    await tester.pumpAndSettle();

    // Setelah tambah, lingkaran "+" berubah jadi angka qty (label "1") —
    // menandakan tap benar-benar berhasil menambah ke keranjang.
    expect(find.text('1'), findsWidgets);

    // Drain drift StreamProvider disposal timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
