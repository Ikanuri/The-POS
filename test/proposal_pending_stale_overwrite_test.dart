import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Audit user "sync harga di tab produk, apakah aman bolak-balik?" —
/// jawaban SEBELUM fix ini: TIDAK. Skenario: asisten edit harga produk
/// (tersimpan lokal + `products.locallyModified=true`, usulan belum
/// direview owner) → SEBELUM owner sempat approve, asisten sync lagi utk
/// hal LAIN (rutin) → edit asisten TERTIMPA BALIK/DUPLIKAT oleh data lama
/// owner, tanpa error apa pun.
///
/// Akar masalah: `price_tiers`/`product_units`/`alt_prices`/
/// `product_barcodes` disinkron full-dump TANPA kolom `updated_at` sama
/// sekali (beda dari `products`) — last-write-wins di `mergeRows` tidak
/// berlaku, jadi data owner (yang belum tahu soal edit asisten) SELALU
/// menang tanpa syarat begitu ikut terkirim di sync APAPUN.
///
/// Fix: `mergeRows` skip baris 4 tabel ini kalau unit-nya milik produk yang
/// MASIH `locally_modified=true` di device penerima — biarkan edit lokal
/// yang belum-di-approve tetap utuh sampai owner benar² approve/reject.
void main() {
  Future<AppDatabase> freshDb() async => AppDatabase(NativeDatabase.memory());

  test(
      'price_tiers: harga yang baru diedit lokal (produk locally_modified) '
      'TIDAK tertimpa balik oleh sync data owner yang tidak terkait',
      () async {
    final db = await freshDb();
    addTearDown(db.close);

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Gula', locallyModified: const drift.Value(true)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const drift.Value(true)));
    // Edit lokal asisten: harga baru 1200, id tier baru (pola regenerasi id
    // tiap simpan di produk_form_screen.dart).
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'tier-new', productUnitId: 'u1', price: 1200));

    // Sync TIDAK TERKAIT (mis. owner kirim data produk lain) kebetulan
    // membawa full-dump price_tiers, TERMASUK baris LAMA milik unit ini
    // (owner belum tahu soal edit asisten, harga di sisi owner masih 1000).
    await db.mergeRows('price_tiers', [
      {
        'id': 'tier-old',
        'product_unit_id': 'u1',
        'min_qty': 1,
        'price': 1000,
        'cost_price': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }
    ], false);

    final tiers = await (db.select(db.priceTiers)
          ..where((t) => t.productUnitId.equals('u1')))
        .get();
    expect(tiers, hasLength(1));
    expect(tiers.single.id, 'tier-new',
        reason: 'edit lokal asisten yang belum di-review owner harus TETAP '
            'utuh — bukan tertimpa balik oleh harga lama owner');
    expect(tiers.single.price, 1200);
  });

  test(
      'product_units: rasio satuan yang baru diedit lokal TIDAK tertimpa '
      'balik oleh sync data owner yang tidak terkait', () async {
    final db = await freshDb();
    addTearDown(db.close);

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Gula', locallyModified: const drift.Value(true)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        isBaseUnit: const drift.Value(true),
        ratioToBase: const drift.Value(2.5)));

    // Sync tak terkait bawa product_units LAMA (id SAMA, sengaja — unit id
    // stabil lintas edit, beda dari tier/altprice/barcode yg regenerasi).
    await db.mergeRows('product_units', [
      {
        'id': 'u1',
        'product_id': 'p1',
        'unit_type_id': null,
        'is_base_unit': 1,
        'ratio_to_base': 1.0,
        'is_non_stock': 0,
        'min_stock': null,
      }
    ], false);

    final unit = await (db.select(db.productUnits)
          ..where((t) => t.id.equals('u1')))
        .getSingle();
    expect(unit.ratioToBase, 2.5,
        reason: 'rasio satuan hasil edit lokal asisten harus TETAP utuh — '
            'bukan tertimpa balik ke 1.0 milik owner');
  });

  test(
      'alt_prices: harga alternatif baru TIDAK duplikat dengan baris lama '
      'owner setelah sync data lain', () async {
    final db = await freshDb();
    addTearDown(db.close);

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Gula', locallyModified: const drift.Value(true)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const drift.Value(true)));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'alt-new', productUnitId: 'u1', label: 'Grosir', price: 950));

    await db.mergeRows('alt_prices', [
      {
        'id': 'alt-old',
        'product_unit_id': 'u1',
        'label': 'Grosir',
        'price': 900,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'sort_order': 0,
      }
    ], false);

    final alts = await (db.select(db.altPrices)
          ..where((t) => t.productUnitId.equals('u1')))
        .get();
    expect(alts, hasLength(1),
        reason: 'baris lama owner TIDAK BOLEH ikut masuk selama produk '
            'masih locally_modified — tanpa fix ini nyangkut jadi 2 baris '
            '"Grosir" (satu benar, satu basi)');
    expect(alts.single.id, 'alt-new');
  });

  test(
      'setelah owner APPROVE (locally_modified kembali false), sync '
      'berikutnya boleh menimpa seperti biasa', () async {
    final db = await freshDb();
    addTearDown(db.close);

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Gula', locallyModified: const drift.Value(false)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const drift.Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'tier-old-local', productUnitId: 'u1', price: 1200));

    await db.mergeRows('price_tiers', [
      {
        'id': 'tier-from-host',
        'product_unit_id': 'u1',
        'min_qty': 1,
        'price': 1500,
        'cost_price': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }
    ], false);

    final tiers = await (db.select(db.priceTiers)
          ..where((t) => t.productUnitId.equals('u1')))
        .get();
    expect(tiers, hasLength(1));
    expect(tiers.single.id, 'tier-from-host',
        reason: 'produk yang TIDAK locally_modified harus tetap ikut '
            'last-write behavior biasa (dedup by unit+min_qty)');
    expect(tiers.single.price, 1500);
  });
}
