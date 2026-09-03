import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 59 — pre-order sebelumnya TIDAK PERNAH memotong stok sistem di
/// seluruh siklus hidupnya: `payment_screen.dart` sengaja kecualikan item
/// pre-order dari `stockItems` saat checkout (benar, barangnya belum ada),
/// tapi tidak satu pun jalur lanjutan (`collectPreorderDeposit`,
/// `fulfillPreorderQty`/`fulfillPreorderEntry`) pernah memanggil
/// `_appendStock`. Keputusan: stok dipotong SAAT barang benar² diserahkan
/// (fulfill), bukan saat DP dibayar.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedProduct({double initialStock = 0}) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Galon Aqua'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1', productId: 'p1', isBaseUnit: const Value(true)));
    if (initialStock != 0) {
      await db.adjustStock(
          productUnitId: 'u1', newQty: initialStock, note: 'seed');
    }
  }

  test(
      'fulfillPreorderQty (penuhi sekaligus, qtyOrdered penuh) memotong stok '
      'PERSIS sejumlah qty & menulis baris stock_ledger', () async {
    await seedProduct();
    await db.adjustStock(productUnitId: 'u1', newQty: 0, note: 'seed');
    // Skenario asli: stok 0 -> restock 20 -> pre-order 5 dipenuhi -> 15.
    await db.adjustStock(productUnitId: 'u1', newQty: 20, note: 'restock');

    await db.addPreorderEntry(
        id: 'po1',
        productId: 'p1',
        productUnitId: 'u1',
        customerName: 'Umum',
        qtyOrdered: 5);

    await db.fulfillPreorderQty('po1', 5, deviceCode: 'K1');

    final stock = await db.currentStock('u1');
    expect(stock, 15,
        reason:
            'stok sistem harus terpotong 5 (20 - 5), bukan tetap 20 spt bug '
            'lama');

    final ledgerRows = await (db.select(db.stockLedger)
          ..where((t) => t.type.equals('preorder_fulfill')))
        .get();
    expect(ledgerRows, hasLength(1));
    expect(ledgerRows.single.qtyChange, -5);
    expect(ledgerRows.single.referenceId, 'po1');

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(entry.fulfilledAt, isNotNull);
  });

  test(
      'fulfillPreorderEntry (penuhi SELURUH sisa sekaligus) memotong stok '
      'PERSIS sejumlah qtyOrdered', () async {
    await seedProduct();
    await db.adjustStock(productUnitId: 'u1', newQty: 20, note: 'restock');

    await db.addPreorderEntry(
        id: 'po2',
        productId: 'p1',
        productUnitId: 'u1',
        customerName: 'Umum',
        qtyOrdered: 5);

    await db.fulfillPreorderEntry('po2', deviceCode: 'K1');

    final stock = await db.currentStock('u1');
    expect(stock, 15);

    final ledgerRows = await (db.select(db.stockLedger)
          ..where((t) => t.type.equals('preorder_fulfill')))
        .get();
    expect(ledgerRows, hasLength(1));
    expect(ledgerRows.single.qtyChange, -5);
  });

  test(
      'pemenuhan SEBAGIAN 2x berturut (fulfillPreorderQty(2) lalu (3)) '
      'total terpotong PERSIS 5, tidak dobel-hitung', () async {
    await seedProduct();
    await db.adjustStock(productUnitId: 'u1', newQty: 20, note: 'restock');

    await db.addPreorderEntry(
        id: 'po3',
        productId: 'p1',
        productUnitId: 'u1',
        customerName: 'Umum',
        qtyOrdered: 5);

    await db.fulfillPreorderQty('po3', 2, deviceCode: 'K1');
    var stock = await db.currentStock('u1');
    expect(stock, 18, reason: 'baru dipotong 2 dari pemenuhan pertama');

    var entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po3')))
        .getSingle();
    expect(entry.fulfilledAt, isNull,
        reason: 'belum lunas (2 dari 5), belum boleh fulfilledAt');

    await db.fulfillPreorderQty('po3', 3, deviceCode: 'K1');
    stock = await db.currentStock('u1');
    expect(stock, 15,
        reason: 'total terpotong PERSIS 5 (2+3), bukan 10 — tidak boleh '
            'dobel-hitung');

    entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po3')))
        .getSingle();
    expect(entry.fulfilledAt, isNotNull,
        reason: 'sudah 5 dari 5, sekarang lunas');

    final ledgerRows = await (db.select(db.stockLedger)
          ..where((t) => t.type.equals('preorder_fulfill')))
        .get();
    expect(ledgerRows, hasLength(2),
        reason: 'dua baris ledger terpisah, satu per pemenuhan');
  });

  test(
      'fulfillPreorderEntry SETELAH pemenuhan sebagian hanya memotong SISA '
      '(tidak dobel-potong qty yang sudah terambil via fulfillPreorderQty)',
      () async {
    await seedProduct();
    await db.adjustStock(productUnitId: 'u1', newQty: 20, note: 'restock');

    await db.addPreorderEntry(
        id: 'po4',
        productId: 'p1',
        productUnitId: 'u1',
        customerName: 'Umum',
        qtyOrdered: 5);

    await db.fulfillPreorderQty('po4', 2, deviceCode: 'K1');
    await db.fulfillPreorderEntry('po4', deviceCode: 'K1');

    final stock = await db.currentStock('u1');
    expect(stock, 15,
        reason: 'total terpotong 5 (2 via fulfillPreorderQty + 3 sisa via '
            'fulfillPreorderEntry), bukan 2+5=7');

    final ledgerRows = await (db.select(db.stockLedger)
          ..where((t) => t.type.equals('preorder_fulfill')))
        .get();
    final total =
        ledgerRows.fold<double>(0, (sum, r) => sum + r.qtyChange.abs());
    expect(total, 5);
  });
}
