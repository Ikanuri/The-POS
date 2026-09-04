import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/services/order_parser_service.dart';

/// Fitur "Pra-Bayar" — `encodeHandoff`/`parse` membawa entri Pra-Bayar dari
/// keranjang PENGIRIM sbg baris meta `Prabayar:` baru (data MENTAH, keputusan
/// adopsi ada di pemanggil yang tahu status gerbang izin PENERIMA — lihat dok
/// `ParsedOrder.prabayar`). `OrderParserService` sendiri sengaja TIDAK tahu
/// apa-apa soal gerbang izin (layering core/services tidak boleh bergantung
/// ke Riverpod) — test ini HANYA membuktikan data mentahnya terbawa utuh;
/// keputusan buang/adopsi ada di `kasir_handoff_qr_test.dart`/
/// `paste_order_sheet` (widget test terpisah).
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

  test('entri Pra-Bayar terbawa utuh (amount/method/methodName/lockedAtMs)',
      () async {
    final db = await seedDb();
    addTearDown(db.close);

    final text = OrderParserService.encodeHandoff(
      items: [item],
      employeeName: 'Kasir A',
      prabayar: [
        (amount: 30000, method: 'tunai', methodName: null, lockedAtMs: 1000),
        (amount: 20000, method: 'qris', methodName: 'QRIS Toko', lockedAtMs: 2000),
      ],
    );

    final parsed = await OrderParserService.parse(db: db, text: text);

    expect(parsed.prabayar, hasLength(2));
    expect(parsed.prabayar[0].amount, 30000);
    expect(parsed.prabayar[0].method, 'tunai');
    expect(parsed.prabayar[0].methodName, isNull);
    expect(parsed.prabayar[0].lockedAtMs, 1000);
    expect(parsed.prabayar[1].amount, 20000);
    expect(parsed.prabayar[1].method, 'qris');
    expect(parsed.prabayar[1].methodName, 'QRIS Toko');
    expect(parsed.prabayar[1].lockedAtMs, 2000);
  });

  test('tanpa Pra-Bayar (kode lama/tanpa entri) → list kosong, item barang '
      'tetap masuk normal', () async {
    final db = await seedDb();
    addTearDown(db.close);

    final text = OrderParserService.encodeHandoff(
      items: [item],
      employeeName: 'Kasir A',
    );

    final parsed = await OrderParserService.parse(db: db, text: text);

    expect(parsed.prabayar, isEmpty);
    expect(parsed.items, hasLength(1));
  });

  test('baris Prabayar rusak (JSON tidak valid) diabaikan dengan aman — '
      'TIDAK menggagalkan parsing barang', () async {
    final db = await seedDb();
    addTearDown(db.close);

    final text = OrderParserService.encodeHandoff(
      items: [item],
      employeeName: 'Kasir A',
    );
    final corrupted = '$text\nPrabayar: {bukan json valid';

    final parsed = await OrderParserService.parse(db: db, text: corrupted);

    expect(parsed.prabayar, isEmpty);
    expect(parsed.items, hasLength(1),
        reason: 'barang tetap masuk walau baris Prabayar rusak');
  });
}
