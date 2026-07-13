import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Item 25a — tandai/lepas "stok habis" cepat lewat modal item kasir.
void main() {
  late AppDatabase db;
  late Product product;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Kopi Sachet'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    product = (await db.searchProducts('')).first;
  });

  tearDown(() async {
    await db.close();
  });

  const device = DeviceIdentity(
    storeUuid: 's',
    storeKey: 'k',
    storeName: 'Toko',
    deviceName: 'Dev',
    deviceCode: 'K1',
    deviceRole: 'kasir', // semua role bisa toggle, tidak dibatasi izin
  );

  testWidgets(
      'tap tombol tandai stok habis → icon berubah & tersimpan ke DB',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, device: device, child: ItemEntrySheet(product: product));

    expect(find.byIcon(Icons.remove_shopping_cart_outlined), findsOneWidget);
    expect(find.byIcon(Icons.remove_shopping_cart), findsNothing);

    await tester.tap(find.byIcon(Icons.remove_shopping_cart_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.remove_shopping_cart), findsOneWidget);
    expect(find.byIcon(Icons.remove_shopping_cart_outlined), findsNothing);

    final row = await (db.select(db.products)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(row.markedOutOfStock, isTrue);
  });

  testWidgets('tap dua kali → kembali ke stok tersedia (toggle)',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, device: device, child: ItemEntrySheet(product: product));

    await tester.tap(find.byIcon(Icons.remove_shopping_cart_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_shopping_cart));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.remove_shopping_cart_outlined), findsOneWidget);
    final row = await (db.select(db.products)
          ..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(row.markedOutOfStock, isFalse);
  });
}
