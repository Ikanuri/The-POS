import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Item 49e — "Tambah Satuan" harus langsung menggulir ke kartu satuan yang
/// baru ditambahkan (form bisa panjang, kartu baru selalu di paling bawah)
/// DAN autofocus field harga-nya, supaya user tidak perlu scroll manual
/// utk mulai mengisi.
void main() {
  Future<void> seedProductWithUnits(AppDatabase db, int unitCount) async {
    const productId = 'p1';
    final units = <ProductUnitsCompanion>[];
    final tiers = <String, List<PriceTiersCompanion>>{};
    for (var i = 0; i < unitCount; i++) {
      final id = 'u$i';
      units.add(ProductUnitsCompanion.insert(
        id: id,
        productId: productId,
        unitTypeId: const Value(12),
        isBaseUnit: Value(i == 0),
        ratioToBase: Value(i == 0 ? 1.0 : (i + 1) * 10.0),
      ));
      tiers[id] = [
        PriceTiersCompanion.insert(
            id: 't$i', productUnitId: id, price: 1000 * (i + 1)),
      ];
    }
    await db.saveProduct(
      product:
          ProductsCompanion.insert(id: productId, name: 'Produk Uji Satuan'),
      units: units,
      tiersByUnitTempId: tiers,
      barcodesByUnitTempId: const {},
    );
  }

  testWidgets(
      'tap "Tambah Satuan" → kartu baru tergulir ke pandangan & field '
      'harganya langsung fokus (tak perlu scroll manual)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // 3 satuan sudah ada → cukup panjang utk kartu ke-4 (baru) mulai di
    // luar viewport pendek, tapi masih di dalam cache-extent default
    // sliver (jumlah satuan realistis, bukan skenario ekstrem).
    await seedProductWithUnits(db, 3);

    // Surface PENDEK (bukan default generus 430x2400 harness) — perlu
    // supaya kartu satuan ke-4 betul-betul mulai di luar viewport visible,
    // sesuai gotcha CLAUDE.md soal surface pendek utk menangkap bug layout/
    // visibilitas (di sini dipakai kebalikannya: sengaja PENDEK utk
    // membuktikan ensureVisible benar-benar menggulir).
    await pumpWithFakeApp(
      tester,
      db: db,
      child: const ProdukFormScreen(productId: 'p1'),
      surfaceSize: const Size(390, 700),
    );
    addTearDown(() async => db.close());

    expect(find.text('Satuan 4'), findsNothing,
        reason: 'belum ditambah, kartu ke-4 belum ada');

    await tester.tap(find.text('Tambah Satuan'));
    await tester.pumpAndSettle();

    // Kartu baru harus SUDAH ter-build (ensureVisible memaksa sliver
    // mem-build & meletakkannya).
    final newCardTitle = find.text('Satuan 4');
    expect(newCardTitle, findsOneWidget,
        reason: 'kartu satuan ke-4 harus sudah ter-build setelah tap');

    // Kartu baru harus VISIBLE di layar (di dalam batas surface 700px),
    // bukan cuma ter-build tapi tetap di luar viewport.
    final titleRect = tester.getRect(newCardTitle);
    expect(titleRect.top, greaterThanOrEqualTo(0));
    expect(titleRect.bottom, lessThanOrEqualTo(700),
        reason: 'kartu satuan baru harus tergulir ke dalam viewport (tinggi '
            'surface 700px), bukan tersembunyi di bawah');

    // Field "Harga Jual (Rp)" DI DALAM kartu baru harus dapat fokus
    // otomatis — cari EditableText pertama di dalam Card kartu ini (field
    // pertama setelah dropdown "Jenis Satuan" adalah _priceCtrl).
    final newCard = find
        .ancestor(of: newCardTitle, matching: find.byType(Card))
        .first;
    final priceEditable = find
        .descendant(of: newCard, matching: find.byType(EditableText))
        .first;
    final editableWidget = tester.widget<EditableText>(priceEditable);
    expect(editableWidget.focusNode.hasFocus, isTrue,
        reason: 'field harga di kartu satuan baru harus langsung fokus');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
