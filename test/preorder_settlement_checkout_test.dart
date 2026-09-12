import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Fitur "Pelunasi Pre-order" DI KERANJANG — arsitektur IDENTIK dgn "Lunasi
/// Hutang" (`debt_settlement_checkout_test.dart`, baca dok di sana dulu),
/// param baru `saveTransactionWithDebtSettlements.preorderSettlements`:
/// (1) menyimpan nota BARU normal, TIDAK diinflasi nominal pelunasan
/// pre-order; (2) mengumpulkan DP ke baris nota pre-order SUMBER via
/// `collectPreorderDeposit` (uang masuk ke nota LAMA, bukan nota baru);
/// (3) menandai `preorderEntries.paid = true`; (4) menulis ringkasan
/// `type: 'preorder'` ke `debtSettlementDetail` nota BARU; (5) TIDAK
/// meregresi jalur `debtSettlements`-saja (param baru opsional, default
/// kosong).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  TransactionsCompanion newSaleCompanion(String txId, {int total = 25000}) =>
      TransactionsCompanion.insert(
        id: txId,
        localId: 'NEW-$txId',
        status: 'lunas',
        total: total,
        paid: total,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(DateTime.now()),
      );

  /// Seed pre-order nota SUMBER: satu produk, satu baris item pre-order
  /// dikunci Rp 0 (`priceAtSale: 0`), tertaut `PreorderEntries` — pola sama
  /// persis `preorder_deposit_payment_test.dart`.
  Future<void> seedPreorderSource({
    required String txId,
    required String preorderId,
    required String customerId,
    required String customerName,
    int originalPrice = 15000,
    double qty = 2,
  }) async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Tabung Gas LPG'));
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: customerId, name: customerName));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: txId,
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: Value(customerId),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 2))),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: '${txId}_ti_lain',
          transactionId: txId,
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: '${txId}_ti_lpg',
          transactionId: txId,
          productId: 'P1',
          productUnitId: 'U2',
          qty: qty,
          priceAtSale: 0,
          originalPrice: originalPrice,
          subtotal: 0,
        ));
    await db.addPreorderEntry(
        id: preorderId,
        productId: 'P1',
        productUnitId: 'U2',
        customerName: customerName,
        customerId: customerId,
        qtyOrdered: qty,
        transactionId: txId,
        transactionItemId: '${txId}_ti_lpg');
  }

  test(
      'preorderSettlements: mengumpulkan DP ke nota SUMBER, TIDAK menginflasi '
      'total/paid nota BARU', () async {
    await seedPreorderSource(
        txId: 'po_src1',
        preorderId: 'po1',
        customerId: 'c1',
        customerName: 'Sari');

    const newTxId = 'newtx1';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(newTxId, total: 25000),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: const [],
      preorderSettlements: [
        (
          preorderEntryId: 'po1',
          invoiceId: 'po_src1',
          invoiceLocalId: 'po_src1',
          invoiceDate: DateTime.now().subtract(const Duration(days: 2)),
          customerName: 'Sari',
          amount: 30000,
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    // (a) Nota BARU: total/paid HANYA belanja baru (25000), TIDAK diinflasi
    // nominal pelunasan pre-order (30000).
    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(newTxId)))
        .getSingle();
    expect(newTx.total, 25000);
    expect(newTx.paid, 25000);

    // (b) Baris nota pre-order SUMBER: subtotal/priceAtSale naik dari Rp 0.
    final srcItem = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('po_src1_ti_lpg')))
        .getSingle();
    expect(srcItem.priceAtSale, 15000);
    expect(srcItem.subtotal, 30000);

    // Pembayaran DP tercatat di NOTA SUMBER (transaction_payments), BUKAN
    // nota baru.
    final srcPayments = await db.getPaymentsForTxs(['po_src1']);
    expect((srcPayments['po_src1'] ?? const []).any((p) => p.amount == 30000),
        isTrue);
    final newTxPayments = await db.getPaymentsForTxs([newTxId]);
    expect(newTxPayments[newTxId] ?? const [], isEmpty);

    // (c) preorderEntries.paid flip ke true.
    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(entry.paid, isTrue);

    // (d) debtSettlementDetail nota BARU berisi baris type:'preorder'.
    final parsed = parseDebtSettlementDetail(newTx.debtSettlementDetail);
    expect(parsed, hasLength(1));
    expect(parsed.single.type, 'preorder');
    expect(parsed.single.preorderEntryId, 'po1');
    expect(parsed.single.amount, 30000);
    expect(parsed.single.shortLabel, contains('Lunasi Pre-order #'));
  });

  test(
      'preorderSettlements: entri yg owed-nya SUDAH 0 (dikumpulkan jalur '
      'lain) di-SKIP diam-diam, tidak melempar & tidak menulis detail',
      () async {
    await seedPreorderSource(
        txId: 'po_src2',
        preorderId: 'po2',
        customerId: 'c2',
        customerName: 'Budi');
    // Kumpulkan DULU lewat jalur lain (mis. device lain, dashboard Laci
    // Meja) SEBELUM checkout keranjang ini benar2 jalan (race).
    await db.collectPreorderDeposit(
        preorderEntryId: 'po2', amount: 30000, method: 'tunai', kasirId: 'K9');

    const newTxId = 'newtx2';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(newTxId, total: 10000),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: const [],
      preorderSettlements: [
        (
          preorderEntryId: 'po2',
          invoiceId: 'po_src2',
          invoiceLocalId: 'po_src2',
          invoiceDate: DateTime.now(),
          customerName: 'Budi',
          amount: 30000,
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(newTxId)))
        .getSingle();
    expect(newTx.total, 10000);
    expect(newTx.paid, 10000);
    // Tidak ada apa pun yg perlu ditulis (entri satu2nya di-skip) ->
    // debtSettlementDetail null, bukan list kosong "[]" yg salah kaprah.
    expect(newTx.debtSettlementDetail, isNull);
  });

  test(
      'debtSettlements-saja (preorderSettlements default kosong) BERPERILAKU '
      'SAMA seperti sebelum param ini ada — tidak ada regresi', () async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c3', name: 'Dedi'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'old3',
          localId: 'old3',
          status: 'tempo',
          total: 20000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('c3'),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
        ));

    const newTxId = 'newtx3';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(newTxId, total: 5000),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: [
        (
          customerName: 'Dedi',
          amount: 20000,
          targets: [
            (
              invoiceId: 'old3',
              invoiceLocalId: 'old3',
              invoiceDate: DateTime.now(),
              amount: 20000,
            ),
          ],
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    final old = await (db.select(db.transactions)
          ..where((t) => t.id.equals('old3')))
        .getSingle();
    expect(old.status, 'lunas');
    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(newTxId)))
        .getSingle();
    final parsed = parseDebtSettlementDetail(newTx.debtSettlementDetail);
    expect(parsed, hasLength(1));
    expect(parsed.single.type, 'debt');
    expect(parsed.single.shortLabel, contains('Lunasi Nota #'));
  });

  test('dua pelanggan berbeda: hutang + pre-order tergabung dalam satu '
      'ringkasan `debtSettlementDetail`', () async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c4', name: 'Andi'));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'old4',
          localId: 'old4',
          status: 'tempo',
          total: 10000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('c4'),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
        ));
    await seedPreorderSource(
        txId: 'po_src5',
        preorderId: 'po5',
        customerId: 'c5',
        customerName: 'Wati');

    const newTxId = 'newtx4';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(newTxId, total: 1000),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: [
        (
          customerName: 'Andi',
          amount: 10000,
          targets: [
            (
              invoiceId: 'old4',
              invoiceLocalId: 'old4',
              invoiceDate: DateTime.now(),
              amount: 10000,
            ),
          ],
          method: 'tunai',
          methodName: null,
        ),
      ],
      preorderSettlements: [
        (
          preorderEntryId: 'po5',
          invoiceId: 'po_src5',
          invoiceLocalId: 'po_src5',
          invoiceDate: DateTime.now(),
          customerName: 'Wati',
          amount: 30000,
          method: 'tunai',
          methodName: null,
        ),
      ],
      kasirId: 'K1',
    );

    final newTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(newTxId)))
        .getSingle();
    final parsed = parseDebtSettlementDetail(newTx.debtSettlementDetail);
    expect(parsed, hasLength(2));
    expect(parsed.map((l) => l.type).toSet(), {'debt', 'preorder'});
    expect(parsed.map((l) => l.amount), containsAll([10000, 30000]));
  });

  test(
      'parseDebtSettlementDetail: JSON LAMA tanpa field type/preorderEntryId '
      '(sebelum fitur Pelunasi Pre-order) -> type default "debt", aman', () {
    const raw =
        '[{"invoiceLocalId":"A1-1","amount":15000,"customerName":"Sari"}]';
    final parsed = parseDebtSettlementDetail(raw);
    expect(parsed.single.type, 'debt');
    expect(parsed.single.preorderEntryId, isNull);
    expect(parsed.single.shortLabel, 'Lunasi Nota #1');
  });

  test(
      'parseDebtSettlementDetail: JSON BARU type="preorder" -> shortLabel '
      '"Lunasi Pre-order #N"', () {
    const raw = '[{"invoiceId":"po_src9","invoiceLocalId":"K1-9",'
        '"invoiceDate":1767225600000,"amount":30000,"customerName":"Sari",'
        '"type":"preorder","preorderEntryId":"po9"}]';
    final parsed = parseDebtSettlementDetail(raw);
    expect(parsed.single.type, 'preorder');
    expect(parsed.single.preorderEntryId, 'po9');
    expect(parsed.single.shortLabel, 'Lunasi Pre-order #9');
  });
}
