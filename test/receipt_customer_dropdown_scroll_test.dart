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
/// in-app) tidak bisa discroll — DUA akar penyebab, dilaporkan & diperbaiki
/// di 2 putaran:
///  1. Dropdown dulu dirender `Column` polos — TIDAK PUNYA mekanisme scroll
///     SAMA SEKALI. Fix: `ListView.builder` sungguhan dibungkus tinggi
///     maksimum (`maxHeight: 240`), pola SAMA PERSIS dgn dropdown pelanggan
///     checkout yang SUDAH BENAR (`payment_screen.dart`).
///  2. SETELAH #1 diperbaiki, user MASIH lapor "tidak bisa discroll" —
///     ternyata `_onCustQueryChanged` memotong hasil pencarian `.take(5)`,
///     jadi pelanggan ke-6+ yang cocok TIDAK PERNAH masuk `_custSuggestions`
///     sama sekali. Scroll apa pun mustahil memunculkannya krn datanya sudah
///     dibuang SEBELUM sempat dirender — dari sudut pandang user, efeknya
///     identik dgn "dropdown tidak bisa discroll" walau widget-nya sendiri
///     sudah genuinely scrollable. Fix: cap dibuang, samakan dgn
///     `payment_screen.dart::_searchCustomers` yang SUDAH BENAR menampilkan
///     SEMUA hasil pencarian tanpa potongan.
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
    // panjang. Sengaja LEBIH dari 5 (bekas cap lama yg sudah dibuang) supaya
    // kasus "pelanggan ke-6+" ikut teruji, dan totalnya jg melewati batas
    // 240px, membuktikan dropdown SUNGGUHAN butuh scroll (bukan cuma
    // "kebetulan pas").
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

    // SEMUA 8 (bukan lagi dipotong 5) harus masuk sbg ITEM DATA `ListView`,
    // walau yg SUNGGUHAN dirender di layar cuma sebagian (lazy-build khas
    // ListView, sisanya baru dibangun begitu di-scroll ke situ — lihat test
    // "pelanggan ke-6+" di bawah utk pembuktian scroll-nya).
    final dropdownListFinder = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxHeight == 240),
        matching: find.byType(ListView));
    final listView = tester.widget<ListView>(dropdownListFinder);
    final delegate = listView.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, 8,
        reason: 'cap `.take(5)` lama sudah dibuang -- SEMUA hasil pencarian '
            'harus masuk `_custSuggestions`, bukan cuma 5 pertama');

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

  testWidgets(
      'BUG NYATA dilaporkan user (putaran ke-2): pelanggan ke-6+ yang cocok '
      'HARUS tetap muncul di saran -- bukan dibuang diam-diam sebelum '
      'sempat dirender', (tester) async {
    await openEditor(tester);

    final dropdownListFinder = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is Container && w.constraints?.maxHeight == 240),
        matching: find.byType(ListView));

    // Baris awal (belum di-scroll) sudah harus ketemu.
    expect(find.textContaining('Bu Pelanggan Nomor 1', findRichText: true),
        findsOneWidget);

    // Scroll dropdown sampai mentok bawah -- pelanggan ke-6+ (dulu terpotong
    // `.take(5)`, TIDAK PERNAH ada di data sama sekali) harus TERLIHAT
    // setelah discroll, bukan cuma "ada di data tapi tidak pernah bisa
    // dijangkau layar".
    await tester.drag(dropdownListFinder, const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bu Pelanggan Nomor 8', findRichText: true),
        findsOneWidget,
        reason: 'pelanggan ke-8 wajib bisa dijangkau via scroll -- dulu '
            'terpotong `.take(5)`, tidak pernah masuk data sama sekali');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('dropdown SUNGGUHAN bisa discroll -- drag ke atas '
      'menggeser posisi scroll-nya', (tester) async {
    // textScaler diperbesar supaya 8 saran PASTI melebihi maxHeight 240
    // scr deterministik, tidak bergantung kebetulan lolos/tidaknya dgn
    // ukuran font default.
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
