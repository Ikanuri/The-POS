import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;
import 'package:the_pos/features/kasir/merged_receipt_screen.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 49b — ringkasan struk disederhanakan jadi 3 baris inti (state akhir
/// akumulatif): Total / Dibayar / Kembalian-ATAU-Sisa. Baris "Uang Diterima"
/// (uang tender kotor) DIHAPUS dari SEMUA jenis struk (in-app, share/gambar,
/// nota gabungan) — user: riwayat pembayaran sudah menyimpan info itu, tak
/// perlu diulang di ringkasan. "Sisa"/"SISA" jadi kondisional (bukan selalu
/// tampil) & tak lagi tampil bareng Kembalian sekaligus.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> insertItem(String id, String txId, int price) => db
      .into(db.transactionItems)
      .insert(TransactionItemsCompanion.insert(
          id: id,
          transactionId: txId,
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: price,
          originalPrice: price,
          subtotal: price));

  group('nota lunas dgn kembalian (in-app & share)', () {
    Future<void> seed() async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx1',
            localId: 'K1-1',
            status: 'lunas',
            total: 50000,
            paid: 60000,
            changeAmount: 10000,
            paymentMethod: 'tunai',
          ));
      await insertItem('i1', 'tx1', 50000);
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1',
              transactionId: 'tx1',
              amount: 60000,
              method: 'tunai',
              changeGiven: const Value(10000)));
    }

    testWidgets('in-app: "Uang Diterima" TIDAK tampil, "Kembalian" tetap',
        (tester) async {
      await seed();
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: 'tx1'));

      expect(find.text('Uang Diterima'), findsNothing);
      expect(find.text('Kembalian'), findsWidgets);
    });

    testWidgets(
        'share (_ReceiptPaper): "Uang Diterima" TIDAK tampil, "Kembali" '
        'tetap tampil dgn nilai benar (10.000), TANPA baris Sisa',
        (tester) async {
      await seed();
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: 'tx1'));
      await tester.tap(find.byTooltip('Bagikan Struk'));
      await tester.pumpAndSettle();

      final receiptPaper = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ReceiptPaper');
      expect(receiptPaper, findsOneWidget);

      expect(
          find.descendant(
              of: receiptPaper, matching: find.text('Uang Diterima')),
          findsNothing);
      expect(
          find.descendant(of: receiptPaper, matching: find.text('Kembali')),
          findsOneWidget);
      expect(
          find.descendant(of: receiptPaper, matching: find.text('Sisa')),
          findsNothing,
          reason: 'nota sudah lunas dgn kembalian tidak boleh punya baris '
              'Sisa sekaligus');
    });
  });

  group('nota lunas dgn CICILAN (beberapa pembayaran) + kembalian', () {
    // Reproduksi laporan user (screenshot): 3 barang total 231.200, dibayar
    // via 4 baris tunai (50.000+50.000+100.000+50.000=250.000), kembalian
    // 18.800 diberikan di pembayaran terakhir. Bug: "Dibayar" sempat
    // menampilkan `netPaidDisplay` (= Total, 231.200) BERSAMA "Kembalian
    // 18.800" sekaligus — tak bisa direkonsiliasi pembaca ("kok ada
    // kembalian kalau Dibayar sudah pas Total?"). Seharusnya Dibayar =
    // 250.000 (persis jumlah Riwayat Pembayaran) supaya Total = Dibayar -
    // Kembalian (231.200 = 250.000 - 18.800).
    Future<void> seedCicilan() async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx5',
            localId: 'A1-1',
            status: 'lunas',
            total: 231200,
            paid: 250000,
            changeAmount: 18800,
            paymentMethod: 'tunai',
          ));
      await insertItem('i5a', 'tx5', 19400);
      await insertItem('i5b', 'tx5', 19300);
      await insertItem('i5c', 'tx5', 192500);
      for (final p in [
        ('pay5a', 50000, 0),
        ('pay5b', 50000, 0),
        ('pay5c', 100000, 0),
        ('pay5d', 50000, 18800),
      ]) {
        await db.into(db.transactionPayments).insert(
            TransactionPaymentsCompanion.insert(
                id: p.$1,
                transactionId: 'tx5',
                amount: p.$2,
                method: 'tunai',
                changeGiven: Value(p.$3)));
      }
    }

    testWidgets(
        'in-app: "Dibayar" = 250.000 (jumlah semua pembayaran), BUKAN '
        '231.200 (= Total, salah)', (tester) async {
      await seedCicilan();
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: 'tx5'));

      // formatRupiah() pakai non-breaking space (U+00A0) antara "Rp" dan
      // angka — find.text('Rp 250.000') literal TIDAK match walau
      // tampilannya sama persis (gotcha CLAUDE.md).
      expect(find.textContaining(formatRupiah(250000)), findsOneWidget,
          reason: 'Dibayar harus = Total + Kembalian (231.200 + 18.800), '
              'sama dgn jumlah Riwayat Pembayaran, bukan netPaidDisplay '
              'yang kebetulan sama dgn Total');
    });

    testWidgets(
        'share (_ReceiptPaper): "Bayar.." = 250.000, BUKAN 231.200',
        (tester) async {
      await seedCicilan();
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: 'tx5'));
      await tester.tap(find.byTooltip('Bagikan Struk'));
      await tester.pumpAndSettle();

      final receiptPaper = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ReceiptPaper');
      expect(receiptPaper, findsOneWidget);

      expect(
          find.descendant(
              of: receiptPaper, matching: find.text('Rp 250.000')),
          findsOneWidget);
    });
  });

  group('nota kurang_bayar TANPA kembalian (share)', () {
    testWidgets(
        'share (_ReceiptPaper): baris "Sisa" tampil dgn nilai benar, TANPA '
        'baris Kembali, TANPA teks "Sudah bayar"/"Sisa hutang" lama',
        (tester) async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx2',
            localId: 'K1-2',
            status: 'kurang_bayar',
            total: 100000,
            paid: 40000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));
      await insertItem('i2', 'tx2', 100000);
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay2',
              transactionId: 'tx2',
              amount: 40000,
              method: 'tunai'));

      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: 'tx2'));
      await tester.tap(find.byTooltip('Bagikan Struk'));
      await tester.pumpAndSettle();

      final receiptPaper = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ReceiptPaper');
      expect(receiptPaper, findsOneWidget);

      expect(find.descendant(of: receiptPaper, matching: find.text('Sisa')),
          findsOneWidget);
      expect(
          find.descendant(
              of: receiptPaper, matching: find.text('Rp 60.000')),
          findsOneWidget,
          reason: 'Sisa = 100.000 - 40.000 = 60.000');
      expect(
          find.descendant(of: receiptPaper, matching: find.text('Kembali')),
          findsNothing);
      expect(
          find.descendant(
              of: receiptPaper, matching: find.textContaining('Sudah bayar')),
          findsNothing,
          reason: 'teks lama yg selalu tampil apa pun kondisinya sudah '
              'diganti baris "Sisa" kondisional');
    });
  });

  group('nota gabungan (merged)', () {
    Future<void> seedMerged() async {
      for (final id in ['tx3', 'tx4']) {
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: id,
              localId: 'K1-$id',
              status: 'lunas',
              total: 20000,
              paid: 20000,
              changeAmount: 0,
              paymentMethod: 'tunai',
              customerId: const Value('C1'),
            ));
        await insertItem('item-$id', id, 20000);
        await db.into(db.transactionPayments).insert(
            TransactionPaymentsCompanion.insert(
                id: 'pay-$id',
                transactionId: id,
                amount: 20000,
                method: 'tunai'));
      }
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'C1', name: 'Pelanggan Uji'));
    }

    testWidgets(
        'nota gabungan: "Uang Diterima" TIDAK tampil, "SISA" TIDAK tampil '
        'kalau sudah lunas semua (bukan selalu tampil apa pun kondisinya)',
        (tester) async {
      await seedMerged();
      await pumpWithFakeApp(tester,
          db: db,
          child: const MergedReceiptScreen(txIds: ['tx3', 'tx4']));

      expect(find.text('Uang Diterima'), findsNothing);
      expect(find.text('SISA'), findsNothing,
          reason: 'grandSisa = 0 (lunas semua) — baris SISA harus hilang '
              'total, bukan tampil "Rp 0"');
      expect(find.text('TOTAL TAGIHAN'), findsOneWidget);
    });
  });
}
