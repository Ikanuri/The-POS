import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Susulan (permintaan user): "Apakah bisa dan masuk akal jika varian juga
/// diberi opsi Harga Lain?" — bisa, tanpa migrasi (AltPrices sudah di-key
/// per productUnitId, varian sudah punya ProductUnits sendiri). Ditambahkan
/// param altPrices di createVariant/updateVariant, pola identik saveProduct
/// (selalu ganti seluruh baris, bukan menumpuk).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedParent() async {
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    return 'p1';
  }

  test('createVariant menyimpan Harga Lain sekaligus', () async {
    await seedParent();
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 5000,
      costPrice: 3000,
      altPrices: const [
        (label: 'Harga Toko A', price: 4500),
        (label: 'Harga Grosir', price: 4000),
      ],
    );

    final units = await db.getProductUnits(variantId);
    final unit = units.single;
    final alts = await db.getAltPrices(unit.id);
    expect(alts, hasLength(2));
    expect(alts.map((a) => a.label).toSet(),
        {'Harga Toko A', 'Harga Grosir'});
    expect(alts.firstWhere((a) => a.label == 'Harga Toko A').price, 4500);
  });

  test(
      'updateVariant dgn altPrices baru MENGGANTI seluruh baris lama '
      '(bukan menumpuk), sama seperti saveProduct', () async {
    await seedParent();
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 5000,
      costPrice: 3000,
      altPrices: const [(label: 'Harga Lama', price: 4000)],
    );
    final unit = (await db.getProductUnits(variantId)).single;

    await db.updateVariant(
      variantProductId: variantId,
      name: 'Coklat',
      price: 5000,
      altPrices: const [(label: 'Harga Baru', price: 4800)],
    );

    final alts = await db.getAltPrices(unit.id);
    expect(alts, hasLength(1),
        reason: 'baris lama harus terganti, bukan bertambah jadi 2');
    expect(alts.single.label, 'Harga Baru');
    expect(alts.single.price, 4800);
  });

  test(
      'updateVariant dgn altPrices NULL tidak menyentuh Harga Lain yang '
      'sudah ada (form lama tanpa field ini)', () async {
    await seedParent();
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 5000,
      costPrice: 3000,
      altPrices: const [(label: 'Tetap Ada', price: 4000)],
    );
    final unit = (await db.getProductUnits(variantId)).single;

    await db.updateVariant(
      variantProductId: variantId,
      name: 'Coklat Updated',
      price: 5500,
      // altPrices sengaja tidak diisi (null).
    );

    final alts = await db.getAltPrices(unit.id);
    expect(alts, hasLength(1));
    expect(alts.single.label, 'Tetap Ada');
  });

  test('updateVariant dgn altPrices KOSONG (bukan null) menghapus semua',
      () async {
    await seedParent();
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 5000,
      costPrice: 3000,
      altPrices: const [(label: 'Akan Dihapus', price: 4000)],
    );
    final unit = (await db.getProductUnits(variantId)).single;

    await db.updateVariant(
      variantProductId: variantId,
      name: 'Coklat',
      price: 5000,
      altPrices: const [],
    );

    final alts = await db.getAltPrices(unit.id);
    expect(alts, isEmpty);
  });
}
