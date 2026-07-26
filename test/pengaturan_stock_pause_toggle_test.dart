import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';

import 'helpers/pump_app.dart';

/// Usulan user: sementara nonaktifkan pelacakan stok utk SEMUA produk
/// (mis. sedang tidak sempat rapikan data stok). Toggle "Jeda Pelacakan
/// Stok" di Pengaturan > Manajemen Data — reversibel, dan produk yang
/// MEMANG sudah non-stok sebelumnya (mis. varian jasa) tidak ikut
/// tersentuh baik saat jeda maupun saat dipulihkan.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Produk biasa (stok dilacak).
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Kopi'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        isBaseUnit: const Value(true),
        isNonStock: const Value(false)));
    // Varian jasa yang MEMANG sudah non-stok sejak awal.
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p2', name: 'Servis'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u2',
        productId: 'p2',
        isBaseUnit: const Value(true),
        isNonStock: const Value(true)));
  });

  tearDown(() async => db.close());

  testWidgets(
      'toggle ON: produk yang tadinya dilacak jadi non-stok, yang sudah '
      'non-stok tidak tersentuh; toggle OFF: kembali seperti semula',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());

    expect(find.text('Jeda Pelacakan Stok'), findsOneWidget);
    var tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Jeda Pelacakan Stok'));
    expect(tile.value, isFalse, reason: 'default OFF');

    await tester.tap(
        find.widgetWithText(SwitchListTile, 'Jeda Pelacakan Stok'));
    await tester.pumpAndSettle();
    // Dialog konfirmasi muncul dulu.
    expect(find.text('Jeda Pelacakan Stok?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Jeda'));
    await tester.pumpAndSettle();

    var u1 = await (db.select(db.productUnits)
          ..where((t) => t.id.equals('u1')))
        .getSingle();
    var u2 = await (db.select(db.productUnits)
          ..where((t) => t.id.equals('u2')))
        .getSingle();
    expect(u1.isNonStock, isTrue,
        reason: 'produk yang tadinya dilacak jadi non-stok');
    expect(u2.isNonStock, isTrue,
        reason: 'varian jasa yang sudah non-stok tetap non-stok (tak ada '
            'perubahan yg perlu diamati, tapi tetap benar)');
    expect(await db.isStockTrackingPaused(), isTrue);

    tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Jeda Pelacakan Stok'));
    expect(tile.value, isTrue);

    // Matikan lagi -> kembali seperti semula, TANPA dialog konfirmasi.
    await tester.tap(
        find.widgetWithText(SwitchListTile, 'Jeda Pelacakan Stok'));
    await tester.pumpAndSettle();

    u1 = await (db.select(db.productUnits)..where((t) => t.id.equals('u1')))
        .getSingle();
    u2 = await (db.select(db.productUnits)..where((t) => t.id.equals('u2')))
        .getSingle();
    expect(u1.isNonStock, isFalse,
        reason: 'dipulihkan persis seperti sebelum dijeda');
    expect(u2.isNonStock, isTrue,
        reason: 'varian jasa yang MEMANG sudah non-stok tetap non-stok, '
            'bukan ikut "dipulihkan" jadi dilacak (dia tak pernah diubah)');
    expect(await db.isStockTrackingPaused(), isFalse);
  });
}
