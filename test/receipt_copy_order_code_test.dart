import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user) — tombol "Salin Kode Pesanan" di Struk (nota
/// LAMA/SUDAH SELESAI), supaya kasir bisa membuat ulang pesanan yang sama
/// persis (mis. pelanggan langganan) lewat "Tempel Pesanan" tanpa input
/// manual satu-satu. Dipakai `#PSN:...` yang SUDAH ADA (`OrderParserService.
/// encodeHandoff`), dipanggil dari `_copyOrderCode` di `receipt_screen.dart`.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Mock manual Clipboard — WAJIB (lihat CLAUDE.md §Gotcha): tanpa handler
  /// ini, `Clipboard.getData()` MENGGANTUNG SELAMANYA di environment test
  /// ini (bukan gagal cepat).
  String? mockClipboard(WidgetTester tester) {
    String? store;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        store = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return {'text': store};
      }
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
    return store;
  }

  Future<void> seedProduct(String id, String name, {String? parentId}) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
          parentProductId: Value(parentId),
        ));
  }

  Future<void> seedUnit(String id, String productId) async {
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: id,
          productId: productId,
        ));
  }

  Future<void> seedTx({
    required String status,
    required List<TransactionItemsCompanion> items,
  }) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: status,
          total: 20000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    for (final it in items) {
      await db.into(db.transactionItems).insert(it);
    }
  }

  testWidgets(
      '"Salin Kode Pesanan" — nota biasa (induk+varian): menyalin #PSN: '
      'dgn productUnitId+qty benar, TANPA flag harga (trustPrices: false)',
      (tester) async {
    await seedProduct('P1', 'Pop Ice');
    await seedProduct('P2', 'Pop Ice Coklat', parentId: 'P1');
    await seedUnit('U1', 'P1');
    await seedUnit('U2', 'P2');
    await seedTx(status: 'lunas', items: [
      TransactionItemsCompanion.insert(
        id: 'ti1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 3,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 15000,
      ),
      TransactionItemsCompanion.insert(
        id: 'ti2',
        transactionId: 'tx1',
        productId: 'P2',
        productUnitId: 'U2',
        qty: 2,
        priceAtSale: 5500,
        originalPrice: 5500,
        subtotal: 11000,
      ),
    ]);

    mockClipboard(tester);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.byTooltip('Salin Kode Pesanan'), findsOneWidget);
    await tester.tap(find.byTooltip('Salin Kode Pesanan'));
    await tester.pump();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text ?? '';
    expect(text, contains('#PSN:'));
    expect(text, contains('U1=3'));
    expect(text, contains('U2=2'));
    expect(text, isNot(contains('|p=')),
        reason: 'trustPrices: false — harga nota lama tidak boleh ikut, '
            'harus di-resolve fresh dari harga TERKINI di sisi penerima');
    expect(find.text('Kode pesanan disalin'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      '"Salin Kode Pesanan" — item yang sudah DIRETUR PENUH tidak ikut '
      'disalin (qty net <= 0, bukan qty asli yg sudah tidak relevan)',
      (tester) async {
    await seedProduct('P1', 'Gula Pasir');
    await seedProduct('P2', 'Beras');
    await seedUnit('U1', 'P1');
    await seedUnit('U2', 'P2');
    await seedTx(status: 'lunas', items: [
      TransactionItemsCompanion.insert(
        id: 'ti1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 2,
        priceAtSale: 15000,
        originalPrice: 15000,
        subtotal: 30000,
      ),
      // Baris retur PENUH utk P1/U1 — menetralkan qty=2 di atas.
      TransactionItemsCompanion.insert(
        id: 'ti1r',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: -2,
        priceAtSale: 15000,
        originalPrice: 15000,
        subtotal: -30000,
        returnedAt: Value(DateTime.now()),
      ),
      TransactionItemsCompanion.insert(
        id: 'ti2',
        transactionId: 'tx1',
        productId: 'P2',
        productUnitId: 'U2',
        qty: 5,
        priceAtSale: 12000,
        originalPrice: 12000,
        subtotal: 60000,
      ),
    ]);

    mockClipboard(tester);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    await tester.tap(find.byTooltip('Salin Kode Pesanan'));
    await tester.pump();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text ?? '';
    expect(text, isNot(contains('U1=')),
        reason: 'item sudah diretur penuh (qty net 0) — tidak boleh ikut');
    expect(text, contains('U2=5'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tombol "Salin Kode Pesanan" TIDAK muncul di nota berstatus void',
      (tester) async {
    await seedProduct('P1', 'Gula Pasir');
    await seedUnit('U1', 'P1');
    await seedTx(status: 'void', items: [
      TransactionItemsCompanion.insert(
        id: 'ti1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 2,
        priceAtSale: 15000,
        originalPrice: 15000,
        subtotal: 30000,
      ),
    ]);

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.byTooltip('Salin Kode Pesanan'), findsNothing,
        reason: 'nota void batal — tidak valid dijadikan basis pesanan baru');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      '"Salin Kode Pesanan" — semua item net 0 (semua diretur habis): '
      'tombol tetap tampil tapi SnackBar "Tidak ada item untuk disalin"',
      (tester) async {
    await seedProduct('P1', 'Gula Pasir');
    await seedUnit('U1', 'P1');
    await seedTx(status: 'lunas', items: [
      TransactionItemsCompanion.insert(
        id: 'ti1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 2,
        priceAtSale: 15000,
        originalPrice: 15000,
        subtotal: 30000,
      ),
      TransactionItemsCompanion.insert(
        id: 'ti1r',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: -2,
        priceAtSale: 15000,
        originalPrice: 15000,
        subtotal: -30000,
        returnedAt: Value(DateTime.now()),
      ),
    ]);

    mockClipboard(tester);
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: 'tx1'));

    await tester.tap(find.byTooltip('Salin Kode Pesanan'));
    await tester.pump();

    expect(find.text('Tidak ada item untuk disalin'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
