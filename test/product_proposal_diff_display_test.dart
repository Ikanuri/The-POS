import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/product_proposal_review_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "kadang ada beberapa kali hanya menampilkan
/// 'tidak ada perubahan harga', padahal sync tersebut diajukan karena ada
/// perubahan [satuan]" — hampir bikin owner dismiss usulan asli krn dikira
/// glitch. Dulu `_ProposalTile` HANYA membandingkan harga tier dasar; kalau
/// yang berubah bukan harga (satuan, isi/rasio, barcode, dst.), teksnya
/// menyesatkan seolah tidak ada apa pun yang berubah. Sekarang harus
/// menampilkan SEMUA aspek yang terdeteksi berubah.
void main() {
  Future<PendingProductProposal> buildProposal(AppDatabase asistenDb) async {
    final rows = await asistenDb.dumpLocalProposals();
    return PendingProductProposal(
      id: 'prop1',
      fromIp: '192.168.1.50',
      arrivedAt: DateTime.now(),
      rows: rows,
      productCount: (rows['products'] ?? const []).length,
    );
  }

  testWidgets(
      'satuan diubah (harga TETAP sama) -> tampil "Satuan diubah: X → Y", '
      'BUKAN "Tidak ada perubahan harga" yang menyesatkan', (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    await hostDb.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Minyak Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u',
            productId: 'p1',
            unitTypeId: const Value(2), // Pcs
            isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t', productUnitId: 'p1-u', price: 15000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final asistenDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => asistenDb.close());
    await asistenDb.saveProduct(
      product: ProductsCompanion.insert(
          id: 'p1', name: 'Minyak Goreng', locallyModified: const Value(true)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u',
            productId: 'p1',
            unitTypeId: const Value(4), // Pak — DIUBAH dari Pcs
            isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          // Harga SAMA PERSIS (15000) — cuma satuan yang berubah.
          PriceTiersCompanion.insert(id: 'p1-t2', productUnitId: 'p1-u', price: 15000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final proposal = await buildProposal(asistenDb);
    await pumpWithFakeApp(tester,
        db: hostDb, child: ProductProposalReviewScreen(proposal: proposal));

    expect(find.textContaining('Tidak ada perubahan harga'), findsNothing,
        reason: 'pesan lama yang menyesatkan tidak boleh muncul lagi utk '
            'kasus ini — usulan MEMANG ada perubahan (satuan)');
    expect(find.textContaining('Satuan diubah: Pcs → Pak'), findsOneWidget,
        reason: 'unit_type_id di host=2 (Pcs), diusulkan asisten jadi 4 '
            '(Pak) — lihat _kDefaultUnitTypes di app_database.dart');

    await hostDb.close();
  });

  testWidgets(
      'nama produk diubah (harga & satuan tetap) -> tampil "Nama: ... → ..."',
      (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    await hostDb.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Sabun Lama'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t', productUnitId: 'p1-u', price: 3000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final asistenDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => asistenDb.close());
    await asistenDb.saveProduct(
      product: ProductsCompanion.insert(
          id: 'p1', name: 'Sabun Baru', locallyModified: const Value(true)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t2', productUnitId: 'p1-u', price: 3000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final proposal = await buildProposal(asistenDb);
    await pumpWithFakeApp(tester,
        db: hostDb, child: ProductProposalReviewScreen(proposal: proposal));

    expect(find.textContaining('Nama: "Sabun Lama" → "Sabun Baru"'),
        findsOneWidget);
    expect(find.textContaining('Tidak ada perubahan harga'), findsNothing);

    await hostDb.close();
  });

  testWidgets(
      'barcode baru ditambahkan (harga & satuan tetap) -> tampil info '
      'barcode', (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    await hostDb.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Teh Botol'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t', productUnitId: 'p1-u', price: 5000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final asistenDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => asistenDb.close());
    await asistenDb.saveProduct(
      product: ProductsCompanion.insert(
          id: 'p1', name: 'Teh Botol', locallyModified: const Value(true)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t2', productUnitId: 'p1-u', price: 5000),
        ],
      },
      barcodesByUnitTempId: {
        'p1-u': [
          ProductBarcodesCompanion.insert(
              id: 'bc1', productUnitId: 'p1-u', barcode: '8991234567890'),
        ],
      },
      altPricesByUnitTempId: const {},
    );

    final proposal = await buildProposal(asistenDb);
    await pumpWithFakeApp(tester,
        db: hostDb, child: ProductProposalReviewScreen(proposal: proposal));

    expect(find.textContaining('Barcode'), findsOneWidget);
    expect(find.textContaining('8991234567890'), findsOneWidget);
    expect(find.textContaining('Tidak ada perubahan harga'), findsNothing);

    await hostDb.close();
  });

  testWidgets(
      'satuan baru ditambahkan (mis. varian kemasan) -> tampil "Satuan baru '
      'ditambahkan"', (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    await hostDb.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Beras'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u',
            productId: 'p1',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t', productUnitId: 'p1-u', price: 12000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final asistenDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => asistenDb.close());
    await asistenDb.saveProduct(
      product: ProductsCompanion.insert(
          id: 'p1', name: 'Beras', locallyModified: const Value(true)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u',
            productId: 'p1',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true)),
        ProductUnitsCompanion.insert(
            id: 'p1-u2',
            productId: 'p1',
            unitTypeId: const Value(6), // Sak
            isBaseUnit: const Value(false),
            ratioToBase: const Value(25)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t2', productUnitId: 'p1-u', price: 12000),
        ],
        'p1-u2': [
          PriceTiersCompanion.insert(
              id: 'p1-t3', productUnitId: 'p1-u2', price: 290000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final proposal = await buildProposal(asistenDb);
    await pumpWithFakeApp(tester,
        db: hostDb, child: ProductProposalReviewScreen(proposal: proposal));

    expect(find.textContaining('Satuan baru ditambahkan: Sak'), findsOneWidget);
    expect(find.textContaining('Tidak ada perubahan harga'), findsNothing);

    await hostDb.close();
  });

  testWidgets(
      'harga BENAR-BENAR berubah -> tampilan lama (RichText sebelum→sesudah) '
      'TETAP jalan seperti sebelumnya, tanpa baris tambahan yang tidak perlu',
      (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    await hostDb.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Gula'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t', productUnitId: 'p1-u', price: 10000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final asistenDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => asistenDb.close());
    await asistenDb.saveProduct(
      product: ProductsCompanion.insert(
          id: 'p1', name: 'Gula', locallyModified: const Value(true)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'p1-u', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'p1-u': [
          PriceTiersCompanion.insert(id: 'p1-t2', productUnitId: 'p1-u', price: 12000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final proposal = await buildProposal(asistenDb);
    await pumpWithFakeApp(tester,
        db: hostDb, child: ProductProposalReviewScreen(proposal: proposal));

    final richTextWithPrice = find.byWidgetPredicate((w) =>
        w is RichText &&
        w.text.toPlainText().contains('Rp 10.000') &&
        w.text.toPlainText().contains('Rp 12.000'));
    expect(richTextWithPrice, findsOneWidget);
    expect(find.textContaining('Tidak ada perubahan harga'), findsNothing);
    expect(find.textContaining('Tidak ada perubahan terdeteksi'), findsNothing);

    await hostDb.close();
  });
}
