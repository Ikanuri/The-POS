import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/produk_form_screen.dart';

import 'helpers/pump_app.dart';

/// Bug user: saat set "Jadikan Satuan Dasar" di satuan LAIN, satuan dasar
/// lama TIDAK ikut dilepas → 2 satuan dasar aktif sekaligus. Fix: form
/// melepas flag dasar dari unit lain begitu satu unit dijadikan dasar
/// (dan memaksa rasio unit dasar baru = 1.0).
void main() {
  Future<void> seedTwoUnitProduct(AppDatabase db) async {
    const productId = 'p1';
    await db.saveProduct(
      product: ProductsCompanion.insert(id: productId, name: 'Sedap Goreng'),
      units: [
        // Biji = satuan dasar awal (rasio 1).
        ProductUnitsCompanion.insert(
            id: 'u-biji',
            productId: productId,
            unitTypeId: const Value(12), // Biji
            isBaseUnit: const Value(true),
            ratioToBase: const Value(1.0)),
        // Dus = non-dasar, isi 40 biji.
        ProductUnitsCompanion.insert(
            id: 'u-dus',
            productId: productId,
            unitTypeId: const Value(14), // Dos
            isBaseUnit: const Value(false),
            ratioToBase: const Value(40.0)),
      ],
      tiersByUnitTempId: {
        'u-biji': [
          PriceTiersCompanion.insert(
              id: 't-biji', productUnitId: 'u-biji', price: 500),
        ],
        'u-dus': [
          PriceTiersCompanion.insert(
              id: 't-dus', productUnitId: 'u-dus', price: 18000),
        ],
      },
      barcodesByUnitTempId: const {},
    );
  }

  testWidgets(
      'set satuan dasar di unit lain → status dasar PINDAH (tetap satu '
      'chip "Dasar", unit lama dilepas), bukan 2 unit dasar sekaligus',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await seedTwoUnitProduct(db);

    await pumpWithFakeApp(
      tester,
      db: db,
      child: const ProdukFormScreen(productId: 'p1'),
      surfaceSize: const Size(480, 2400),
    );

    // Prakondisi: tepat 1 chip "Dasar" (di unit biji) + 1 checkbox
    // "Jadikan Satuan Dasar" (di unit dus, satu-satunya yg belum dasar).
    expect(find.text('Dasar'), findsOneWidget);
    expect(find.text('Jadikan Satuan Dasar'), findsOneWidget);

    // Jadikan "dus" satuan dasar.
    await tester.tap(find.text('Jadikan Satuan Dasar'));
    await tester.pumpAndSettle();

    // BUG lama: 2 chip "Dasar" (flag biji tak pernah dilepas). Setelah fix:
    // status DASAR benar-benar PINDAH — tetap TEPAT 1 chip "Dasar", dan unit
    // biji sekarang menampilkan checkbox "Jadikan Satuan Dasar" lagi (bukti
    // ia sudah dilepas dari status dasar). Chip & checkbox ini merender
    // langsung `_units[i].isBaseUnit`, persis nilai yang ditulis saveProduct.
    expect(find.text('Dasar'), findsOneWidget,
        reason: 'satuan dasar harus tunggal — flag unit lama harus dilepas');
    expect(find.text('Jadikan Satuan Dasar'), findsOneWidget,
        reason: 'unit biji harus kembali menampilkan checkbox (sudah dilepas '
            'dari status dasar), bukan hilang total');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
