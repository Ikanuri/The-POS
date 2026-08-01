import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';
import 'package:the_pos/core/utils/input_formatters.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "Harga lain juga, bagaimana cara
/// menggunakannya untuk varian?" — dicek: "Harga Lain" varian sudah bisa
/// disimpan lewat dialog Tambah/Edit Varian, tapi sebelumnya TIDAK PERNAH
/// bisa dipakai saat jual (harga varian di keranjang selalu harga dasar
/// mentah). Fix awal: ikon popup "Pilih harga". Revisi (permintaan user,
/// 1 Agustus): popup diganti field harga BISA DIKETIK MANUAL + chip "Harga
/// dasar"/Harga Lain langsung tampil (persis pola produk utama) — TAPI
/// keduanya cuma muncul saat varian itu qty>0 (sedang dibeli), supaya
/// varian yg banyak tidak bikin layar penuh sesak.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<Product> seedParentWithVariant() async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-coklat', name: 'Coklat', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-coklat', productId: 'v-coklat', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-coklat', productUnitId: 'vu-coklat', price: 5500));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'vap-coklat',
        productUnitId: 'vu-coklat',
        label: 'Toko A',
        price: 4500));

    return (await db.searchProducts('')).firstWhere((p) => p.id == 'p1');
  }

  Finder priceFieldIn(Finder row) => find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.prefixText == 'Rp '));

  Finder rowOf(String variantName) => find.ancestor(
      of: find.text(variantName),
      matching:
          find.byWidgetPredicate((w) => w.runtimeType.toString() == '_VariantRow'));

  testWidgets(
      'varian qty=0: field harga & chip Harga Lain TIDAK tampil sama sekali '
      '(baru muncul begitu qty>0)', (tester) async {
    final product = await seedParentWithVariant();
    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    final row = rowOf('Coklat');
    expect(priceFieldIn(row), findsNothing,
        reason: 'varian belum dibeli (qty 0) -> kontrol harga disembunyikan');
    expect(find.descendant(of: row, matching: find.text('Toko A')),
        findsNothing);
  });

  testWidgets(
      'varian tanpa Harga Lain: field harga tetap muncul saat qty>0, tapi '
      'tanpa chip apa pun', (tester) async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'v-melon', name: 'Melon', parentProductId: const Value('p1')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'vu-melon', productId: 'v-melon', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'vt-melon', productUnitId: 'vu-melon', price: 5500));
    final product = (await db.searchProducts('')).firstWhere((p) => p.id == 'p1');

    await pumpWithFakeApp(tester,
        db: db, child: ItemEntrySheet(product: product));

    final row = rowOf('Melon');
    await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.add_circle_outline)));
    await tester.pumpAndSettle();

    expect(priceFieldIn(row), findsOneWidget,
        reason: 'qty sudah >0, field harga harus muncul');
    expect(find.descendant(of: row, matching: find.text('Harga dasar')),
        findsNothing,
        reason: 'tanpa Harga Lain, tidak perlu chip apa pun (cuma 1 opsi)');
  });

  testWidgets(
      'varian dgn Harga Lain, qty>0: tap chip "Toko A" -> field harga '
      'terisi otomatis, tersimpan ke keranjang sbg harga Harga Lain', (tester) async {
    final product = await seedParentWithVariant();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Dev',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(body: ItemEntrySheet(product: product))),
      ),
    );
    await tester.pumpAndSettle();

    final row = rowOf('Coklat');
    await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.add_circle_outline)));
    await tester.pumpAndSettle();

    final priceField = priceFieldIn(row);
    expect(priceField, findsOneWidget);
    expect(tester.widget<TextField>(priceField).controller!.text,
        ThousandsSeparatorFormatter.format(5500),
        reason: 'awalnya harga dasar varian 5500');

    await tester.tap(find.descendant(of: row, matching: find.text('Toko A')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(priceFieldIn(row)).controller!.text,
        ThousandsSeparatorFormatter.format(4500),
        reason: 'field harga harus ikut terisi Harga Lain yang dipilih');

    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final line = cart.firstWhere((c) => c.productId == 'v-coklat');
    expect(line.price, 4500,
        reason: 'harga tersimpan di keranjang harus Harga Lain, bukan harga '
            'dasar (5500) mentah');
    expect(line.qty, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'field harga diketik manual (bukan chip) -> tersimpan ke keranjang, '
      'override sekali pakai (tidak menyentuh data varian tersimpan)',
      (tester) async {
    final product = await seedParentWithVariant();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Dev',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(body: ItemEntrySheet(product: product))),
      ),
    );
    await tester.pumpAndSettle();

    final row = rowOf('Coklat');
    await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.add_circle_outline)));
    await tester.pumpAndSettle();

    await tester.enterText(priceFieldIn(row), '6000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah ke Keranjang'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final line = cart.firstWhere((c) => c.productId == 'v-coklat');
    expect(line.price, 6000);

    final storedTier = await (db.select(db.priceTiers)
          ..where((t) => (t.productUnitId.equals('vu-coklat') & t.minQty.equals(1))))
        .getSingle();
    expect(storedTier.price, 5500,
        reason: 'harga tersimpan varian TIDAK boleh berubah — ketikan manual '
            'cuma override sekali pakai utk transaksi ini');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
