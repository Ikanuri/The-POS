import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 54 — live-toggle kategori: `setProductGroupMembership` menggantikan
/// `assignProductsToGroup` (Item 52) batch-overwrite yang bertentangan dgn
/// keputusan baru "kategori lama tetap dipertahankan, kategori baru jadi
/// TAMBAHAN". Centang produk yg BELUM punya kategori utama -> kategori itu
/// jadi utama. Centang produk yg SUDAH punya kategori utama LAIN -> kategori
/// baru jadi TAG TAMBAHAN (`product_group_tags`), kategori utama lama
/// TIDAK berubah. Uncentang melepas dari kategori itu SAJA.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(100), name: const Value('Minuman')));
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(200), name: const Value('Snack')));

    Future<void> seed(String id, String name, {int? groupId}) => db.saveProduct(
          product: ProductsCompanion.insert(
            id: id,
            name: name,
            productGroupId: Value(groupId),
          ),
          units: [
            ProductUnitsCompanion.insert(
                id: '${id}_u', productId: id, isBaseUnit: const Value(true)),
          ],
          tiersByUnitTempId: {
            '${id}_u': [
              PriceTiersCompanion.insert(
                  id: '${id}_t', productUnitId: '${id}_u', price: 1000),
            ],
          },
          barcodesByUnitTempId: const {},
          altPricesByUnitTempId: const {},
        );

    await seed('p1', 'Teh Botol'); // tanpa kategori
    await seed('p2', 'Kopi Sachet', groupId: 200); // sudah di kategori lain
    await seed('p3', 'Air Mineral'); // tanpa kategori
  });
  tearDown(() => db.close());

  test('centang produk tanpa kategori -> jadi kategori UTAMA', () async {
    await db.setProductGroupMembership('p1', 100, true);

    final p1 = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(p1.productGroupId, 100);
    expect(await db.getProductGroupTagsFor(['p1']), isEmpty);
  });

  test(
      'centang produk yang SUDAH punya kategori utama lain -> jadi TAG '
      'TAMBAHAN, kategori utama lama TIDAK berubah', () async {
    await db.setProductGroupMembership('p2', 100, true);

    final p2 = await (db.select(db.products)..where((t) => t.id.equals('p2')))
        .getSingle();
    expect(p2.productGroupId, 200, reason: 'kategori utama lama dipertahankan');
    final tags = await db.getProductGroupTagsFor(['p2']);
    expect(tags['p2'], {100});
  });

  test('uncentang kategori UTAMA -> lepas jadi null, updatedAt dicap ulang',
      () async {
    await db.setProductGroupMembership('p2', 200, false);

    final p2 = await (db.select(db.products)..where((t) => t.id.equals('p2')))
        .getSingle();
    expect(p2.productGroupId, isNull);
  });

  test('uncentang TAG TAMBAHAN -> hapus baris product_group_tags saja, '
      'kategori utama tetap', () async {
    await db.setProductGroupMembership('p2', 100, true); // jadi tag
    await db.setProductGroupMembership('p2', 100, false); // lepas tag

    final p2 = await (db.select(db.products)..where((t) => t.id.equals('p2')))
        .getSingle();
    expect(p2.productGroupId, 200, reason: 'kategori utama tak tersentuh');
    expect(await db.getProductGroupTagsFor(['p2']), isEmpty);
  });

  test('produk lain yang tidak disentuh tidak ikut berubah', () async {
    await db.setProductGroupMembership('p1', 100, true);

    final p3 = await (db.select(db.products)..where((t) => t.id.equals('p3')))
        .getSingle();
    expect(p3.productGroupId, isNull);
  });

  test('updated_at dicap ulang ke SAAT INI saat set kategori utama '
      '(supaya ikut tersinkron ke klien lain)', () async {
    final before = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    final oldUpdatedAt = before.updatedAt;

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await db.setProductGroupMembership('p1', 100, true);

    final after = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(after.updatedAt.isAfter(oldUpdatedAt), isTrue);

    final sinceAfterOldEdit =
        DateTime.now().subtract(const Duration(seconds: 1, milliseconds: 500));
    final dump = await db.dumpSince(sinceAfterOldEdit);
    expect(dump['products']!.any((r) => r['id'] == 'p1'), isTrue);
  });

  test('countProductsInGroup dihitung dari UNION kategori utama + tag',
      () async {
    await db.setProductGroupMembership('p1', 100, true); // utama
    await db.setProductGroupMembership('p2', 100, true); // tag (utama=200)

    expect(await db.countProductsInGroup(100), 2);
  });

  test(
      'deleteProductGroup (Item 53) mencap ulang updated_at & membersihkan '
      'product_group_tags milik kategori yang dihapus', () async {
    await db.setProductGroupMembership('p1', 100, true); // utama
    await db.setProductGroupMembership('p2', 100, true); // tag

    final before = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    final oldUpdatedAt = before.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    await db.deleteProductGroup(100);

    final p1 = await (db.select(db.products)..where((t) => t.id.equals('p1')))
        .getSingle();
    expect(p1.productGroupId, isNull);
    expect(p1.updatedAt.isAfter(oldUpdatedAt), isTrue,
        reason: 'Item 53 — updated_at wajib dicap ulang saat kategori dihapus');

    expect(await db.getProductGroupTagsFor(['p2']), isEmpty,
        reason: 'tag milik kategori yg dihapus wajib ikut dibersihkan, '
            'supaya tidak "hidup lagi" kalau id kategori dipakai ulang');
  });
}
