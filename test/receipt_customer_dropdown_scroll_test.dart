import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Pump manual (bukan `pumpWithFakeApp`) dgn `textScaler` diperbesar —
/// memaksa tiap baris saran jadi lebih tinggi supaya 5 saran (cap
/// `_onCustQueryChanged`) PASTI melebihi `maxHeight: 240` dropdown,
/// membuktikan kemampuan discroll-nya scr deterministik (bukan bergantung
/// kebetulan lolos/tidaknya di ukuran font default).
Future<void> pumpWithLargeText(WidgetTester tester,
    {required AppDatabase db, required Widget child}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  const fakeDevice = DeviceIdentity(
    storeUuid: 'test-store-uuid',
    storeKey: 'test-store-key',
    storeName: 'Toko Uji',
    deviceName: 'Kasir Uji',
    deviceCode: 'K1',
    deviceRole: 'owner',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      ],
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.2)),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Bug dilaporkan user: dropdown saran pelanggan (inline edit di struk
/// in-app) tidak bisa discroll. Akarnya dropdown dulu dirender `Column`
/// polos — TIDAK PUNYA mekanisme scroll SAMA SEKALI, jadi baris yang jatuh
/// di luar sisa ruang layar (terutama saat keyboard terbuka) mustahil
/// dijangkau. Fix: `ListView.builder` sungguhan dibungkus tinggi maksimum
/// (`maxHeight: 240`), pola SAMA PERSIS dgn dropdown pelanggan checkout yang
/// SUDAH BENAR (`payment_screen.dart`).
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P0', name: 'Gula Pasir'));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1', transactionId: txId, amount: 10000, method: 'tunai'));

    // 8 pelanggan dgn nama+alamat yg sama-sama mengandung "Bu" & lumayan
    // panjang — dgn cap 5 saran x ~56px/baris (nama+alamat 2 baris), totalnya
    // jelas melewati batas 240px, membuktikan dropdown SUNGGUHAN butuh
    // scroll (bukan cuma "kebetulan pas").
    for (var i = 1; i <= 8; i++) {
      await db.into(db.customers).insert(CustomersCompanion.insert(
            id: 'c$i',
            name: 'Bu Pelanggan Nomor $i',
            address: Value('Jl. Alamat Contoh Sangat Panjang No. $i'),
          ));
    }
  });
  tearDown(() async => db.close());

  Future<void> openEditor(WidgetTester tester,
      {bool largeText = false}) async {
    if (largeText) {
      await pumpWithLargeText(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));
    } else {
      await pumpWithFakeApp(tester,
          db: db, child: const ReceiptScreen(transactionId: txId));
    }
    await tester.tap(find.text('Pelanggan: '));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Bu');
    await tester.pumpAndSettle();
  }

  testWidgets(
      'dropdown saran dibungkus tinggi maksimum & dirender via ListView '
      'sungguhan (bukan Column polos tanpa mekanisme scroll)', (tester) async {
    await openEditor(tester);

    // Semua 5 saran (cap) harus ketemu -- ListView.builder membangun semua
    // itemnya krn shrinkWrap+maxHeight terbatas, TIDAK lazy di luar viewport
    // pendek spt ListView biasa (item count kecil, ini valid).
    expect(find.textContaining('Bu Pelanggan Nomor', findRichText: true).evaluate().length,
        greaterThanOrEqualTo(5),
        reason: 'cap saran = 5 (lihat _onCustQueryChanged)');

    final container = tester.widget<Container>(find
        .ancestor(
            of: find.textContaining('Bu Pelanggan Nomor 1', findRichText: true),
            matching: find.byType(Container))
        .first);
    expect(container.constraints?.maxHeight, 240,
        reason: 'dropdown WAJIB dibatasi tinggi maksimum supaya ListView di '
            'dalamnya punya alasan (& kemampuan) utk discroll');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('dropdown SUNGGUHAN bisa discroll -- drag ke atas '
      'menggeser posisi scroll-nya', (tester) async {
    // textScaler diperbesar supaya 5 saran (cap) PASTI melebihi maxHeight
    // 240 scr deterministik, tidak bergantung kebetulan lolos/tidaknya
    // dgn ukuran font default.
    await openEditor(tester, largeText: true);

    final listFinder = find.descendant(
        of: find.byWidgetPredicate((w) =>
            w is Container && w.constraints?.maxHeight == 240),
        matching: find.byType(ListView));
    expect(listFinder, findsOneWidget);

    final scrollableFinder = find.descendant(
        of: listFinder, matching: find.byType(Scrollable));
    final scrollableState =
        tester.state<ScrollableState>(scrollableFinder);
    expect(scrollableState.position.pixels, 0);
    expect(scrollableState.position.maxScrollExtent, greaterThan(0),
        reason: 'dgn teks diperbesar, 5 saran WAJIB melebihi maxHeight 240 '
            '-- kalau tidak, dropdown belum genuinely "kelebihan konten" '
            'yang butuh discroll di skenario test ini');

    await tester.drag(listFinder, const Offset(0, -150));
    await tester.pumpAndSettle();

    expect(scrollableState.position.pixels, greaterThan(0),
        reason: 'drag ke atas harus MENGGESER posisi scroll dropdown -- '
            'sebelum fix, Column polos tidak punya posisi scroll sama sekali');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
