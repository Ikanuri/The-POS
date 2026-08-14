import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Statistik detail per produk & per pelanggan (permintaan user) — tab
/// Produk/Pelanggan di Laporan dulu BUNTU (barisnya tidak bisa diketuk).
/// Query di sini yang menyuplai layar detailnya.
///
/// Keputusan user yang ikut diuji: pelanggan UMUM/AD-HOC (nota tanpa
/// `customer_id`) DIABAIKAN dari statistik pelanggan.
late AppDatabase db;

final _from = DateTime(2026, 1, 1);
final _to = DateTime(2026, 12, 31, 23, 59, 59);

Future<void> _product(String id, String name) async {
  await db.into(db.products).insert(ProductsCompanion.insert(id: id, name: name));
}

Future<void> _customer(String id, String name) async {
  await db.into(db.customers).insert(CustomersCompanion.insert(id: id, name: name));
}

Future<void> _tx(
  String id, {
  String? customerId,
  String? customerName,
  required int total,
  required DateTime at,
  String status = 'lunas',
}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: 'K1-$id',
        status: status,
        total: total,
        paid: total,
        changeAmount: 0,
        paymentMethod: 'tunai',
        customerId: Value(customerId),
        customerName: Value(customerName),
        createdAt: Value(at),
      ));
}

Future<void> _item(
  String id, {
  required String txId,
  required String productId,
  required double qty,
  required int price,
  int cost = 0,
}) async {
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: id,
        transactionId: txId,
        productId: productId,
        productUnitId: 'u-$productId',
        qty: qty,
        priceAtSale: price,
        originalPrice: price,
        costAtSale: Value(cost),
        subtotal: (price * qty).round(),
      ));
}

void main() {
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('Statistik produk', () {
    test('ringkasan: qty/omzet/HPP + jumlah NOTA (bukan jumlah baris)',
        () async {
      await _product('p1', 'Beras');
      // Nota 1 memuat produk p1 DUA baris (satuan beda) — txCount harus 1.
      await _tx('t1', total: 30000, at: DateTime(2026, 3, 1));
      await _item('i1', txId: 't1', productId: 'p1', qty: 2, price: 10000, cost: 6000);
      await _item('i2', txId: 't1', productId: 'p1', qty: 1, price: 10000, cost: 6000);
      await _tx('t2', total: 20000, at: DateTime(2026, 3, 5));
      await _item('i3', txId: 't2', productId: 'p1', qty: 2, price: 10000, cost: 6000);

      final s = await db.getProductStatsSummary('p1', _from, _to);
      expect(s.qtySold, 5);
      expect(s.revenue, 50000);
      expect(s.cogs, 30000);
      expect(s.txCount, 2,
          reason: '2 NOTA, walau ada 3 baris item — satu nota bisa memuat '
              'produk sama beberapa kali dgn satuan berbeda');
    });

    test('nota void TIDAK dihitung', () async {
      await _product('p1', 'Beras');
      await _tx('t1', total: 10000, at: DateTime(2026, 3, 1));
      await _item('i1', txId: 't1', productId: 'p1', qty: 1, price: 10000);
      await _tx('t2', total: 10000, at: DateTime(2026, 3, 2), status: 'void');
      await _item('i2', txId: 't2', productId: 'p1', qty: 5, price: 10000);

      final s = await db.getProductStatsSummary('p1', _from, _to);
      expect(s.qtySold, 1);
      expect(s.txCount, 1);
    });

    test('di luar rentang tanggal TIDAK dihitung', () async {
      await _product('p1', 'Beras');
      await _tx('t1', total: 10000, at: DateTime(2025, 12, 31));
      await _item('i1', txId: 't1', productId: 'p1', qty: 9, price: 10000);

      final s = await db.getProductStatsSummary('p1', _from, _to);
      expect(s.qtySold, 0);
      expect(s.txCount, 0);
    });

    test('tren harian dikelompokkan per tanggal lokal & terurut', () async {
      await _product('p1', 'Beras');
      await _tx('t1', total: 10000, at: DateTime(2026, 3, 5, 8));
      await _item('i1', txId: 't1', productId: 'p1', qty: 1, price: 10000);
      await _tx('t2', total: 20000, at: DateTime(2026, 3, 5, 17));
      await _item('i2', txId: 't2', productId: 'p1', qty: 2, price: 10000);
      await _tx('t3', total: 10000, at: DateTime(2026, 3, 2, 10));
      await _item('i3', txId: 't3', productId: 'p1', qty: 1, price: 10000);

      final daily = await db.getProductDailySales('p1', _from, _to);
      expect(daily, hasLength(2));
      expect(daily.first.date, DateTime(2026, 3, 2));
      expect(daily.last.date, DateTime(2026, 3, 5));
      expect(daily.last.qty, 3, reason: '2 nota di hari yang sama digabung');
      expect(daily.last.revenue, 30000);
    });

    test('pembeli teratas HANYA pelanggan terdaftar (ad-hoc diabaikan)',
        () async {
      await _product('p1', 'Beras');
      await _customer('c1', 'Bu Ani');
      await _tx('t1', customerId: 'c1', total: 30000, at: DateTime(2026, 3, 1));
      await _item('i1', txId: 't1', productId: 'p1', qty: 3, price: 10000);
      // Pembeli ad-hoc (nama bebas, tanpa customerId) — harus DILEWATI.
      await _tx('t2',
          customerName: 'Umum', total: 90000, at: DateTime(2026, 3, 2));
      await _item('i2', txId: 't2', productId: 'p1', qty: 9, price: 10000);

      final buyers = await db.getProductTopBuyers('p1', _from, _to);
      expect(buyers, hasLength(1));
      expect(buyers.single.name, 'Bu Ani');
      expect(buyers.single.qty, 3);
    });
  });

  group('Statistik pelanggan', () {
    test('ringkasan: total belanja, jumlah nota, qty item, rata-rata/nota',
        () async {
      await _product('p1', 'Beras');
      await _customer('c1', 'Bu Ani');
      await _tx('t1', customerId: 'c1', total: 30000, at: DateTime(2026, 3, 1));
      await _item('i1', txId: 't1', productId: 'p1', qty: 3, price: 10000);
      await _tx('t2', customerId: 'c1', total: 10000, at: DateTime(2026, 3, 4));
      await _item('i2', txId: 't2', productId: 'p1', qty: 1, price: 10000);

      final s = await db.getCustomerStatsSummary('c1', _from, _to);
      expect(s.totalSpent, 40000);
      expect(s.txCount, 2);
      expect(s.itemQty, 4);
      expect(s.avgPerTx, 20000);
    });

    test('nota TEMPO (belum dibayar) TETAP dihitung sbg belanja', () async {
      await _product('p1', 'Beras');
      await _customer('c1', 'Bu Ani');
      await _tx('t1',
          customerId: 'c1',
          total: 50000,
          at: DateTime(2026, 3, 1),
          status: 'tempo');
      await _item('i1', txId: 't1', productId: 'p1', qty: 5, price: 10000);

      final s = await db.getCustomerStatsSummary('c1', _from, _to);
      expect(s.totalSpent, 50000,
          reason: 'pakai `total` (nilai nota), bukan `paid` — konsisten dgn '
              'getTopCustomersByRevenue yang jadi pintu masuknya');
    });

    test('tidak ada transaksi -> nol semua, avgPerTx tidak dibagi nol',
        () async {
      await _customer('c1', 'Bu Ani');
      final s = await db.getCustomerStatsSummary('c1', _from, _to);
      expect(s.totalSpent, 0);
      expect(s.txCount, 0);
      expect(s.avgPerTx, 0);
    });

    test('produk favorit pelanggan terurut by omzet', () async {
      await _product('p1', 'Beras');
      await _product('p2', 'Gula');
      await _customer('c1', 'Bu Ani');
      await _tx('t1', customerId: 'c1', total: 50000, at: DateTime(2026, 3, 1));
      await _item('i1', txId: 't1', productId: 'p1', qty: 1, price: 10000, cost: 6000);
      await _item('i2', txId: 't1', productId: 'p2', qty: 2, price: 20000, cost: 12000);

      final top = await db.getCustomerTopProducts('c1', _from, _to);
      expect(top.map((e) => e.name), ['Gula', 'Beras']);
      expect(top.first.revenue, 40000);
      expect(top.first.profit, 40000 - 24000);
    });

    test('daftar nota pelanggan: terbaru dulu, void dikecualikan', () async {
      await _customer('c1', 'Bu Ani');
      await _tx('t1', customerId: 'c1', total: 10000, at: DateTime(2026, 3, 1));
      await _tx('t2', customerId: 'c1', total: 20000, at: DateTime(2026, 3, 9));
      await _tx('t3',
          customerId: 'c1',
          total: 30000,
          at: DateTime(2026, 3, 5),
          status: 'void');

      final txs = await db.getCustomerTransactions('c1', _from, _to);
      expect(txs.map((t) => t.id), ['t2', 't1']);
    });
  });
}
