import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// PLAN.md Item 58 — pelanggan TERDAFTAR harus dicocokkan ke pre-order-nya
/// MURNI lewat `PreorderEntries.customerId`, BUKAN nama, supaya dua
/// pelanggan terdaftar beda id yang kebetulan namanya SAMA ("Budi" vs
/// "Budi") tidak saling tertaut pre-order-nya. Pembeli ad-hoc (tanpa
/// customerId) tetap lewat nama seperti sebelumnya (satu-satunya identitas
/// yg tersedia utk kasus itu) — dibuktikan sbg regresi negatif di bawah.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx(String id, {String? customerId, String? customerName}) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: 'lunas',
            total: 10000,
            paid: 10000,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerId: customerId == null
                ? const Value.absent()
                : Value(customerId),
            customerName: customerName == null
                ? const Value.absent()
                : Value(customerName),
          ));

  Future<void> seedCustomer(String id, String name) =>
      db.into(db.customers).insert(CustomersCompanion.insert(id: id, name: name));

  group('getOpenPreorderRefsForCustomer — nama kembar (Item 58)', () {
    test('pelanggan TERDAFTAR dicocokkan lewat customerId, TIDAK ikut '
        'pre-order pelanggan LAIN yang kebetulan namanya sama', () async {
      await seedCustomer('cust-A', 'Budi');
      await seedCustomer('cust-B', 'Budi');
      await seedTx('tx-a', customerId: 'cust-A', customerName: 'Budi');
      await seedTx('tx-b', customerId: 'cust-B', customerName: 'Budi');
      await seedTx('tx-baru', customerId: 'cust-A', customerName: 'Budi');
      await db.addPreorderEntry(
          id: 'p-a',
          productId: 'P-A',
          productUnitId: 'U1',
          customerId: 'cust-A',
          customerName: 'Budi',
          qtyOrdered: 3,
          transactionId: 'tx-a');
      await db.addPreorderEntry(
          id: 'p-b',
          productId: 'P-B',
          productUnitId: 'U1',
          customerId: 'cust-B',
          customerName: 'Budi',
          qtyOrdered: 7,
          transactionId: 'tx-b');

      final refs = await db.getOpenPreorderRefsForCustomer(
          customerId: 'cust-A',
          customerName: 'Budi',
          excludeTransactionId: 'tx-baru');

      expect(refs.containsKey('P-A'), isTrue,
          reason: 'pre-order milik cust-A sendiri harus tetap muncul');
      expect(refs.containsKey('P-B'), isFalse,
          reason: 'pre-order milik cust-B (nama kembar) TIDAK boleh ikut '
              'walau namanya sama-sama Budi');
    });

    test('pembeli ad-hoc (customerId null) tetap match by nama seperti '
        'sebelumnya (regresi negatif — fallback lama tidak boleh rusak)',
        () async {
      await seedTx('tx-lama', customerName: 'Bu Rina');
      await seedTx('tx-baru', customerName: 'Bu Rina');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 5,
          transactionId: 'tx-lama');

      final refs = await db.getOpenPreorderRefsForCustomer(
          customerName: 'Bu Rina', excludeTransactionId: 'tx-baru');

      expect(refs['P1']?.transactionId, 'tx-lama');
    });
  });

  group('getLaciMejaPending — nama kembar (Item 58)', () {
    test('pelanggan TERDAFTAR dicocokkan lewat customerId, TIDAK ikut '
        'pre-order pelanggan LAIN yang kebetulan namanya sama', () async {
      await seedCustomer('cust-A', 'Budi');
      await seedCustomer('cust-B', 'Budi');
      await db.addPreorderEntry(
          id: 'p-a',
          productId: 'P-A',
          productUnitId: 'U1',
          customerId: 'cust-A',
          customerName: 'Budi',
          qtyOrdered: 3);
      await db.addPreorderEntry(
          id: 'p-b',
          productId: 'P-B',
          productUnitId: 'U1',
          customerId: 'cust-B',
          customerName: 'Budi',
          qtyOrdered: 7);

      final pending =
          await db.getLaciMejaPending(customerId: 'cust-A', customerName: 'Budi');

      expect(pending.preorders.length, 1,
          reason: 'hanya pre-order milik cust-A yang boleh ikut');
      expect(pending.preorders.single.qty, 3);
    });

    test('pembeli ad-hoc (customerId null) tetap match by nama seperti '
        'sebelumnya (regresi negatif — fallback lama tidak boleh rusak)',
        () async {
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 5);

      final pending = await db.getLaciMejaPending(customerName: 'Bu Rina');

      expect(pending.preorders.length, 1);
      expect(pending.preorders.single.qty, 5);
    });
  });
}
