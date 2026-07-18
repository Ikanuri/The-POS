import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/product_proposal_review_screen.dart';

import 'helpers/pump_app.dart';

/// Diff harga (sebelum→sesudah) dirender via `RichText`/`TextSpan`, BUKAN
/// `Text` biasa — `find.text`/`find.textContaining` TIDAK bisa melihatnya
/// (cuma cek widget `Text`/`EditableText`). Matcher ini cek plain-text hasil
/// gabungan seluruh span di widget `RichText` mana pun di layar.
Finder findRichTextContaining(String substring) => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText().contains(substring));

/// Item 40 — layar review usulan harga/produk dari device non-owner: harga
/// berubah tampil sebelum→sesudah, produk baru tampil di bagian "Baru".
/// (Alur "Terapkan" penuh — tulis ke DB host — sudah diuji tuntas di
/// level DB via product_proposal_test.dart; widget test di sini fokus ke
/// RENDER diff & interaksi checkbox, bukan mengulang cakupan yang sama.)
void main() {
  Future<PendingProductProposal> buildProposalFromAsisten({
    required List<(String id, String name, int price)> existingChanges,
    required List<(String id, String name, int price)> newProducts,
  }) async {
    final asistenDb = AppDatabase(NativeDatabase.memory());
    for (final (id, name, price) in [...existingChanges, ...newProducts]) {
      await asistenDb.into(asistenDb.products).insert(
          ProductsCompanion.insert(id: id, name: name));
      final unitId = '$id-u';
      await asistenDb.into(asistenDb.productUnits).insert(
          ProductUnitsCompanion.insert(
              id: unitId, productId: id, isBaseUnit: const Value(true)));
      await asistenDb.into(asistenDb.priceTiers).insert(
          PriceTiersCompanion.insert(
              id: '$id-t', productUnitId: unitId, price: price));
      await asistenDb.markProductLocallyModified(id);
    }
    final rows = await asistenDb.dumpLocalProposals();
    await asistenDb.close();
    return PendingProductProposal(
      id: 'prop1',
      fromIp: '192.168.1.50',
      arrivedAt: DateTime.now(),
      rows: rows,
      productCount: existingChanges.length + newProducts.length,
    );
  }

  testWidgets(
      'harga produk yang sudah ada tampil sebelum→sesudah, produk baru '
      'tampil di bagian "Baru"', (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    // Produk existing di host dgn harga LAMA (10000) — asisten usulkan 12000.
    await hostDb.into(hostDb.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Gula'));
    await hostDb.into(hostDb.productUnits).insert(
        ProductUnitsCompanion.insert(
            id: 'p1-u', productId: 'p1', isBaseUnit: const Value(true)));
    await hostDb.into(hostDb.priceTiers).insert(
        PriceTiersCompanion.insert(
            id: 'p1-t', productUnitId: 'p1-u', price: 10000));

    final proposal = await buildProposalFromAsisten(
      existingChanges: [('p1', 'Gula', 12000)],
      newProducts: [('p2', 'Kopi Baru', 5000)],
    );

    await pumpWithFakeApp(
      tester,
      db: hostDb,
      child: ProductProposalReviewScreen(proposal: proposal),
    );

    expect(find.text('Harga/Produk Berubah (1)'), findsOneWidget);
    expect(find.text('Produk Baru (1)'), findsOneWidget);
    expect(findRichTextContaining('Rp 10.000'), findsOneWidget);
    expect(findRichTextContaining('Rp 12.000'), findsOneWidget);
    expect(find.text('Kopi Baru'), findsOneWidget);

    await hostDb.close();
  });

  testWidgets(
      'semua usulan default TERCENTANG, uncheck salah satu mengurangi '
      'jumlah di tombol Terapkan', (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final proposal = await buildProposalFromAsisten(
      existingChanges: [],
      newProducts: [
        ('p1', 'Produk A', 1000),
        ('p2', 'Produk B', 2000),
      ],
    );

    await pumpWithFakeApp(
      tester,
      db: hostDb,
      child: ProductProposalReviewScreen(proposal: proposal),
    );

    expect(find.text('Terapkan (2 produk)'), findsOneWidget);

    await tester.tap(find.text('Produk B'));
    await tester.pumpAndSettle();

    expect(find.text('Terapkan (1 produk)'), findsOneWidget);

    await hostDb.close();
  });
}
