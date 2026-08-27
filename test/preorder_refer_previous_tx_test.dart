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
import 'package:the_pos/features/laci_meja/laci_meja_reminder.dart';

/// Usulan user: pelanggan dgn pre-order TANPA DP, ketika dinamai di cart bar
/// / dilihat notanya di transaksi LAIN yang beda, ada opsi merujuk balik ke
/// nota ASLI tempat pre-order itu dicatat — berguna utk cek momen nota asli.
///
/// Dua titik integrasi (permintaan user):
///  1. Cart bar (baris "Pre-order: ..." pengingat) — tiap produk yang py
///     `transactionId` jadi tappable.
///  2. Struk in-app — nama item yang produknya cocok dgn pre-order terbuka
///     pelanggan ybs (di nota LAIN) jadi tappable.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTx(String id, {String? customerName}) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: 'lunas',
            total: 10000,
            paid: 10000,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerName: customerName == null
                ? const Value.absent()
                : Value(customerName),
          ));

  group('AppDatabase.getOpenPreorderRefsForCustomer (DB murni)', () {
    test('menemukan pre-order terbuka milik nama pelanggan yang sama, '
        'DI NOTA LAIN, dikelompokkan per productId', () async {
      await seedTx('tx-lama');
      await seedTx('tx-baru');
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

    test('TIDAK menampilkan pre-order milik nota yang SEDANG dilihat sendiri',
        () async {
      await seedTx('tx1');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 5,
          transactionId: 'tx1');

      final refs = await db.getOpenPreorderRefsForCustomer(
          customerName: 'Bu Rina', excludeTransactionId: 'tx1');

      expect(refs, isEmpty,
          reason: 'pre-order milik nota ini sendiri bukan "nota lain"');
    });

    test('pre-order yang SUDAH dipenuhi/dibatalkan tidak ikut', () async {
      await seedTx('tx-lama');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 5,
          transactionId: 'tx-lama');
      await db.fulfillPreorderEntry('p1');

      final refs = await db.getOpenPreorderRefsForCustomer(
          customerName: 'Bu Rina', excludeTransactionId: 'tx-baru');

      expect(refs, isEmpty);
    });

    test('pre-order tanpa transactionId (titip wadah tanpa beli apa pun) '
        'tidak ikut -- tidak ada nota utk dirujuk', () async {
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 5);

      final refs = await db.getOpenPreorderRefsForCustomer(
          customerName: 'Bu Rina', excludeTransactionId: 'tx-baru');

      expect(refs, isEmpty);
    });

    test('lebih dari satu pre-order utk produk sama -> yang PALING LAMA '
        '(FIFO) yang dipakai sbg rujukan', () async {
      await seedTx('tx-a');
      await seedTx('tx-b');
      await db.addPreorderEntry(
          id: 'p-a',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 3,
          transactionId: 'tx-a');
      await db.addPreorderEntry(
          id: 'p-b',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 2,
          transactionId: 'tx-b');

      final refs = await db.getOpenPreorderRefsForCustomer(
          customerName: 'Bu Rina', excludeTransactionId: 'tx-lain');

      expect(refs['P1']?.transactionId, 'tx-a',
          reason: 'tx-a dicatat lebih dulu (createdAt lebih lama)');
    });

    test('nama pelanggan kosong -> map kosong, tidak query', () async {
      expect(
          await db.getOpenPreorderRefsForCustomer(
              customerName: '', excludeTransactionId: 'tx1'),
          isEmpty);
    });
  });

  group('Struk in-app: nama item bisa diklik merujuk ke nota pre-order asli',
      () {
    const fakeDevice = DeviceIdentity(
      storeUuid: 'test-store-uuid',
      storeKey: 'test-store-key',
      storeName: 'Toko Uji',
      deviceName: 'Kasir Uji',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    Future<void> pumpReceiptApp(WidgetTester tester, String txId) async {
      SharedPreferences.setMockInitialValues({});
      // Surface generus — `ReceiptScreen` pakai `ListView` yang lazy-build
      // anak di luar viewport (pola sama `pumpWithFakeApp`).
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
            deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> seedItem(String txId, String productId, String unitId,
        {String productName = 'Gas LPG 3kg'}) async {
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: productId, name: productName));
      await db.into(db.productUnits).insert(
          ProductUnitsCompanion.insert(id: unitId, productId: productId));
      await db.into(db.transactionItems).insert(
          TransactionItemsCompanion.insert(
              id: '$txId-i1',
              transactionId: txId,
              productId: productId,
              productUnitId: unitId,
              qty: 1,
              priceAtSale: 20000,
              originalPrice: 20000,
              subtotal: 20000));
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: '$txId-pay', transactionId: txId, amount: 20000, method: 'tunai'));
    }

    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    }

    testWidgets('item dgn pre-order terbuka di nota lain -> tampil "Pre-order '
        'sebelumnya" & tap membuka nota ASLI (bukan nota ini)', (tester) async {
      await seedTx('tx-lama', customerName: 'Bu Rina');
      await seedTx('tx-baru', customerName: 'Bu Rina');
      // Item DISTINGTIF di nota lama, tidak ada di nota baru sama sekali —
      // kalau setelah tap teks ini muncul, itu bukti navigasi SUNGGUHAN ke
      // nota lain, bukan cuma widget yang kebetulan tetap berjenis sama.
      await seedItem('tx-lama', 'P-lama', 'U-lama',
          productName: 'Barang Khas Nota Lama');
      await seedItem('tx-baru', 'P1', 'U1');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 5,
          transactionId: 'tx-lama');

      await pumpReceiptApp(tester, 'tx-baru');

      expect(find.textContaining('Pre-order sebelumnya', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('Barang Khas Nota Lama', findRichText: true),
          findsNothing,
          reason: 'belum navigasi -- masih di nota baru');

      // Tap span via recognizer (findRichText: true finds InlineSpan text).
      final richText = tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((rt) => _spanText(rt.text).contains('Pre-order sebelumnya'));
      final span = _findSpanWithText(richText.text, ' · Pre-order sebelumnya')
          as TextSpan;
      (span.recognizer as TapGestureRecognizer).onTap!();
      await tester.pumpAndSettle();

      expect(find.textContaining('Barang Khas Nota Lama', findRichText: true),
          findsOneWidget,
          reason: 'tap berhasil navigasi ke nota ASLI pre-order (tx-lama)');

      await drain(tester);
    });

    testWidgets(
        'item TANPA pre-order terbuka -> TIDAK ada span "Pre-order sebelumnya"',
        (tester) async {
      await seedTx('tx1', customerName: 'Bu Rina');
      await seedItem('tx1', 'P1', 'U1');

      await pumpReceiptApp(tester, 'tx1');

      expect(find.textContaining('Pre-order sebelumnya', findRichText: true),
          findsNothing);

      await drain(tester);
    });

    testWidgets(
        'pre-order milik nota YANG SEDANG DILIHAT ini sendiri -> TIDAK '
        'dianggap "nota lain" (tidak tampil rujukan ke diri sendiri)',
        (tester) async {
      await seedTx('tx1', customerName: 'Bu Rina');
      await seedItem('tx1', 'P1', 'U1');
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 5,
          transactionId: 'tx1');

      await pumpReceiptApp(tester, 'tx1');

      expect(find.textContaining('Pre-order sebelumnya', findRichText: true),
          findsNothing);

      await drain(tester);
    });
  });

  group('Cart bar: baris pre-order bisa diklik (LaciMejaReminder.bar)', () {
    testWidgets('produk pre-order dgn transactionId -> tampil sbg link '
        '(InkWell) yang bisa ditap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return LaciMejaReminder.bar(
              context,
              (
                titip: 0,
                ketinggalan: 0,
                pinjaman: 0,
                preorders: [
                  (
                    productName: 'Gas LPG 3kg',
                    qty: 5,
                    depositQty: 0,
                    id: 'p1',
                    transactionId: 'tx-lama',
                  ),
                ],
              ),
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gas LPG 3kg', findRichText: true),
          findsOneWidget);
      final inkWell = find.ancestor(
          of: find.textContaining('Gas LPG 3kg', findRichText: true),
          matching: find.byType(InkWell));
      expect(inkWell, findsOneWidget,
          reason: 'produk pre-order dgn transactionId harus jadi InkWell');

      // Verifikasi tappable (tidak perlu benar-benar navigasi -- ini murni
      // widget test tanpa GoRouter di tree).
      final widget = tester.widget<InkWell>(inkWell);
      expect(widget.onTap, isNotNull);
      tapped = widget.onTap != null;
      expect(tapped, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('produk pre-order TANPA transactionId (titip wadah tanpa '
        'beli apa pun) -> teks biasa, BUKAN link', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) {
            return LaciMejaReminder.bar(
              context,
              (
                titip: 0,
                ketinggalan: 0,
                pinjaman: 0,
                preorders: [
                  (
                    productName: 'Galon Aqua',
                    qty: 2,
                    depositQty: 2,
                    id: 'p1',
                    transactionId: null,
                  ),
                ],
              ),
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();

      final inkWell = find.ancestor(
          of: find.textContaining('Galon Aqua', findRichText: true),
          matching: find.byType(InkWell));
      expect(inkWell, findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });
}

InlineSpan? _findSpanWithText(InlineSpan span, String text) {
  if (span is TextSpan) {
    if (span.text == text) return span;
    if (span.children != null) {
      for (final child in span.children!) {
        final found = _findSpanWithText(child, text);
        if (found != null) return found;
      }
    }
  }
  return null;
}

String _spanText(InlineSpan span) => span.toPlainText();
