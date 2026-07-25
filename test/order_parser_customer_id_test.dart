import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/services/order_parser_service.dart';

/// Item 4/57 — `encodeHandoff` membawa `PelangganId:`/`Nota:` (id pelanggan
/// non-umum & nomor nota yang sudah direservasi pengirim), `parse` di sisi
/// penerima meng-auto-resolve `customerId` HANYA kalau baris itu benar-benar
/// tersync lokal (kalau tidak, fallback diam-diam ke `customerName` polos —
/// bukan error), dan meneruskan `reservedLocalId` apa adanya.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 2,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
  );

  Future<AppDatabase> seedDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Gula Pasir'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 15000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    return db;
  }

  test('customerId tersync lokal di penerima → ikut ter-resolve di ParsedOrder',
      () async {
    final db = await seedDb();
    addTearDown(db.close);
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'cust-1', name: 'Budi'));

    final text = OrderParserService.encodeHandoff(
      items: [item],
      employeeName: 'Kasir A',
      customerName: 'Budi',
      customerId: 'cust-1',
      reservedLocalId: 'K1-20260723-0017',
    );

    final parsed = await OrderParserService.parse(db: db, text: text);

    expect(parsed.customerId, 'cust-1');
    expect(parsed.customerName, 'Budi');
    expect(parsed.reservedLocalId, 'K1-20260723-0017');
  });

  test(
      'customerId TIDAK tersync di penerima (beda toko/belum sync) → '
      'fallback diam-diam ke nama saja, BUKAN error', () async {
    final db = await seedDb();
    addTearDown(db.close);
    // Sengaja TIDAK insert customer 'cust-1' — simulasikan device penerima
    // yang belum pernah sync pelanggan ini.

    final text = OrderParserService.encodeHandoff(
      items: [item],
      employeeName: 'Kasir A',
      customerName: 'Budi',
      customerId: 'cust-1',
    );

    final parsed = await OrderParserService.parse(db: db, text: text);

    expect(parsed.customerId, isNull,
        reason: 'id yang tak ditemukan lokal tidak boleh dipaksakan');
    expect(parsed.customerName, 'Budi',
        reason: 'nama tetap terbawa walau id tak ter-resolve');
  });

  test('tanpa customerId/reservedLocalId (kode lama) → keduanya null',
      () async {
    final db = await seedDb();
    addTearDown(db.close);

    final text = OrderParserService.encodeHandoff(
      items: [item],
      employeeName: 'Kasir A',
    );

    final parsed = await OrderParserService.parse(db: db, text: text);

    expect(parsed.customerId, isNull);
    expect(parsed.reservedLocalId, isNull);
  });
}
