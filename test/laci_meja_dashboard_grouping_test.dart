import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';

/// Item 52 susulan (permintaan user, screenshot device asli): barang
/// titip/ketinggalan dari NOTA YANG SAMA harus dikumpulkan jadi SATU
/// "frame" (Card), bukan baris rata terpisah — dan tiap baris menampilkan
/// qty + satuan produknya.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/laci-meja',
      routes: [
        GoRoute(
          path: '/laci-meja',
          builder: (_, __) => const LaciMejaDashboardScreen(),
        ),
        GoRoute(
          path: '/kasir/struk/:txId',
          builder: (_, state) => Scaffold(
              body: Text('Layar Struk ${state.pathParameters['txId']}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> seedTransaction(String id) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
  }

  testWidgets(
      '2 barang dari NOTA SAMA dikumpulkan jadi 1 Card (frame); nota lain '
      'jadi Card terpisah', (tester) async {
    await seedTransaction('tx1');
    await seedTransaction('tx2');
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 2,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 10000));
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Galon Aqua',
        jenis: 'titip',
        transactionItemId: 'i1');
    await db.addLeftBehindItem(
        id: 'l2', transactionId: 'tx1', itemName: 'Payung', jenis: 'ketinggalan');
    await db.addLeftBehindItem(
        id: 'l3', transactionId: 'tx2', itemName: 'Topi', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(2),
        reason: '2 nota berbeda -> 2 frame (Card), bukan 3 baris rata');

    // Card pertama (tx1) berisi 2 ListTile (Galon Aqua + Payung).
    final firstCard = find.byType(Card).first;
    expect(
        find.descendant(of: firstCard, matching: find.byType(ListTile)),
        findsNWidgets(2),
        reason: '2 barang dari nota yg SAMA harus 1 frame berisi 2 baris');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'barang yang tertaut transactionItemId menampilkan qty+satuan; yang '
      'tidak tertaut (entri lama) tidak menampilkan apa pun tambahan',
      (tester) async {
    await seedTransaction('tx1');
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Galon Aqua Produk'));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(99), name: 'Pak'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1',
        productId: 'P1',
        isBaseUnit: const Value(true),
        unitTypeId: const Value(99)));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 3,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 15000));

    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Galon Aqua',
        jenis: 'titip',
        transactionItemId: 'i1');
    await db.addLeftBehindItem(
        id: 'l2',
        transactionId: 'tx1',
        itemName: 'Payung Lama',
        jenis: 'ketinggalan');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Galon Aqua ·'), findsOneWidget,
        reason: 'barang tertaut transactionItemId harus tampilkan qty+satuan');
    expect(find.text('Payung Lama'), findsOneWidget,
        reason: 'entri lama tanpa tautan tetap tampil apa adanya, tanpa qty');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tombol "Ambil" (redesain minimalis) menandai barang diambil',
      (tester) async {
    await seedTransaction('tx1');
    await db.addLeftBehindItem(
        id: 'l1', transactionId: 'tx1', itemName: 'Galon Aqua', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Sudah Diambil'), findsNothing,
        reason: 'label lama dihapus, redesain minimalis');
    expect(find.text('Ambil'), findsOneWidget);

    await tester.tap(find.text('Ambil'));
    await tester.pumpAndSettle();

    expect(find.text('Galon Aqua'), findsNothing,
        reason: 'setelah diambil, baris hilang dari daftar yg menggantung');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  group('Pre-order (permintaan user putaran terbaru)', () {
    Future<void> tapPreorderTab(WidgetTester tester) async {
      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        '2 produk pre-order dari NOTA SAMA jadi 1 Card, header nama '
        'pelanggan (bold), tiap baris "[qty] [produk] - [jaminan]"',
        (tester) async {
      await seedTransaction('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Galon Aqua'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.into(db.products)
          .insert(ProductsCompanion.insert(id: 'P2', name: 'Tabung Gas'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U2', productId: 'P2', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Artia',
          qtyOrdered: 2,
          transactionId: 'tx1');
      await db.addPreorderEntry(
          id: 'p2',
          productId: 'P2',
          productUnitId: 'U2',
          customerName: 'Bu Artia',
          qtyOrdered: 1,
          depositQty: 1,
          transactionId: 'tx1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPreorderTab(tester);

      expect(find.byType(Card), findsOneWidget,
          reason: '2 produk pre-order NOTA SAMA -> 1 frame, tidak kocar-kacir');
      expect(find.text('Bu Artia'), findsOneWidget,
          reason: 'header nama pelanggan tampil SEKALI per grup');
      final header = tester.widget<Text>(find.text('Bu Artia'));
      expect(header.style?.fontWeight, FontWeight.w700,
          reason: 'header nama pelanggan harus bold');
      expect(find.textContaining('2 Galon Aqua'), findsOneWidget);
      expect(find.textContaining('1 Tabung Gas - 1 jaminan'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('Pre-order: pencarian & statistik (permintaan user)', () {
    Future<void> seedPreorders() async {
      await seedTransaction('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Tabung Gas'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P2', name: 'Galon Aqua'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U2', productId: 'P2', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'po1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Artia',
          qtyOrdered: 2,
          depositQty: 2,
          transactionId: 'tx1');
      await db.addPreorderEntry(
          id: 'po2',
          productId: 'P2',
          productUnitId: 'U2',
          customerName: 'Pak Budi',
          qtyOrdered: 3,
          depositQty: 1,
          transactionId: 'tx1');
    }

    Future<void> openPreorderTab(WidgetTester tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();
    }

    testWidgets('statistik memisahkan total produk vs total jaminan',
        (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      expect(find.text('Total produk'), findsOneWidget);
      expect(find.text('Total jaminan'), findsOneWidget);
      // qty 2 + 3 = 5 produk; jaminan 2 + 1 = 3 wadah — SENGAJA dua angka
      // terpisah, bukan dijumlahkan jadi satu.
      expect(find.text('5'), findsOneWidget, reason: 'total produk dipesan');
      expect(find.text('3'), findsOneWidget, reason: 'total jaminan dititip');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('cari by NAMA PELANGGAN menyaring daftar & statistik',
        (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      await tester.enterText(find.byType(TextField), 'Budi');
      await tester.pumpAndSettle();

      expect(find.text('Pak Budi'), findsOneWidget);
      expect(find.text('Bu Artia'), findsNothing);
      // Statistik ikut tersaring: sisa 3 produk & 1 jaminan.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('cari by NAMA PRODUK juga bisa', (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      await tester.enterText(find.byType(TextField), 'galon');
      await tester.pumpAndSettle();

      expect(find.text('Pak Budi'), findsOneWidget,
          reason: 'Galon Aqua dipesan Pak Budi');
      expect(find.text('Bu Artia'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('kata kunci tanpa hasil -> pesan kosong, bukan daftar penuh',
        (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.textContaining('Tidak ada yang cocok'), findsOneWidget);
      expect(find.text('Bu Artia'), findsNothing);
      expect(find.text('Pak Budi'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('Pinjaman (permintaan user putaran terbaru — group by pelanggan)', () {
    Future<void> tapPinjamanTab(WidgetTester tester) async {
      await tester.tap(find.text('Pinjaman'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'pinjaman dari 2 NOTA BERBEDA tapi pelanggan SAMA dikumpulkan jadi '
        '1 Card; tiap baris tetap tertaut ke transactionId-nya sendiri',
        (tester) async {
      await seedTransaction('tx1');
      await seedTransaction('tx2');
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'c1', name: 'Pak Budi'));
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: 'tx1',
          itemName: 'Galon Aqua',
          qty: 2,
          customerId: 'c1',
          customerNameText: 'Pak Budi');
      await db.addBorrowedItem(
          id: 'b2',
          transactionId: 'tx2',
          itemName: 'Tabung Gas',
          qty: 1,
          customerId: 'c1',
          customerNameText: 'Pak Budi');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPinjamanTab(tester);

      expect(find.byType(Card), findsOneWidget,
          reason: 'satu pelanggan, 2 nota berbeda -> tetap 1 grup');
      expect(find.text('Pak Budi'), findsOneWidget,
          reason: 'header nama pelanggan tampil SEKALI, bukan per baris');
      expect(
          find.descendant(
              of: find.byType(Card), matching: find.byType(ListTile)),
          findsNWidgets(2),
          reason: '2 baris barang (dari 2 nota berbeda) di dalam 1 grup');

      // Tap baris Galon Aqua -> redirect ke tx1 (BUKAN tx2), walau satu grup.
      await tester.tap(find.text('Galon Aqua'));
      await tester.pumpAndSettle();
      expect(find.text('Layar Struk tx1'), findsOneWidget,
          reason: 'tiap baris redirect ke transactionId MILIKNYA sendiri');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('pelanggan BERBEDA -> Card terpisah', (tester) async {
      await seedTransaction('tx1');
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: 'tx1',
          itemName: 'Galon A',
          qty: 1,
          customerNameText: 'Ani');
      await db.addBorrowedItem(
          id: 'b2',
          transactionId: 'tx1',
          itemName: 'Galon B',
          qty: 1,
          customerNameText: 'Budi');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPinjamanTab(tester);

      expect(find.byType(Card), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });
}
