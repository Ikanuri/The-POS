import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 49g — retur/edit nota SUDAH LUNAS: TIDAK bikin nota baru (beda dari
/// [AppDatabase.addReturnTransaction] lama). DB-tier murni sesuai jenjang
/// test CLAUDE.md.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedPaidTx({
    String txId = 'tx1',
    int total = 406000,
    String? customerId,
    int pointsEarned = 0,
  }) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: total,
          paid: total,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: Value(customerId),
          pointsEarned: Value(pointsEarned),
        ));
    // 234 12: 1 Slop x 193.000.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-12',
        transactionId: txId,
        productId: 'P12',
        productUnitId: 'U-Slop',
        qty: 1,
        priceAtSale: 193000,
        originalPrice: 193000,
        subtotal: 193000));
    // 234 Refil: 1 Slop x 213.000.
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i-refil',
        transactionId: txId,
        productId: 'PRefil',
        productUnitId: 'U-Slop-Refil',
        qty: 1,
        priceAtSale: 213000,
        originalPrice: 213000,
        subtotal: 213000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: txId, amount: total, method: 'tunai'));
  }

  group('returnPaidTransactionItems', () {
    test(
        'retur 1 baris (contoh user): item ASLI utuh, baris retur baru '
        'qty negatif, total/paid net turun, refund tunai negatif tercatat',
        () async {
      await seedPaidTx();

      await db.returnPaidTransactionItems(
        txId: 'tx1',
        returns: const [(transactionItemId: 'i-refil', qty: 1)],
        kasirId: 'K1',
        refundMethod: 'tunai',
      );

      final items = await (db.select(db.transactionItems)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      expect(items.length, 3,
          reason: '2 baris asli TETAP ADA + 1 baris retur baru');

      final original =
          items.firstWhere((i) => i.id == 'i-refil');
      expect(original.qty, 1,
          reason: 'item ASLI tidak pernah dihapus/diubah');
      expect(original.subtotal, 213000);

      final returLine =
          items.firstWhere((i) => i.returnedAt != null);
      expect(returLine.qty, -1);
      expect(returLine.subtotal, -213000);
      expect(returLine.productUnitId, 'U-Slop-Refil');

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.total, 193000, reason: 'Total awal 406.000 - retur 213.000');
      expect(tx.status, 'lunas');

      final payments = await (db.select(db.transactionPayments)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      final refund = payments.firstWhere((p) => p.amount < 0);
      expect(refund.amount, -213000);
      expect(refund.method, 'tunai');

      // Stok dikembalikan.
      final ledger = await (db.select(db.stockLedger)
            ..where((t) => t.productUnitId.equals('U-Slop-Refil')))
          .get();
      expect(ledger.any((l) => l.type == 'return_in' && l.qtyChange == 1),
          isTrue);
    });

    test('tidak bisa retur melebihi qty yang pernah dibeli (double-retur)',
        () async {
      await seedPaidTx();

      await db.returnPaidTransactionItems(
        txId: 'tx1',
        returns: const [(transactionItemId: 'i-refil', qty: 1)],
        kasirId: 'K1',
        refundMethod: 'tunai',
      );
      // Coba retur LAGI baris yang sama (qty asli cuma 1, sudah full-retur).
      await db.returnPaidTransactionItems(
        txId: 'tx1',
        returns: const [(transactionItemId: 'i-refil', qty: 1)],
        kasirId: 'K1',
        refundMethod: 'tunai',
      );

      final items = await (db.select(db.transactionItems)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      final returLines = items.where((i) => i.returnedAt != null).toList();
      expect(returLines.length, 1,
          reason: 'retur kedua harus di-clamp ke 0 (tidak nambah baris lagi)');

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.total, 193000,
          reason: 'total tidak boleh turun lagi krn retur kedua ditolak');
    });

    test('reverse poin loyalty proporsional thd nilai refund', () async {
      await seedPaidTx(customerId: 'C1', pointsEarned: 40);
      await db
          .into(db.customers)
          .insert(CustomersCompanion.insert(id: 'C1', name: 'Budi'));
      await db.customUpdate(
          'UPDATE customers SET loyalty_points = 100 WHERE id = ?',
          variables: [Variable.withString('C1')],
          updates: {db.customers});

      // Retur 213.000 dari total 406.000 -> proporsi 213000/406000.
      await db.returnPaidTransactionItems(
        txId: 'tx1',
        returns: const [(transactionItemId: 'i-refil', qty: 1)],
        kasirId: 'K1',
        refundMethod: 'tunai',
      );

      final cust = await (db.select(db.customers)
            ..where((t) => t.id.equals('C1')))
          .getSingle();
      // pointsToReverse = round(40 * 213000/406000) = round(20.98..) = 21.
      expect(cust.loyaltyPoints, 100 - 21);
    });

    test('throws StateError kalau nota BUKAN status lunas', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx2',
            localId: 'K1-2',
            status: 'kurang_bayar',
            total: 100000,
            paid: 50000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));
      await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'i1',
          transactionId: 'tx2',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 100000,
          originalPrice: 100000,
          subtotal: 100000));

      expect(
        () => db.returnPaidTransactionItems(
          txId: 'tx2',
          returns: const [(transactionItemId: 'i1', qty: 1)],
          kasirId: 'K1',
          refundMethod: 'tunai',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('editPaidTransactionItem', () {
    test('turunkan qty -> refund negatif sungguhan, item ASLI diupdate '
        'DI TEMPAT (tanpa baris terpisah)', () async {
      await seedPaidTx();

      await db.editPaidTransactionItem(
        txId: 'tx1',
        transactionItemId: 'i-12',
        newQty: 0.5,
        newPrice: 193000,
        kasirId: 'K1',
        refundMethod: 'tunai',
      );

      final items = await (db.select(db.transactionItems)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      expect(items.length, 2,
          reason: 'TANPA baris terpisah — cuma 2 baris asli, satu diupdate');
      final edited = items.firstWhere((i) => i.id == 'i-12');
      expect(edited.qty, 0.5);
      expect(edited.subtotal, (193000 * 0.5).round());

      final payments = await (db.select(db.transactionPayments)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      final refund = payments.firstWhere((p) => p.amount < 0);
      expect(refund.amount, -(193000 * 0.5).round());
      expect(refund.method, 'tunai');

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.total, 406000 - (193000 * 0.5).round());
    });

    test('menaikkan qty DITOLAK (no-op) — nota sudah settled', () async {
      await seedPaidTx();

      await db.editPaidTransactionItem(
        txId: 'tx1',
        transactionItemId: 'i-12',
        newQty: 2, // naik dari 1 -> 2, harus ditolak
        newPrice: 193000,
        kasirId: 'K1',
        refundMethod: 'tunai',
      );

      final item = await (db.select(db.transactionItems)
            ..where((t) => t.id.equals('i-12')))
          .getSingle();
      expect(item.qty, 1, reason: 'qty TIDAK berubah — menaikkan ditolak');

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.total, 406000, reason: 'total tidak berubah');
    });

    test('edit CUMA catatan (harga/qty sama, delta 0) -> catatan tersimpan, '
        'TANPA refund sama sekali', () async {
      await seedPaidTx();

      await db.editPaidTransactionItem(
        txId: 'tx1',
        transactionItemId: 'i-12',
        newQty: 1, // sama persis
        newPrice: 193000, // sama persis
        newNote: 'Rusak sedikit',
        kasirId: 'K1',
        refundMethod: 'tunai',
      );

      final item = await (db.select(db.transactionItems)
            ..where((t) => t.id.equals('i-12')))
          .getSingle();
      expect(item.itemNote, 'Rusak sedikit',
          reason: 'catatan tetap tersimpan walau delta 0');
      expect(item.qty, 1);
      expect(item.subtotal, 193000);

      final payments = await (db.select(db.transactionPayments)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      expect(payments.where((p) => p.amount < 0), isEmpty,
          reason: 'edit tanpa penurunan nilai TIDAK boleh bikin refund');

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.total, 406000, reason: 'total tidak berubah');
    });

    test('qty jadi 0 -> baris terhapus total', () async {
      await seedPaidTx();

      await db.editPaidTransactionItem(
        txId: 'tx1',
        transactionItemId: 'i-12',
        newQty: 0,
        newPrice: 193000,
        kasirId: 'K1',
        refundMethod: 'tunai',
      );

      final items = await (db.select(db.transactionItems)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      expect(items.any((i) => i.id == 'i-12'), isFalse);
      expect(items.length, 1);
    });
  });
}
