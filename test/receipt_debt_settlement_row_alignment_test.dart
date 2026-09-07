import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

/// Dilaporkan user (dgn screenshot): baris item "Lunasi Nota #X" struk
/// IN-APP tidak sejajar kolom dgn baris produk di atasnya — sebelumnya
/// `_DebtSettlementSummaryRow` cuma `Padding`+`Row` polos tanpa
/// leading/indent, sementara baris produk pakai `ListTile` (leading
/// Checkbox + contentPadding tertentu). Redesain keempat: baris hutang
/// SEKARANG jadi `ListTile` juga, dgn `contentPadding`/`dense` PERSIS sama
/// dgn baris produk non-varian, supaya kolom nama & nominal jatuh sejajar.
///
/// Kode nota lengkap yg direfer (`invoiceLocalId`) dipindah jadi "catatan
/// item" via `_Blockquote` (reuse widget yg sama dipakai `item.itemNote`
/// produk) — judul tetap pakai `shortLabel` yg sudah dipersingkat.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const fakeDevice = DeviceIdentity(
    storeUuid: 'test-store-uuid',
    storeKey: 'test-store-key',
    storeName: 'Toko Uji',
    deviceName: 'Kasir Uji',
    deviceCode: 'K1',
    deviceRole: 'owner',
  );

  Future<void> seedNewTx() async {
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
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P0', name: 'Indomie'));
    await db.into(db.productUnits).insert(
        ProductUnitsCompanion.insert(id: 'U0', productId: 'P0'));
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

  Future<void> seedOldTx() async {
    // Nota ASLI yg dilunasi (invoiceId 'old1') — item DISTINGTIF dipakai
    // utk membuktikan hyperlink navigasi sungguhan, bukan cuma widget yg
    // kebetulan sama jenisnya.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'old1',
          localId: 'K1-20260907-0012',
          status: 'lunas',
          total: 15000,
          paid: 15000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P-old', name: 'Barang Khas Nota Lama'));
    await db.into(db.productUnits).insert(
        ProductUnitsCompanion.insert(id: 'U-old', productId: 'P-old'));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'io0',
        transactionId: 'old1',
        productId: 'P-old',
        productUnitId: 'U-old',
        qty: 1,
        priceAtSale: 15000,
        originalPrice: 15000,
        subtotal: 15000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'payo0',
            transactionId: 'old1',
            amount: 15000,
            method: 'tunai'));
  }

  Future<void> pumpReceiptApp(WidgetTester tester, String txId) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/kasir/struk/$txId',
      routes: [
        GoRoute(
          path: '/kasir/struk/:txId',
          builder: (_, state) =>
              ReceiptScreen(transactionId: state.pathParameters['txId']!),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          deviceProvider
              .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'baris "Lunasi Nota #X" jadi ListTile dgn contentPadding/dense PERSIS '
      'sama dgn ListTile item produk (sejajar kolom)', (tester) async {
    await seedNewTx();
    await pumpReceiptApp(tester, 'tx1');

    // ListTile item produk (baris "Indomie") sbg referensi.
    final produkListTile = tester.widget<ListTile>(find.ancestor(
      of: find.textContaining('Indomie', findRichText: true),
      matching: find.byType(ListTile),
    ));

    // ListTile baris hutang.
    final debtListTileFinder = find.ancestor(
      of: find.text('Lunasi Nota #12'),
      matching: find.byType(ListTile),
    );
    expect(debtListTileFinder, findsOneWidget,
        reason: 'baris hutang harus berupa ListTile (dulu Padding+Row '
            'polos, itulah akar penyebab tidak sejajar)');
    final debtListTile = tester.widget<ListTile>(debtListTileFinder);

    expect(debtListTile.dense, produkListTile.dense);
    expect(debtListTile.contentPadding, produkListTile.contentPadding);
    expect(debtListTile.contentPadding,
        const EdgeInsets.only(left: 4, right: 12));

    // Leading harus sama lebarnya dgn Checkbox produk (48) — dibungkus
    // SizedBox eksplisit supaya kolom indent PERSIS sama.
    final leadingIcon = find.descendant(
      of: debtListTileFinder,
      matching: find.byIcon(Icons.receipt_long_outlined),
    );
    expect(leadingIcon, findsOneWidget);
    final leadingSizedBox = tester.widget<SizedBox>(find.ancestor(
      of: leadingIcon,
      matching: find.byType(SizedBox),
    ).first);
    expect(leadingSizedBox.width, 48);
    expect(leadingSizedBox.height, 48);

    await drain(tester);
  });

  testWidgets(
      'kode nota LENGKAP muncul via catatan (blockquote), judul tetap pakai '
      'shortLabel yg dipersingkat', (tester) async {
    await seedNewTx();
    await pumpReceiptApp(tester, 'tx1');

    expect(find.text('Lunasi Nota #12'), findsOneWidget);
    expect(find.text('Nota asal: K1-20260907-0012'), findsOneWidget,
        reason: 'kode nota lengkap dipindah ke catatan item (reuse '
            '_Blockquote), bukan dihapus');

    await drain(tester);
  });

  testWidgets(
      'hyperlink "Lunasi Nota #X" TETAP berfungsi setelah restrukturisasi '
      'jadi ListTile -> tap navigasi ke nota asal', (tester) async {
    await seedNewTx();
    await seedOldTx();
    await pumpReceiptApp(tester, 'tx1');

    expect(find.textContaining('Barang Khas Nota Lama', findRichText: true),
        findsNothing,
        reason: 'belum navigasi -- masih di nota baru');

    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((rt) => rt.text.toPlainText().contains('Lunasi Nota #12'));
    final span = _findSpanWithText(richText.text, 'Lunasi Nota #12');
    expect(span, isNotNull);
    final recognizer = (span as TextSpan).recognizer;
    expect(recognizer, isA<TapGestureRecognizer>(),
        reason: 'hyperlink harus tetap ada setelah dipindah ke ListTile');
    (recognizer as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(find.textContaining('Barang Khas Nota Lama', findRichText: true),
        findsOneWidget,
        reason: 'tap berhasil navigasi ke nota ASLI (old1)');

    await drain(tester);
  });
}

InlineSpan? _findSpanWithText(InlineSpan span, String text) {
  if (span is TextSpan) {
    if (span.text != null && span.text!.contains(text)) return span;
    if (span.children != null) {
      for (final child in span.children!) {
        final found = _findSpanWithText(child, text);
        if (found != null) return found;
      }
    }
  }
  return null;
}
