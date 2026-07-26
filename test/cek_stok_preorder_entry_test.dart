import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/cek_stok_screen.dart';

import 'helpers/pump_app.dart';

/// Item 52 ("Laci Meja") — jalur kedua entry Pre-order (jalur pertama:
/// pencarian Kasir saat stok kosong). Tombol "Catat Pre-order" muncul di
/// baris produk yang dicentang (markedOutOfStock) di layar Cek Stok.
void main() {
  late AppDatabase db;

  Future<String> addProduct(AppDatabase db, String name,
      {bool requiresDeposit = false}) async {
    final id = 'p-$name';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, name: name));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '$id-u',
          productId: id,
          isBaseUnit: const Value(true),
          requiresDeposit: Value(requiresDeposit),
        ));
    return id;
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'tombol "Catat Pre-order" hanya muncul stlh produk dicentang, simpan '
      'entri tercatat dgn productId & productUnitId yg benar', (tester) async {
    await addProduct(db, 'Tabung LPG 3kg');
    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());

    expect(find.text('Catat Pre-order'), findsNothing);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('Catat Pre-order'), findsOneWidget);

    await tester.tap(find.text('Catat Pre-order'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Nama pelanggan'), 'Budi');
    await tester.enterText(
        find.widgetWithText(TextField, 'Jumlah dipesan'), '2');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.preorderEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.customerName, 'Budi');
    expect(rows.single.qtyOrdered, 2);
    expect(rows.single.productId, 'p-Tabung LPG 3kg');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'produk requiresDeposit=true: field jaminan wajib diisi min 1, '
      'kosong/0 ditolak (tidak tersimpan)', (tester) async {
    await addProduct(db, 'Tabung LPG 3kg', requiresDeposit: true);
    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catat Pre-order'));
    await tester.pumpAndSettle();

    expect(find.textContaining('wadah dititip'), findsOneWidget,
        reason: 'field jaminan wajib tampil krn produk requiresDeposit');

    await tester.enterText(
        find.widgetWithText(TextField, 'Nama pelanggan'), 'Ani');
    await tester.enterText(
        find.widgetWithText(TextField, 'Jumlah dipesan'), '1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Jumlah wadah dititip (wajib, min 1)'),
        '0');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(await db.select(db.preorderEntries).get(), isEmpty,
        reason: 'requiresDeposit=true tapi jaminan 0 -> DITOLAK, tidak '
            'tersimpan (aturan bisnis: syarat antri adalah titip wadah)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
