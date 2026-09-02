import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Permintaan user: pre-order dengan jaminan/DP yang harganya dikunci Rp 0
/// saat checkout (`_effectivePrice` di `item_entry_sheet.dart`) — begitu
/// pre-order dipenuhi, kasir butuh cara MENGUMPULKAN pembayaran itu, walau
/// nota sudah LUNAS utk item lain (`editPaidTransactionItem` sengaja
/// menolak kenaikan nilai, jadi butuh jalur khusus: `collectPreorderDeposit`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx() async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Tabung Gas'));
    // Nota sudah LUNAS (item lain sudah bayar penuh), tapi item LPG
    // (ti_lpg) dikunci Rp 0 (jaminan pre-order belum dibayar) — persis
    // kasus user: "lunas selain LPG (no DP)".
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 30000,
          paid: 30000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti_lain',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 30000,
          originalPrice: 30000,
          subtotal: 30000,
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti_lpg',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U2',
          qty: 2,
          priceAtSale: 0,
          originalPrice: 15000,
          subtotal: 0,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: 'tx1', amount: 30000, method: 'tunai'));
  }

  test('getPreorderDepositOwed: null kalau tidak tertaut baris nota', () async {
    await seedTx();
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U2',
        customerName: 'Umum',
        qtyOrdered: 2,
        transactionId: 'tx1');
    // transactionItemId TIDAK diisi (entri lama / titip wadah tanpa beli).

    expect(await db.getPreorderDepositOwed('po1'), isNull);
  });

  test('getPreorderDepositOwed: mengembalikan selisih originalPrice*qty '
      'dgn subtotal saat ini', () async {
    await seedTx();
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U2',
        customerName: 'Umum',
        qtyOrdered: 2,
        transactionId: 'tx1',
        transactionItemId: 'ti_lpg');

    expect(await db.getPreorderDepositOwed('po1'), 30000);
  });

  test('collectPreorderDeposit: menaikkan subtotal item, reconcile total '
      'nota, catat ke Riwayat Pembayaran, tandai preorder paid, & catat '
      'event "bayar"', () async {
    await seedTx();
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U2',
        customerName: 'Umum',
        qtyOrdered: 2,
        transactionId: 'tx1',
        transactionItemId: 'ti_lpg');

    final owed = await db.collectPreorderDeposit(
        preorderEntryId: 'po1',
        amount: 30000,
        method: 'tunai',
        kasirId: 'K1');
    expect(owed, 30000);

    final item = await (db.select(db.transactionItems)
          ..where((t) => t.id.equals('ti_lpg')))
        .getSingle();
    expect(item.priceAtSale, 15000);
    expect(item.subtotal, 30000);

    final tx =
        await (db.select(db.transactions)..where((t) => t.id.equals('tx1')))
            .getSingle();
    expect(tx.total, 60000);
    expect(tx.paid, 60000);
    expect(tx.status, 'lunas');

    // Riwayat Pembayaran (transaction_payments) — pembayaran DP baru harus
    // muncul di sini, BUKAN cuma di transaction_items.
    final payments = await (db.select(db.transactionPayments)
          ..where((t) => t.transactionId.equals('tx1')))
        .get();
    expect(payments, hasLength(2));
    expect(payments.any((p) => p.amount == 30000 && p.id != 'pay1'), isTrue);

    final entry = await (db.select(db.preorderEntries)
          ..where((t) => t.id.equals('po1')))
        .getSingle();
    expect(entry.paid, isTrue);

    // Riwayat card pre-order di nota (laci_meja_events) — event 'bayar'.
    final events = await (db.select(db.laciMejaEvents)
          ..where((t) => t.entryId.equals('po1'))
          ..where((t) => t.aksi.equals('bayar')))
        .get();
    expect(events, hasLength(1));
    expect(events.single.qty, 0);
    expect(events.single.note, contains('Rp 30.000'));

    // Sudah dibayar -> tidak ada lagi yang perlu dikumpulkan.
    expect(await db.getPreorderDepositOwed('po1'), isNull);
  });

  test('collectPreorderDeposit: null kalau tidak ada yang perlu '
      'dikumpulkan (sudah lunas)', () async {
    await seedTx();
    await db.addPreorderEntry(
        id: 'po1',
        productId: 'P1',
        productUnitId: 'U1',
        customerName: 'Umum',
        qtyOrdered: 1,
        transactionId: 'tx1',
        transactionItemId: 'ti_lain');

    final owed = await db.collectPreorderDeposit(
        preorderEntryId: 'po1',
        amount: 5000,
        method: 'tunai',
        kasirId: 'K1');
    expect(owed, isNull);

    // Tidak ada pembayaran baru yang tercatat.
    final payments = await (db.select(db.transactionPayments)
          ..where((t) => t.transactionId.equals('tx1')))
        .get();
    expect(payments, hasLength(1));
  });
}
