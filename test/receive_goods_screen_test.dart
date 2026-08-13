import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/receive_goods_screen.dart';

import 'helpers/pump_app.dart';

/// Alur Penerimaan Barang di layar: tempel teks -> proses -> baris yang
/// cocok ditandai, yang tidak cocok bisa dipilih manual lewat dropdown
/// berpencarian -> commit MENAMBAH stok & mengingat pilihan ke kamus.
Future<AppDatabase> _seed() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.into(db.products).insert(
      ProductsCompanion.insert(id: 'p1', name: 'Indomie Goreng'));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        isBaseUnit: const Value(true),
      ));
  await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
        id: 'sl0',
        productUnitId: 'u1',
        type: 'opening',
        qtyChange: 10,
        stockAfter: 10,
        createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
      ));
  return db;
}

Future<double> _stock(AppDatabase db, String uid) async {
  final rows = await db.customSelect(
    'SELECT stock_after FROM stock_ledger WHERE product_unit_id = ? '
    'ORDER BY created_at DESC, rowid DESC LIMIT 1',
    variables: [Variable.withString(uid)],
  ).get();
  return rows.isEmpty ? 0 : (rows.first.data['stock_after'] as num).toDouble();
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('tempel teks -> baris cocok otomatis -> commit MENAMBAH stok',
      (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(tester, db: db, child: const ReceiveGoodsScreen());
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).first, '── Hari ini ──\n4 pcs Indomie Goreng');
    await tester.tap(find.text('Proses Daftar'));
    await tester.pumpAndSettle();

    expect(find.text('Hasil (1 baris)'), findsOneWidget,
        reason: 'header tanggal harus diabaikan, bukan dihitung sbg baris');
    expect(find.textContaining('Indomie Goreng'), findsWidgets);

    await tester.tap(find.text('Tambahkan 1 Barang ke Stok'));
    await tester.pumpAndSettle();

    expect(await _stock(db, 'u1'), 14,
        reason: 'stok awal 10 + 4 diterima = 14 (menambah, bukan menimpa)');

    await _drain(tester);
    await db.close();
  });

  testWidgets(
      'baris tidak dikenali -> tandai perlu dipilih, tombol commit '
      'menghitung hanya yang siap', (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(tester, db: db, child: const ReceiveGoodsScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first,
        '4 pcs Indomie Goreng\n2 dus Barang Antah Berantah');
    await tester.tap(find.text('Proses Daftar'));
    await tester.pumpAndSettle();

    expect(find.text('Hasil (2 baris)'), findsOneWidget);
    expect(find.text('Tidak ketemu — pilih produknya'), findsOneWidget);
    expect(find.text('Tambahkan 1 Barang ke Stok'), findsOneWidget,
        reason: 'cuma 1 baris yang siap; yang belum dipilih tidak ikut');

    await _drain(tester);
    await db.close();
  });

  testWidgets(
      'pilih produk manual lewat dropdown berpencarian -> tersimpan ke '
      'kamus, teks sama langsung cocok di kemudian hari', (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(tester, db: db, child: const ReceiveGoodsScreen());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '3 pcs Indomie Grg');
    await tester.tap(find.text('Proses Daftar'));
    await tester.pumpAndSettle();
    expect(find.text('Tidak ketemu — pilih produknya'), findsOneWidget);

    // Buka dropdown, cari, pilih.
    await tester.tap(find.text('Indomie Grg'));
    await tester.pumpAndSettle();
    expect(find.text('Cari produk'), findsOneWidget,
        reason: 'permintaan user: ada opsi search di dalam modal dropdown');

    await tester.enterText(find.widgetWithText(TextField, 'Cari produk'),
        'Indomie');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Indomie Goreng').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tambahkan 1 Barang ke Stok'));
    await tester.pumpAndSettle();

    expect(await _stock(db, 'u1'), 13);
    expect(await db.resolveReceiveUnit(name: 'Indomie Grg', unit: 'pcs'), 'u1',
        reason: 'pilihan manual WAJIB diingat supaya tidak ditanya lagi');

    await _drain(tester);
    await db.close();
  });

  testWidgets('layar Kamus Produk menampilkan & bisa menghapus entri',
      (tester) async {
    final db = await _seed();
    await db.learnReceiveAlias(
        name: 'Indomie Grg', unit: 'pcs', productUnitId: 'u1');

    await pumpWithFakeApp(tester, db: db, child: const ReceiveAliasScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('indomie grg'), findsWidgets);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    final left = await db.getReceiveAliases();
    expect(left.length, 1, reason: '1 dari 2 kunci terhapus');

    await _drain(tester);
    await db.close();
  });
}
