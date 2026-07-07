import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Sisipkan saldo stok awal dengan timestamp eksplisit. TIDAK memakai
/// [AppDatabase.adjustStock] karena method itu men-hardcode `DateTime.now()`
/// (waktu sungguhan saat test dijalankan) — kalau timestamp transaksi di
/// test memakai tanggal tertentu di masa lalu (mis. 2026-07-01) sementara
/// hari ini sudah lebih baru, `_rawBaseStock` (ORDER BY created_at DESC) akan
/// salah mengira baris opening ini yang "terbaru", membalik urutan kronologis.
Future<void> _seedStock(AppDatabase db, String productUnitId, double qty, DateTime at) async {
  await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
        id: 'seed-$productUnitId-${at.microsecondsSinceEpoch}',
        productUnitId: productUnitId,
        type: 'opening',
        qtyChange: qty,
        stockAfter: qty,
        createdAt: Value(at),
      ));
}

/// Test integrasi Drift asli untuk siklus hidup transaksi paling kritis —
/// fungsi-fungsi ini dieksekusi di SETIAP penjualan, pembatalan, retur, dan
/// pelunasan hutang, tapi sebelumnya belum punya test sama sekali.
void main() {
  group('saveTransaction', () {
    test('memotong stok sesuai qty & menyimpan item/pembayaran dengan benar',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime(2026, 7, 1, 10, 0);
      // Stok awal 50 unit, tercatat SEBELUM waktu transaksi.
      await _seedStock(db, 'U1', 50, now.subtract(const Duration(days: 1)));

      await db.saveTransaction(
        tx: TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(now),
        ),
        items: [
          TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 2,
            priceAtSale: 5000,
            originalPrice: 5000,
            subtotal: 10000,
          ),
        ],
        payments: [
          TransactionPaymentsCompanion.insert(
            id: 'p1',
            transactionId: 'tx1',
            amount: 10000,
            method: 'tunai',
            paidAt: Value(now),
          ),
        ],
        stockItems: const [(productUnitId: 'U1', qty: 2, note: 'K1-1')],
        now: now,
      );

      expect(await db.currentStock('U1'), 48,
          reason: 'stok berkurang persis sebesar qty yang terjual (50-2)');

      final savedItems = await (db.select(db.transactionItems)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      expect(savedItems.single.subtotal, 10000);

      final payments = await db.getPaymentsForTx('tx1');
      expect(payments.single.amount, 10000);

      await db.close();
    });

    test('poin loyalti pelanggan bertambah sesuai loyaltyEntry', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.customers).insert(CustomersCompanion.insert(
            id: 'cust1',
            name: 'Budi',
          ));
      final now = DateTime(2026, 7, 1, 10, 0);
      await _seedStock(db, 'U1', 10, now.subtract(const Duration(days: 1)));

      await db.saveTransaction(
        tx: TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          customerId: const Value('cust1'),
          status: 'lunas',
          total: 20000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          pointsEarned: const Value(4),
          createdAt: Value(now),
        ),
        items: [
          TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 1,
            priceAtSale: 20000,
            originalPrice: 20000,
            subtotal: 20000,
          ),
        ],
        payments: const [],
        stockItems: const [(productUnitId: 'U1', qty: 1, note: 'K1-1')],
        now: now,
        loyaltyEntry: LoyaltyPointLedgerCompanion.insert(
          id: 'lp1',
          customerId: 'cust1',
          type: 'earn',
          points: 4,
          createdAt: Value(now),
        ),
      );

      final cust = await (db.select(db.customers)
            ..where((t) => t.id.equals('cust1')))
          .getSingle();
      expect(cust.loyaltyPoints, 4);

      await db.close();
    });
  });

  group('voidTransaction', () {
    Future<AppDatabase> dbWithSoldTx({int pointsEarned = 0, String? customerId}) async {
      final db = AppDatabase(NativeDatabase.memory());
      if (customerId != null) {
        await db.into(db.customers).insert(CustomersCompanion.insert(
              id: customerId,
              name: 'Budi',
              loyaltyPoints: Value(pointsEarned),
            ));
      }
      final now = DateTime(2026, 7, 1, 10, 0);
      await _seedStock(db, 'U1', 20, now.subtract(const Duration(days: 1)));
      await db.saveTransaction(
        tx: TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          customerId: Value(customerId),
          status: 'lunas',
          total: 15000,
          paid: 15000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          pointsEarned: Value(pointsEarned),
          createdAt: Value(now),
        ),
        items: [
          TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 3,
            priceAtSale: 5000,
            originalPrice: 5000,
            subtotal: 15000,
          ),
        ],
        payments: const [],
        stockItems: const [(productUnitId: 'U1', qty: 3, note: 'K1-1')],
        now: now,
      );
      return db;
    }

    test('mengembalikan stok persis sebesar qty yang terjual & menandai void',
        () async {
      final db = await dbWithSoldTx();
      expect(await db.currentStock('U1'), 17, reason: 'sebelum void: 20-3');

      await db.voidTransaction('tx1', 'K1');

      expect(await db.currentStock('U1'), 20,
          reason: 'stok harus kembali persis ke sebelum penjualan');
      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx1'))).getSingle();
      expect(tx.status, 'void');

      await db.close();
    });

    test('membalik poin loyalti yang sudah didapat', () async {
      final db = await dbWithSoldTx(pointsEarned: 4, customerId: 'cust1');

      await db.voidTransaction('tx1', 'K1');

      final cust = await (db.select(db.customers)..where((t) => t.id.equals('cust1'))).getSingle();
      expect(cust.loyaltyPoints, 0, reason: 'poin yang didapat harus dibalik saat void');

      final ledger = await (db.select(db.loyaltyPointLedger)
            ..where((t) => t.customerId.equals('cust1')))
          .get();
      expect(ledger.any((l) => l.type == 'adjust' && l.points == -4), isTrue);

      await db.close();
    });

    test('void dua kali tidak menggandakan pengembalian stok (idempoten)', () async {
      final db = await dbWithSoldTx();

      await db.voidTransaction('tx1', 'K1');
      await db.voidTransaction('tx1', 'K1'); // panggilan kedua harus no-op

      expect(await db.currentStock('U1'), 20,
          reason: 'void kedua tidak boleh menambah stok lagi (bukan 23)');

      await db.close();
    });
  });

  group('addReturnTransaction (nota sudah lunas)', () {
    test('membuat nota retur terpisah, mengembalikan stok, nota asli tak berubah',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime(2026, 7, 1, 10, 0);
      await _seedStock(db, 'U1', 20, now.subtract(const Duration(days: 1)));
      await db.saveTransaction(
        tx: TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 15000,
          paid: 15000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          createdAt: Value(now),
        ),
        items: [
          TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 3,
            priceAtSale: 5000,
            originalPrice: 5000,
            costAtSale: const Value(3000),
            subtotal: 15000,
          ),
        ],
        payments: const [],
        stockItems: const [(productUnitId: 'U1', qty: 3, note: 'K1-1')],
        now: now,
      );
      expect(await db.currentStock('U1'), 17);

      await db.addReturnTransaction(
        originalTxId: 'tx1',
        localId: 'K1-2',
        returnItems: const [
          (
            productUnitId: 'U1',
            productId: 'P1',
            qty: 1,
            price: 5000,
            costPrice: 3000,
            itemNote: null,
          ),
        ],
        kasirId: 'K1',
      );

      expect(await db.currentStock('U1'), 18, reason: '17+1 dikembalikan');

      // Nota ASLI tidak disentuh sama sekali (model lama: nota retur terpisah).
      final orig = await (db.select(db.transactions)..where((t) => t.id.equals('tx1'))).getSingle();
      expect(orig.total, 15000);
      expect(orig.status, 'lunas');

      // Nota retur baru: total negatif = nilai refund. Id nota retur
      // di-generate acak (Uuid) oleh addReturnTransaction, jadi dicari lewat
      // internal_note, bukan lewat 'K1-2' (yang cuma dipakai sebagai localId).
      final returByNote = await (db.select(db.transactions)
            ..where((t) => t.internalNote.equals('RETUR:tx1')))
          .getSingle();
      expect(returByNote.total, -5000);
      expect(returByNote.paid, -5000);
      expect(returByNote.localId, 'K1-2');

      await db.close();
    });

    test('poin loyalti dibalik proporsional terhadap nilai refund', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.customers).insert(CustomersCompanion.insert(
            id: 'cust1',
            name: 'Budi',
            loyaltyPoints: const Value(10),
          ));
      final now = DateTime(2026, 7, 1, 10, 0);
      await _seedStock(db, 'U1', 10, now.subtract(const Duration(days: 1)));
      await db.saveTransaction(
        tx: TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          customerId: const Value('cust1'),
          status: 'lunas',
          total: 100000,
          paid: 100000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          pointsEarned: const Value(10),
          createdAt: Value(now),
        ),
        items: [
          TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'tx1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: 10,
            priceAtSale: 10000,
            originalPrice: 10000,
            subtotal: 100000,
          ),
        ],
        payments: const [],
        stockItems: const [(productUnitId: 'U1', qty: 10, note: 'K1-1')],
        now: now,
      );

      // Retur 30% dari nilai transaksi (30000 dari 100000) → poin dibalik 30%.
      await db.addReturnTransaction(
        originalTxId: 'tx1',
        localId: 'K1-2',
        returnItems: const [
          (
            productUnitId: 'U1',
            productId: 'P1',
            qty: 3,
            price: 10000,
            costPrice: 0,
            itemNote: null,
          ),
        ],
        kasirId: 'K1',
      );

      final cust = await (db.select(db.customers)..where((t) => t.id.equals('cust1'))).getSingle();
      expect(cust.loyaltyPoints, 7, reason: '10 - round(10*0.3)=3 → sisa 7');

      await db.close();
    });
  });

  group('settleMergedDebt', () {
    Future<AppDatabase> dbWithTwoDebts() async {
      final db = AppDatabase(NativeDatabase.memory());
      final t1 = DateTime(2026, 7, 1);
      final t2 = DateTime(2026, 7, 2);
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx1',
            localId: 'K1-1',
            status: 'kurang_bayar',
            total: 50000,
            paid: 0,
            changeAmount: 0,
            paymentMethod: 'tempo',
            createdAt: Value(t1),
          ));
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx2',
            localId: 'K1-2',
            status: 'kurang_bayar',
            total: 30000,
            paid: 0,
            changeAmount: 0,
            paymentMethod: 'tempo',
            createdAt: Value(t2),
          ));
      return db;
    }

    test('alokasi FIFO: nota terlama dilunasi dulu, sisa mengalir ke nota berikutnya',
        () async {
      final db = await dbWithTwoDebts();

      // Bayar 60rb: cukup lunasi tx1 (50rb) + sisa 10rb ke tx2.
      final (applied, change) = await db.settleMergedDebt(
        txIds: ['tx1', 'tx2'],
        amount: 60000,
        method: 'tunai',
        kasirId: 'K1',
      );

      expect(applied, 60000);
      expect(change, 0);

      final tx1 = await (db.select(db.transactions)..where((t) => t.id.equals('tx1'))).getSingle();
      final tx2 = await (db.select(db.transactions)..where((t) => t.id.equals('tx2'))).getSingle();
      expect(tx1.status, 'lunas');
      expect(tx1.paid, 50000);
      expect(tx2.status, 'kurang_bayar', reason: 'baru terbayar sebagian (10rb dari 30rb)');
      expect(tx2.paid, 10000);

      await db.close();
    });

    test('overpay: kelebihan dari total seluruh nota jadi kembalian', () async {
      final db = await dbWithTwoDebts(); // total gabungan 80000

      final (applied, change) = await db.settleMergedDebt(
        txIds: ['tx1', 'tx2'],
        amount: 100000,
        method: 'tunai',
        kasirId: 'K1',
      );

      expect(applied, 80000, reason: 'maksimal yang bisa dialokasikan = total hutang');
      expect(change, 20000, reason: 'sisa uang yang harus dikembalikan ke pelanggan');

      final tx1 = await (db.select(db.transactions)..where((t) => t.id.equals('tx1'))).getSingle();
      final tx2 = await (db.select(db.transactions)..where((t) => t.id.equals('tx2'))).getSingle();
      expect(tx1.status, 'lunas');
      expect(tx2.status, 'lunas');

      await db.close();
    });

    test('nota yang sudah lunas di dalam daftar dilewati, tidak ikut dialokasikan',
        () async {
      final db = await dbWithTwoDebts();
      // Lunasi tx1 duluan secara manual.
      await (db.update(db.transactions)..where((t) => t.id.equals('tx1')))
          .write(const TransactionsCompanion(status: Value('lunas'), paid: Value(50000)));

      final (applied, change) = await db.settleMergedDebt(
        txIds: ['tx1', 'tx2'],
        amount: 30000,
        method: 'tunai',
        kasirId: 'K1',
      );

      expect(applied, 30000, reason: 'seluruhnya masuk ke tx2 (tx1 sudah lunas, dilewati)');
      expect(change, 0);
      final tx2 = await (db.select(db.transactions)..where((t) => t.id.equals('tx2'))).getSingle();
      expect(tx2.status, 'lunas');

      await db.close();
    });
  });
}
