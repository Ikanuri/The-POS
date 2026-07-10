import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Item 20 — tombol edit produk di modal ItemEntrySheet HANYA untuk
/// owner/asisten, disembunyikan untuk role kasir.
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

  DeviceIdentity device(String role) => DeviceIdentity(
        storeUuid: 's',
        storeKey: 'k',
        storeName: 'Toko',
        deviceName: 'Dev',
        deviceCode: 'K1',
        deviceRole: role,
      );

  testWidgets('OWNER melihat tombol edit produk di modal', (tester) async {
    await pumpWithFakeApp(tester,
        db: db,
        device: device('owner'),
        child: ItemEntrySheet(product: product));
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('ASISTEN melihat tombol edit produk di modal', (tester) async {
    await pumpWithFakeApp(tester,
        db: db,
        device: device('asisten'),
        child: ItemEntrySheet(product: product));
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('KASIR TIDAK melihat tombol edit produk', (tester) async {
    await pumpWithFakeApp(tester,
        db: db,
        device: device('kasir'),
        child: ItemEntrySheet(product: product));
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });
}
