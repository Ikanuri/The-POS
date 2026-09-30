import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/stock_display.dart';
import 'package:the_pos/features/kasir/widgets/item_entry_sheet.dart';

import 'helpers/pump_app.dart';

/// Usulan user (sesi 83) — kartu tap item kasir menampilkan stok SEMUA
/// satuan ("1.250 biji / 125 slop / 12,5 dus") + ikon peringatan stok
/// (kuning menipis, merah habis).
void main() {
  group('formatStockQty', () {
    test('ribuan titik, desimal koma, nol di belakang koma dibuang', () {
      expect(formatStockQty(1250), '1.250');
      expect(formatStockQty(12.5), '12,5');
      expect(formatStockQty(0.083333), '0,08');
      expect(formatStockQty(1234567), '1.234.567');
      expect(formatStockQty(0), '0');
      expect(formatStockQty(-3), '-3');
      expect(formatStockQty(2.0000001), '2');
    });
  });

  group('formatMultiUnitStock', () {
    const units = <StockUnit>[
      (name: 'dus', ratioToBase: 100),
      (name: 'biji', ratioToBase: 1),
      (name: 'slop', ratioToBase: 10),
    ];
    test('urut kecil -> besar, setara per satuan', () {
      expect(formatMultiUnitStock(1250, units),
          '1.250 biji / 125 slop / 12,5 dus');
    });
    test('stok nol & rasio tidak valid dilewati', () {
      expect(formatMultiUnitStock(0, units), '0 biji / 0 slop / 0 dus');
      expect(
          formatMultiUnitStock(5, const [
            (name: 'biji', ratioToBase: 1),
            (name: 'rusak', ratioToBase: 0),
          ]),
          '5 biji');
    });
  });

  group('stockLevel', () {
    test('habis: <= 0 atau ditandai manual', () {
      expect(stockLevel(baseStock: 0), StockLevel.out);
      expect(stockLevel(baseStock: -2, minStock: 5), StockLevel.out);
      expect(stockLevel(baseStock: 50, markedOutOfStock: true), StockLevel.out);
    });
    test('menipis: <= minStock; ok bila di atas / tidak dipantau', () {
      expect(stockLevel(baseStock: 5, minStock: 5), StockLevel.low);
      expect(stockLevel(baseStock: 6, minStock: 5), StockLevel.ok);
      expect(stockLevel(baseStock: 3), StockLevel.ok);
    });
  });

  group('kartu item kasir', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    Future<Product> seed({required double stock, int? minStock}) async {
      await db
          .into(db.products)
          .insert(ProductsCompanion.insert(id: 'p1', name: 'Rokok'));
      // unit_types: 1=default; pakai nama dari seed bawaan.
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          unitTypeId: const Value(1),
          isBaseUnit: const Value(true),
          minStock: Value(minStock)));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u2',
          productId: 'p1',
          unitTypeId: const Value(2),
          ratioToBase: const Value(10)));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1', productUnitId: 'u1', price: 1000));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't2', productUnitId: 'u2', price: 10000));
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'sl1',
          productUnitId: 'u1',
          type: 'opening',
          qtyChange: stock,
          stockAfter: stock));
      return (await db.searchProducts('')).firstWhere((p) => p.id == 'p1');
    }

    Future<String> stockText(WidgetTester tester) async {
      final t = find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().startsWith('Stok '));
      return tester.widget<RichText>(t.first).text.toPlainText();
    }

    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('semua satuan tampil; tanpa peringatan bila stok aman',
        (tester) async {
      final product = await seed(stock: 1250, minStock: 100);
      await pumpWithFakeApp(tester,
          db: db, child: ItemEntrySheet(product: product));
      final txt = await stockText(tester);
      expect(txt, contains(' / '), reason: 'sebelumnya hanya satu satuan');
      expect(txt, contains('1.250 '));
      expect(txt, contains('125 '));
      expect(find.byKey(const ValueKey('stock-alert-low')), findsNothing);
      expect(find.byKey(const ValueKey('stock-alert-out')), findsNothing);
      await drain(tester);
    });

    testWidgets('kuning bila stok <= minimum', (tester) async {
      final product = await seed(stock: 80, minStock: 100);
      await pumpWithFakeApp(tester,
          db: db, child: ItemEntrySheet(product: product));
      expect(find.byKey(const ValueKey('stock-alert-low')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-alert-out')), findsNothing);
      await drain(tester);
    });

    testWidgets('merah bila stok habis', (tester) async {
      final product = await seed(stock: 0, minStock: 100);
      await pumpWithFakeApp(tester,
          db: db, child: ItemEntrySheet(product: product));
      expect(find.byKey(const ValueKey('stock-alert-out')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-alert-low')), findsNothing);
      await drain(tester);
    });
  });
}
