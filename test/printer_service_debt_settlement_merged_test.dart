import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/printer_service.dart';

/// Redesain ketiga "Lunasi Hutang" (permintaan user): di struk cetak
/// ESC/POS, baris nota yg dilunasi harus MENYATU LANGSUNG ke list item
/// produk (baris terakhir, SEBELUM baris "Total") — bukan lagi section
/// terpisah berheader "Turut lunasi hutang:" SETELAH ringkasan
/// Bayar/Kembali/Sisa. Lihat juga
/// `test/receipt_debt_settlement_merged_list_test.dart` utk versi in-app/
/// share.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'ESC/POS: baris "Lunasi Nota #12" tercetak SEBELUM "Total", TANPA '
      'header "Turut lunasi hutang:" terpisah', () async {
    const txId = 'tx1';
    final detail = jsonEncode([
      {
        'invoiceId': 'old1',
        'invoiceLocalId': 'K1-20260907-0012',
        'invoiceDate': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'amount': 15000,
        'customerName': 'Budi',
      },
    ]);
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-2',
          status: 'lunas',
          total: 65000,
          paid: 65000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          debtSettlementDetail: Value(detail),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 50000,
        originalPrice: 50000,
        subtotal: 50000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: txId,
            amount: 65000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 9, 7, 8, 0))));

    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    final items = await (db.select(db.transactionItems)
          ..where((i) => i.transactionId.equals(txId)))
        .get();
    final payments = await db.getPaymentsForTx(txId);

    final bytes = await PrinterService.debugBuildBytes(
      tx: tx,
      items: items,
      productNames: const {'P0': 'Indomie'},
      unitNames: const {'U0': 'pcs'},
      customer: null,
      storeName: 'Toko A',
      storeAddress: '',
      storePhone: '',
      strukNote: null,
      payments: payments,
      settings: const PrinterSettings(),
    );

    final text = latin1.decode(bytes, allowInvalid: true);

    // Nama singkat wajib, BUKAN localId penuh yg verbose, dan header
    // section lama SUDAH TIDAK ADA.
    expect(text.contains('Lunasi Nota #12'), isTrue,
        reason: 'baris nota yg dilunasi harus tercetak dgn nama singkat');
    expect(text.contains('K1-20260907-0012'), isFalse,
        reason: 'localId penuh terlalu verbose, harus dipersingkat');
    expect(text.contains('Turut lunasi hutang'), isFalse,
        reason: 'header section terpisah lama sudah dihapus — baris '
            'menyatu ke list item');

    // Urutan: "Lunasi Nota #12" harus tercetak SEBELUM "Total" (menyatu ke
    // list item, bukan setelah ringkasan Bayar/Kembali/Sisa).
    final debtIdx = text.indexOf('Lunasi Nota #12');
    final totalIdx = text.indexOf('Total');
    expect(debtIdx, greaterThanOrEqualTo(0));
    expect(totalIdx, greaterThanOrEqualTo(0));
    expect(debtIdx, lessThan(totalIdx),
        reason: '"Lunasi Nota #12" harus tercetak SEBELUM baris "Total" '
            '(bagian dari list item, bukan section setelah ringkasan '
            'pembayaran)');

    // Nama item produk juga harus muncul SEBELUM baris hutang (list yg
    // sama, item dulu baru nota hutang).
    final produkIdx = text.indexOf('Indomie');
    expect(produkIdx, greaterThanOrEqualTo(0));
    expect(produkIdx, lessThan(debtIdx),
        reason: 'item produk harus tercetak sebelum baris nota hutang '
            'dalam list yg sama');
  });
}
