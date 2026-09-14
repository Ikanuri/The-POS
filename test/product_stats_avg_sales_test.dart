import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laporan/stats/product_stats_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: tambahkan rata-rata penjualan produk per rentang
/// (harian/mingguan/bulanan) di halaman detail produk (`ProductStatsScreen`,
/// dibuka dari tab Produk di Laporan).
///
/// Rata-rata dihitung dari TOTAL qty terjual / jumlah HARI dalam rentang
/// (inclusive, bukan cuma hari yang ADA penjualannya) — supaya hari kosong
/// ikut menurunkan angka, mencerminkan kecepatan jual sungguhan. Mingguan =
/// harian × 7, bulanan = harian × 30 (pendekatan, bukan kalender sungguhan).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  /// Rentang persis 10 hari (1-10 Jan 2026 inclusive), total qty terjual 20
  /// (2 transaksi @10 qty) -> rata-rata harian = 20/10 = 2.0 (bilangan
  /// bulat, gampang diverifikasi tanpa pembulatan mengganggu).
  final range = DateTimeRange(
    start: DateTime(2026, 1, 1),
    end: DateTime(2026, 1, 10, 23, 59, 59, 999),
  );

  Future<void> seed() async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Beras Pandan'));
    for (final t in [('t1', 2026, 1, 2), ('t2', 2026, 1, 8)]) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: t.$1,
            localId: 'K1-${t.$1}',
            status: 'lunas',
            total: 100000,
            paid: 100000,
            changeAmount: 0,
            paymentMethod: 'tunai',
            createdAt: Value(DateTime(t.$2, t.$3, t.$4)),
          ));
      await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
            id: '${t.$1}_i',
            transactionId: t.$1,
            productId: 'p1',
            productUnitId: 'u1',
            qty: 10,
            priceAtSale: 10000,
            originalPrice: 10000,
            subtotal: 100000,
          ));
    }
  }

  testWidgets(
      'halaman detail produk menampilkan rata-rata penjualan harian/'
      'mingguan/bulanan', (tester) async {
    await seed();
    await pumpWithFakeApp(
      tester,
      db: db,
      child: ProductStatsScreen(
        productId: 'p1',
        productName: 'Beras Pandan',
        initialRange: range,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rata-rata penjualan'), findsOneWidget);
    expect(find.text('Per hari'), findsOneWidget);
    expect(find.text('Per minggu'), findsOneWidget);
    expect(find.text('Per bulan'), findsOneWidget);

    // 20 qty / 10 hari = 2/hari, 14/minggu, 60/bulan.
    expect(find.text('2 satuan'), findsOneWidget);
    expect(find.text('14 satuan'), findsOneWidget);
    expect(find.text('60 satuan'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('rata-rata pecahan dibulatkan 1 desimal, bukan angka panjang',
      (tester) async {
    // 1 hari, qty 3 -> harian 3.0, mingguan 21.0, bulanan 90.0 (masih
    // bulat). Ganti qty jadi 1 (1 tx) dgn rentang 3 hari -> 1/3 = 0.333... .
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p2', name: 'Telur'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 't3',
          localId: 'K1-t3',
          status: 'lunas',
          total: 3000,
          paid: 3000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(DateTime(2026, 1, 1)),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 't3_i',
          transactionId: 't3',
          productId: 'p2',
          productUnitId: 'u2',
          qty: 1,
          priceAtSale: 3000,
          originalPrice: 3000,
          subtotal: 3000,
        ));

    await pumpWithFakeApp(
      tester,
      db: db,
      child: ProductStatsScreen(
        productId: 'p2',
        productName: 'Telur',
        initialRange: DateTimeRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 3, 23, 59, 59, 999),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1/3 hari = 0.333... -> dibulatkan 1 desimal jadi 0.3, BUKAN
    // "0.3333333333333333" (bug kalau lupa dibulatkan).
    expect(find.text('0.3 satuan'), findsOneWidget);

    await drain(tester);
  });
}
