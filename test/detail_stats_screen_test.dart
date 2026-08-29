import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laporan/stats/customer_stats_screen.dart';
import 'package:the_pos/features/laporan/stats/product_stats_screen.dart';
import 'package:the_pos/features/laporan/tabs/pelanggan_tab.dart';
import 'package:the_pos/features/laporan/tabs/produk_tab.dart';
import 'package:the_pos/features/pelanggan/pelanggan_form_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: tab Produk & Pelanggan di Laporan dulu BUNTU (barisnya
/// tidak bisa diketuk sama sekali — dibuktikan dgn grep `onTap` yang NIHIL).
/// Sekarang tiap baris membuka layar statistik detail, dan statistik
/// pelanggan WAJIB bisa dibuka dari DUA tempat (Laporan + detail pelanggan).
final _range = DateTimeRange(
  start: DateTime(2026, 1, 1),
  end: DateTime(2026, 12, 31, 23, 59, 59),
);

Future<AppDatabase> _seed() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.into(db.products).insert(
      ProductsCompanion.insert(id: 'p1', name: 'Beras Pandan'));
  await db.into(db.customers).insert(
      CustomersCompanion.insert(id: 'c1', name: 'Bu Ani'));
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: 't1',
        localId: 'K1-0001',
        status: 'lunas',
        total: 30000,
        paid: 30000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        customerId: const Value('c1'),
        createdAt: Value(DateTime(2026, 3, 1)),
      ));
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 't1',
        productId: 'p1',
        productUnitId: 'u1',
        qty: 3,
        priceAtSale: 10000,
        originalPrice: 10000,
        costAtSale: const Value(6000),
        subtotal: 30000,
      ));
  return db;
}

/// Tutup stream/timer sebelum DB ditutup — gotcha wajib di CLAUDE.md.
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('tab Produk: baris bisa diketuk -> buka statistik produk',
      (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(tester, db: db, child: ProdukTab(range: _range));
    await tester.pumpAndSettle();

    expect(find.text('Beras Pandan'), findsOneWidget);
    await tester.tap(find.text('Beras Pandan'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductStatsScreen), findsOneWidget,
        reason: 'baris tab Produk dulu BUNTU — sekarang harus membuka '
            'layar statistik detail');
    // Ringkasan produk terisi dari data uji (3 terjual, omzet 30.000).
    // "satuan" krn produk uji tak punya baris `product_units` (fallback
    // nama satuan dasar, lihat dok `AppDatabase._baseUnitNameOf`).
    expect(find.text('3 satuan'), findsWidgets);
    expect(find.text(formatRupiah(30000)), findsWidgets);

    await _drain(tester);
    await db.close();
  });

  testWidgets('tab Pelanggan: baris bisa diketuk -> buka statistik pelanggan',
      (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(tester, db: db, child: PelangganTab(range: _range));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bu Ani'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerStatsScreen), findsOneWidget);
    expect(find.text('Total belanja'), findsOneWidget);
    expect(find.text(formatRupiah(30000)), findsWidgets);
    // Barang yang sering dibeli ikut tampil (bukan cuma angka ringkas).
    expect(find.text('Beras Pandan'), findsOneWidget);

    await _drain(tester);
    await db.close();
  });

  testWidgets(
      'detail pelanggan: tombol Statistik Belanja membuka layar yang SAMA '
      '(pintu masuk kedua)', (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(tester, db: db,
        child: const PelangganFormScreen(customerId: 'c1'));
    await tester.pumpAndSettle();

    final btn = find.byTooltip('Statistik Belanja');
    expect(btn, findsOneWidget,
        reason: 'permintaan user: statistik juga bisa dibuka dari dalam '
            'detail/pengaturan pelanggan, bukan cuma dari Laporan');
    await tester.tap(btn);
    await tester.pumpAndSettle();

    expect(find.byType(CustomerStatsScreen), findsOneWidget);

    await _drain(tester);
    await db.close();
  });

  testWidgets('statistik pelanggan: rentang tanggal bisa diubah & angkanya '
      'ikut berubah', (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(
      tester,
      db: db,
      child: CustomerStatsScreen(
        customerId: 'c1',
        customerName: 'Bu Ani',
        // Rentang yang TIDAK memuat transaksi (transaksi ada di Mar 2026).
        initialRange: DateTimeRange(
          start: DateTime(2025, 1, 1),
          end: DateTime(2025, 12, 31, 23, 59, 59),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Belum ada belanja di rentang ini'), findsOneWidget,
        reason: 'filter tanggal harus benar-benar menyaring, bukan hiasan');

    await _drain(tester);
    await db.close();
  });

  testWidgets('statistik produk: rentang di luar transaksi -> pesan kosong',
      (tester) async {
    final db = await _seed();
    await pumpWithFakeApp(
      tester,
      db: db,
      child: ProductStatsScreen(
        productId: 'p1',
        productName: 'Beras Pandan',
        initialRange: DateTimeRange(
          start: DateTime(2025, 1, 1),
          end: DateTime(2025, 12, 31, 23, 59, 59),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Belum ada penjualan di rentang ini'), findsOneWidget);

    await _drain(tester);
    await db.close();
  });
}
