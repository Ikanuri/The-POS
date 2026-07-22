import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/price_match_service.dart';
import 'package:the_pos/core/services/price_sync_service.dart';
import 'package:the_pos/features/produk/price_preview_screen.dart';

import 'helpers/pump_app.dart';

/// Inti dari redesain sinkron harga (task manager 21 Juli): begitu owner
/// KONFIRMASI sebuah pasangan produk (Tingkat 3/4, nama+satuan atau pilih
/// manual dari kandidat ganda), aplikasi harus MENULISKAN barcode katalog
/// sbg alias permanen ke produk lokal itu — supaya sinkron BERIKUTNYA utk
/// produk yang SAMA langsung lompat ke Tingkat 1 (barcode), TIDAK PERNAH
/// ditinjau ulang lagi. Ini yang menutup akar masalah "harga berubah
/// sendiri padahal sudah fixed" (dulu: setiap sinkron menebak dari nol,
/// tanpa ingatan sama sekali).
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.batch((b) {
      b.insertAll(db.unitTypes,
          [UnitTypesCompanion.insert(id: const Value(102), name: 'Pak')]);
    });
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p_234', name: '234 16'),
      units: [
        ProductUnitsCompanion.insert(
          id: 'u_234',
          productId: 'p_234',
          unitTypeId: const Value(102),
          isBaseUnit: const Value(true),
        ),
      ],
      tiersByUnitTempId: {
        'u_234': [
          PriceTiersCompanion.insert(
              id: 't_234', productUnitId: 'u_234', price: 25000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
  });
  tearDown(() async => db.close());

  const catalogItem = PriceCatalogItem(
    productName: '234 16',
    kodeProduk: null,
    barcode: '8999909010567',
    unitTypeName: 'Pak',
    price: 25500,
    costPrice: 0,
  );

  testWidgets(
      'konfirmasi kandidat tunggal (Samakan) → barcode katalog tertaut '
      'permanen, harga terupdate, DAN sync berikutnya utk produk sama '
      'langsung Tingkat 1 (barcode) — tanpa perlu ditinjau lagi',
      (tester) async {
    final before =
        await PriceMatchService.match(db: db, catalog: const [catalogItem]);
    expect(before.matched, isEmpty);
    expect(before.ambiguous, hasLength(1));
    expect(
        before.ambiguous.first.reason, AmbiguousReason.nameUniqueCandidate);

    await pumpWithFakeApp(tester,
        db: db, child: PricePreviewScreen(result: before));

    // Tab "Perlu Ditinjau".
    await tester.tap(find.text('Perlu Ditinjau (1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Samakan'));
    await tester.pumpAndSettle();

    // TIDAK pakai pumpAndSettle() sebelum dialog "Selesai" ditutup —
    // `_apply()` menahan `_busy=true` (spinner tombol Terapkan terus
    // beranimasi) selama `showDialog` masih menunggu ditutup, jadi
    // pumpAndSettle() tidak akan pernah selesai sampai dialognya dismiss.
    await tester.tap(find.text('Terapkan (1 perubahan)'));
    await tester.pump();
    await tester.pump();
    // Dialog "Selesai" muncul — tutup via OK.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // 1. Harga terupdate.
    final tiers = await db.getPriceTiers('u_234');
    expect(tiers.single.price, 25500);

    // 2. Barcode katalog tertaut permanen (non-primary — tidak menimpa
    // apa pun, produk ini memang belum punya barcode sama sekali).
    final linked = await db.lookupBarcode('8999909010567');
    expect(linked, isNotNull);
    expect(linked!.productUnitId, 'u_234');

    // 3. INI BUKTI UTAMANYA — sync berikutnya utk produk yang SAMA PERSIS
    // sekarang lompat ke Tingkat 1 (barcode), tidak perlu ditinjau lagi.
    final after =
        await PriceMatchService.match(db: db, catalog: const [catalogItem]);
    expect(after.ambiguous, isEmpty,
        reason: 'produk yang sudah dikonfirmasi TIDAK BOLEH muncul lagi di '
            'tinjauan manual pada sync berikutnya');
    expect(after.matched, hasLength(1));
    expect(after.matched.first.matchType, MatchType.barcode);
  });
}
