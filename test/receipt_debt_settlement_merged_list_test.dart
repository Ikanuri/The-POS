import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Redesain ketiga "Lunasi Hutang" (permintaan user): baris nota yg
/// dilunasi harus MENYATU LANGSUNG ke list item produk struk (bukan lagi
/// section terpisah berheader "Turut melunasi hutang:") — di KETIGA jenis
/// struk (in-app, share/gambar `_ReceiptPaper`, cetak ESC/POS). Test ini
/// memverifikasi versi in-app & share/gambar; verifikasi ESC/POS ada di
/// `test/printer_service_debt_settlement_merged_test.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seed() async {
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
  }

  testWidgets(
      'in-app: baris "Lunasi Nota #12" jadi SIBLING item produk (bukan '
      'section terpisah "Turut melunasi hutang:")', (tester) async {
    await seed();
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.pumpAndSettle();

    // Nama singkat wajib pakai segmen terakhir localId, BUKAN localId
    // penuh yg verbose.
    expect(find.text('Lunasi Nota #12'), findsOneWidget);
    expect(find.textContaining('K1-20260907-0012'), findsNothing);

    // Header section lama HARUS SUDAH TIDAK ADA — baris ini sudah menyatu
    // ke list item, konteksnya jelas tanpa header terpisah.
    expect(find.text('Turut melunasi hutang:'), findsNothing);

    // Struktur: baris hutang harus jadi SIBLING dari ListTile item produk
    // dalam Column yg sama (bukan section terpisah di bawah Total). Cari
    // Column yg berisi KEDUA: ListTile item produk DAN teks "Lunasi Nota
    // #12" sbg direct descendant list-nya.
    final itemColumnFinder = find.ancestor(
      of: find.text('Lunasi Nota #12'),
      matching: find.byType(Column),
    );
    expect(itemColumnFinder, findsWidgets);
    // Salah satu Column leluhur itu juga punya ListTile (baris item
    // produk) sbg descendant — pembuktian keduanya SATU list yg sama.
    bool sameColumnAsItems = false;
    for (final element in itemColumnFinder.evaluate()) {
      final hasListTile = find
          .descendant(of: find.byWidget(element.widget), matching: find.byType(ListTile))
          .evaluate()
          .isNotEmpty;
      if (hasListTile) {
        sameColumnAsItems = true;
        break;
      }
    }
    expect(sameColumnAsItems, isTrue,
        reason: 'baris "Lunasi Nota #12" harus berada di Column yg sama '
            'dgn ListTile item produk (list tunggal), bukan section '
            'terpisah di bawah Total');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'share/gambar (_ReceiptPaper): baris "Lunasi Nota #12" tampil TANPA '
      'header "Turut melunasi hutang:" terpisah', (tester) async {
    await seed();
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();

    expect(find.text('Lunasi Nota #12'), findsWidgets);
    expect(find.text('Turut melunasi hutang:'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
