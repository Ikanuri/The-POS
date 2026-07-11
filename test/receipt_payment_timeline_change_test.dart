import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Nota dengan >1 pembayaran: card "Riwayat Pembayaran" menampilkan
/// kembalian MASING-MASING baris (bukan cuma agregat), dan checkbox per
/// baris menulis ke baris pembayarannya sendiri — menjawab ambiguitas
/// "tadi bayar berapa? sisanya sudah dikembalikan?" untuk nota kurang_bayar
/// yang dilunasi belakangan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> insertTx() => db.into(db.transactions).insert(
      TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 55000,
          changeAmount: 5000,
          paymentMethod: 'tunai'));

  Future<void> insertItem() => db.into(db.transactionItems).insert(
      TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 50000,
          originalPrice: 50000,
          subtotal: 50000));

  testWidgets(
      'nota dengan 2 pembayaran: Riwayat Pembayaran tampilkan kembalian '
      'pembayaran PERTAMA juga (bukan cuma yang kedua)', (tester) async {
    await insertTx();
    await insertItem();
    // Pembayaran pertama: 30rb (kurang, belum ada kembalian).
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 30000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 10, 0))));
    // Pembayaran kedua (pelunasan sisa + lebih): 25rb → kembalian 5rb.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay2',
            transactionId: 'tx1',
            amount: 25000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 15, 0)),
            changeGiven: const Value(5000)));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Riwayat Pembayaran'), findsOneWidget);
    // Kembalian dari pembayaran KEDUA tampil PERSIS 2x: di Ringkasan DAN di
    // baris Riwayat Pembayaran — sengaja duplikat, sama-sama merujuk baris
    // pembayaran terakhir yang sama.
    expect(find.text(formatRupiah(5000)), findsNWidgets(2));
  });

  testWidgets(
      'centang kembalian di baris Riwayat Pembayaran menulis ke baris '
      'pembayaran ITU (bukan baris lain)', (tester) async {
    await insertTx();
    await insertItem();
    // Kedua pembayaran sama-sama punya kembalian sendiri (mis. nota yang
    // dapat tambahan item di antara 2 pembayaran) — supaya card Riwayat
    // Pembayaran menampilkan 2 baris checkbox berbeda untuk dibedakan.
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 33000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 10, 0)),
            changeGiven: const Value(3000)));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay2',
            transactionId: 'tx1',
            amount: 25000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 15, 0)),
            changeGiven: const Value(5000)));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    // Urutan "Kembalian" yang dirender: [0] Ringkasan (pembayaran terakhir
    // = pay2), [1] baris Riwayat Pembayaran utk pay1, [2] baris Riwayat
    // Pembayaran utk pay2. Centang baris pay1 secara spesifik.
    await tester.tap(find.text('Kembalian').at(1));
    await tester.pumpAndSettle();

    final pay1 = await (db.select(db.transactionPayments)
          ..where((t) => t.id.equals('pay1')))
        .getSingle();
    expect(pay1.changeTaken, isTrue);
    final pay2 = await (db.select(db.transactionPayments)
          ..where((t) => t.id.equals('pay2')))
        .getSingle();
    expect(pay2.changeTaken, isFalse,
        reason: 'baris pembayaran lain tidak ikut tersentuh');
  });
}
