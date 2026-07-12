import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/produk/produk_list_screen.dart';

import 'helpers/pump_app.dart';

/// Poin 2 — daftar Produk tampilkan harga dasar (satuan dasar, minQty=1)
/// di bawah nama produk.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Unmount tree secara eksplisit lalu pump — memicu disposal
  /// StreamProvider (drift `markAsClosed` menjadwalkan timer 0ms saat
  /// cancel) SELAGI test masih jalan, lalu drain timer itu; kalau tidak,
  /// binding menemukan "Timer still pending" saat disposal di akhir test.
  /// ProdukListScreen pakai StreamProvider (watchLowStockCount) jadi butuh
  /// ini, sama seperti pola di payment_method_edit_delete_test.dart.
  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets('daftar produk tampilkan harga dasar di bawah nama',
      (tester) async {
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2850),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    await pumpWithFakeApp(tester, db: db, child: const ProdukListScreen());

    expect(find.text('Sedap Goreng'), findsOneWidget);
    expect(find.text(formatRupiah(2850)), findsOneWidget);
    await drain(tester);
  });

  testWidgets('produk tanpa satuan/harga TIDAK menampilkan baris harga',
      (tester) async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Tanpa Harga'));

    await pumpWithFakeApp(tester, db: db, child: const ProdukListScreen());

    expect(find.text('Tanpa Harga'), findsOneWidget);
    expect(find.text(formatRupiah(0)), findsNothing);
    await drain(tester);
  });
}
