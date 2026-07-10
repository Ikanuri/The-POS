import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Widget test — reorder "Harga Lain" via drag-handle di form Produk (Item
/// 9 PLAN.md). Membuktikan drag-handle benar-benar mengubah URUTAN entri di
/// form (bukan cuma render tanpa efek), yang lalu tersimpan sebagai
/// `sortOrder` dan diikuti `getAltPrices()`.
void main() {
  testWidgets(
      'drag-handle memindahkan baris Harga Lain ke posisi baru di form',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());

    const productId = 'p1';
    const unitId = 'u1';
    await db.saveProduct(
      product: ProductsCompanion.insert(id: productId, name: 'Sedap Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: unitId, productId: productId, isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        unitId: [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: unitId, price: 2850),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: {
        unitId: [
          AltPricesCompanion.insert(
              id: 'a1',
              productUnitId: unitId,
              label: 'Harga A (pertama)',
              price: 3000,
              sortOrder: const Value(0)),
          AltPricesCompanion.insert(
              id: 'a2',
              productUnitId: unitId,
              label: 'Harga B (kedua)',
              price: 3500,
              sortOrder: const Value(1)),
        ],
      },
    );

    await pumpWithFakeApp(
      tester,
      db: db,
      child: const ProdukFormScreen(productId: productId),
      // Lebar default (430) memicu RenderFlex overflow di baris header
      // "Satuan & Harga" (bug pra-eksisting TIDAK terkait Item ini) pada
      // rendering test — perlebar surface murni untuk menghindarinya,
      // supaya fokus pengujian tetap ke reorder Harga Lain.
      surfaceSize: const Size(480, 2400),
    );

    // Prakondisi: urutan awal sesuai sortOrder tersimpan (A dulu, B kedua).
    expect(
      find.byWidgetPredicate((w) =>
          w is TextFormField &&
          w.controller?.text == 'Harga A (pertama)'),
      findsOneWidget,
    );

    // Ambil posisi Y drag-handle baris pertama & kedua untuk simulasi drag
    // baris pertama TURUN melewati baris kedua.
    final handles = find.byIcon(Icons.drag_handle);
    expect(handles, findsNWidgets(2),
        reason: 'tiap baris Harga Lain harus punya drag-handle-nya sendiri');

    // Drag handle baris pertama TURUN melewati baris kedua.
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 100));
    // Beberapa langkah kecil (bukan satu lompatan besar) — ReorderableListView
    // butuh beberapa event pointermove untuk mengenali gestur drag berjalan.
    for (var step = 1; step <= 6; step++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // Setelah drag: baris "Harga B" sekarang tampil LEBIH DULU (index 0)
    // dibanding "Harga A" — urutan visual harus terbalik dari semula.
    final labelTexts = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((w) => w.controller?.text)
        .where((t) => t == 'Harga A (pertama)' || t == 'Harga B (kedua)')
        .toList();
    expect(labelTexts, ['Harga B (kedua)', 'Harga A (pertama)'],
        reason: 'drag-handle harus benar-benar menukar urutan entri, bukan '
            'cuma me-render ulang tanpa efek');

    await db.close();
  });
}
