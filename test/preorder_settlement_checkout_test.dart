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
          fulfillOnSettle: false,
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
          fulfillOnSettle: false,
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
          fulfillOnSettle: false,
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

  test(
      'Item 66: fulfillOnSettle=true -> pre-order langsung terpenuhi & stok '
      'terpotong PENUH dalam checkout yang SAMA (bukan cuma DP terkumpul)',
      () async {
    await seedPreorderSource(
        txId: 'po_src6',
        preorderId: 'po6',
        customerId: 'c6',
        customerName: 'Rini',
        qty: 3);
    await db.adjustStock(productUnitId: 'U2', newQty: 10, note: 'seed');

    const newTxId = 'newtx6';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(newTxId, total: 5000),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: const [],
      preorderSettlements: [
        (
          preorderEntryId: 'po6',
          invoiceId: 'po_src6',
          invoiceLocalId: 'po_src6',
          invoiceDate: DateTime.now().subtract(const Duration(days: 2)),
          customerName: 'Rini',
          amount: 30000,
          method: 'tunai',
          methodName: null,
          fulfillOnSettle: true,
        ),
      ],
      kasirId: 'K1',
    );

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po6')))
        .getSingle();
    expect(entry.paid, isTrue, reason: 'DP tetap ikut terkumpul spt biasa');
    expect(entry.fulfilledAt, isNotNull,
        reason: 'fulfillOnSettle=true harus langsung memenuhi entrinya');

    final stock = await db.currentStock('U2');
    expect(stock, 7,
        reason: 'stok harus terpotong PENUH sejumlah qtyOrdered (3), sama '
            'seperti fulfillPreorderEntry dipanggil manual');

    final ledgerRows = await (db.select(db.stockLedger)
          ..where((t) => t.type.equals('preorder_fulfill')))
        .get();
    expect(ledgerRows, hasLength(1));
    expect(ledgerRows.single.qtyChange, -3);
  });

  test(
      'Item 66: fulfillOnSettle=false (default) -> DP terkumpul TAPI entri '
      'TETAP belum terpenuhi, stok TIDAK tersentuh -- tidak ada regresi',
      () async {
    await seedPreorderSource(
        txId: 'po_src7',
        preorderId: 'po7',
        customerId: 'c7',
        customerName: 'Tono',
        qty: 3);
    await db.adjustStock(productUnitId: 'U2', newQty: 10, note: 'seed');

    const newTxId = 'newtx7';
    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion(newTxId, total: 5000),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: const [],
      preorderSettlements: [
        (
          preorderEntryId: 'po7',
          invoiceId: 'po_src7',
          invoiceLocalId: 'po_src7',
          invoiceDate: DateTime.now().subtract(const Duration(days: 2)),
          customerName: 'Tono',
          amount: 30000,
          method: 'tunai',
          methodName: null,
          fulfillOnSettle: false,
        ),
      ],
      kasirId: 'K1',
    );

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po7')))
        .getSingle();
    expect(entry.paid, isTrue);
    expect(entry.fulfilledAt, isNull,
        reason: 'default fulfillOnSettle=false TIDAK boleh ikut memenuhi — '
            'pemenuhan tetap jalur terpisah (dashboard/tombol Penuhi struk)');

    final stock = await db.currentStock('U2');
    expect(stock, 10, reason: 'stok TIDAK boleh tersentuh sama sekali');

    final ledgerRows = await (db.select(db.stockLedger)
          ..where((t) => t.type.equals('preorder_fulfill')))
        .get();
    expect(ledgerRows, isEmpty);
  });

  test(
      'Item 78: locallyModified=true dari checkout (device non-owner) WAJIB '
      'diteruskan ke baris preorderEntries.paid=true yang dihasilkan '
      'collectPreorderDeposit -- kalau tidak, baris itu tidak pernah '
      'diusulkan ke host (dumpLaciMejaProposals filter locally_modified=1)',
      () async {
    await seedPreorderSource(
        txId: 'po_src8',
        preorderId: 'po8',
        customerId: 'c8',
        customerName: 'Wati');

    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion('newtx8', total: 25000),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: const [],
      preorderSettlements: [
        (
          preorderEntryId: 'po8',
          invoiceId: 'po_src8',
          invoiceLocalId: 'po_src8',
          invoiceDate: DateTime.now().subtract(const Duration(days: 2)),
          customerName: 'Wati',
          amount: 30000,
          method: 'tunai',
          methodName: null,
          fulfillOnSettle: false,
        ),
      ],
      kasirId: 'K2',
      locallyModified: true,
    );

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po8')))
        .getSingle();
    expect(entry.paid, isTrue);
    expect(entry.locallyModified, isTrue,
        reason: 'device non-owner wajib menandai baris ini supaya ikut '
            'diusulkan ke host lewat dumpLaciMejaProposals');

    // Baris ini HARUS ikut terambil oleh dumpLaciMejaProposals sekarang.
    final proposals = await db.dumpLaciMejaProposals();
    expect(
        (proposals['preorder_entries'] ?? const [])
            .any((r) => r['id'] == 'po8'),
        isTrue);
  });

  test(
      'Item 78: locallyModified=true + fulfillOnSettle=true WAJIB diteruskan '
      'juga ke fulfillPreorderEntry (fulfilledAt), bukan cuma paid',
      () async {
    await seedPreorderSource(
        txId: 'po_src9',
        preorderId: 'po9',
        customerId: 'c9',
        customerName: 'Nur');

    await db.saveTransactionWithDebtSettlements(
      tx: newSaleCompanion('newtx9', total: 25000),
      items: const [],
      payments: const [],
      stockItems: const [],
      debtSettlements: const [],
      preorderSettlements: [
        (
          preorderEntryId: 'po9',
          invoiceId: 'po_src9',
          invoiceLocalId: 'po_src9',
          invoiceDate: DateTime.now().subtract(const Duration(days: 2)),
          customerName: 'Nur',
          amount: 30000,
          method: 'tunai',
          methodName: null,
          fulfillOnSettle: true,
        ),
      ],
      kasirId: 'K2',
      locallyModified: true,
    );

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po9')))
        .getSingle();
    expect(entry.fulfilledAt, isNotNull);
    expect(entry.locallyModified, isTrue,
        reason: 'baris yg SEKALIGUS dipenuhi via checkout kasir non-owner '
            'juga wajib nyangkut sbg locallyModified, bukan cuma paid=true');
  });
}
