import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/cek_stok_screen.dart';

import 'helpers/pump_app.dart';

/// Item 93 (usulan user) — panel Order Restock di Cek Stok:
///  * chip kategori bisa dilipat/dibuka, pilihan TERAKHIR disimpan;
///  * kolom teks + Salin/Kirim SELALU terlihat;
///  * kolom teks bisa diperbesar (tombol pojok kanan atas di dalam field),
///    tingginya = tinggi chip (terbuka) + kolom normal; saat diperbesar
///    chip ditimpa sementara; keadaan diperbesar TIDAK disimpan.
void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(101), name: 'Pcs'),
        mode: InsertMode.insertOrIgnore);
    for (final (gid, gname, pname) in [
      (1, 'Sembako', 'Beras'),
      (2, 'Gas', 'Lpg'),
    ]) {
      await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
          id: Value(gid), name: Value(gname)));
      final id = 'p-$pname';
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: pname,
          productGroupId: Value(gid),
          markedOutOfStock: const Value(true)));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '$id-base',
          productId: id,
          isBaseUnit: const Value(true),
          unitTypeId: const Value(101)));
      await db.adjustStock(productUnitId: '$id-base', newQty: -10);
    }
  });
  tearDown(() async => db.close());

  const toggle = ValueKey('outcat-panel-toggle');
  const chip = ValueKey('outcat-1');
  const expandBtn = ValueKey('order-field-expand');
  const expandedField = ValueKey('order-field-expanded');

  Future<void> open(WidgetTester tester) async {
    await pumpWithFakeApp(tester,
        db: db,
        child: const CekStokScreen(),
        surfaceSize: const Size(412, 900));
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('chip dilipat -> tersembunyi, teks & Salin tetap; pilihan '
      'tersimpan saat layar dibuka ulang', (tester) async {
    await open(tester);
    expect(find.byKey(chip), findsOneWidget, reason: 'awal = terbuka');

    await tester.tap(find.byKey(toggle));
    await tester.pumpAndSettle();
    expect(find.byKey(chip), findsNothing);
    expect(find.text('Salin'), findsOneWidget);
    expect(find.text('Kirim ke Supplier'), findsOneWidget);
    expect(await db.getSetting('cek_stok_category_panel_expanded'), '0');

    // Buka ulang layar (provider baru) -> tetap terlipat.
    await drain(tester);
    await open(tester);
    expect(find.byKey(chip), findsNothing,
        reason: 'tanpa persistensi: kembali terbuka tiap layar dibuka');
    await drain(tester);
  });

  testWidgets('field diperbesar: menimpa chip, tinggi = chip + field normal; '
      'diperkecil -> chip kembali', (tester) async {
    await open(tester);
    final chipsBottom =
        tester.getBottomLeft(find.byKey(chip)).dy; // chip terbuka
    final normalField = find.byType(TextField).last;
    final normalTop = tester.getTopLeft(normalField).dy;
    final normalBottom = tester.getBottomLeft(normalField).dy;
    final salinTop = tester.getTopLeft(find.text('Salin')).dy;
    expect(chipsBottom, lessThan(normalTop));

    await tester.tap(find.byKey(expandBtn));
    await tester.pumpAndSettle();
    expect(find.byKey(expandedField), findsOneWidget);
    expect(find.byKey(chip), findsNothing,
        reason: 'chip ditimpa sementara oleh field diperbesar');
    // Tinggi panel konstan: tombol Salin tidak bergeser.
    expect(tester.getTopLeft(find.text('Salin')).dy,
        moreOrLessEquals(salinTop, epsilon: 1));
    expect(tester.getBottomLeft(find.byKey(expandedField)).dy,
        moreOrLessEquals(normalBottom, epsilon: 1));

    await tester.tap(find.byKey(expandBtn));
    await tester.pumpAndSettle();
    expect(find.byKey(expandedField), findsNothing);
    expect(find.byKey(chip), findsOneWidget,
        reason: 'chip kembali ke keadaan terakhirnya (terbuka)');
    await drain(tester);
  });

  testWidgets('keadaan field diperbesar TIDAK disimpan', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(expandBtn));
    await tester.pumpAndSettle();
    await drain(tester);
    await open(tester);
    expect(find.byKey(expandedField), findsNothing,
        reason: 'selalu mulai ciut');
    expect(find.byKey(chip), findsOneWidget);
    await drain(tester);
  });
}
