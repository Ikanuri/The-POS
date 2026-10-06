import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_preview_paper.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Pratinjau keranjang: catatan item + blok Pra-Bayar (logika sama dgn footer
/// keranjang: saldo = terkunci - kembalian sudah diambil) + toggle.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 2,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
    itemNote: 'bungkus rapi',
  );

  Future<void> paper(WidgetTester tester, CartPreviewPaper w) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: SingleChildScrollView(child: w))));
    await tester.pump();
  }

  CartPreviewPaper make({
    List<({String label, int amount})> lines = const [],
    int taken = 0,
    int debt = 0,
    int total = 30000,
  }) =>
      CartPreviewPaper(
        items: const [item],
        effectiveQtyOf: (i) => i.qty,
        totalAmount: total,
        customerName: 'Umum',
        storeName: 'Toko',
        storeAddress: '',
        storePhone: '',
        prabayarLines: lines,
        changeTakenTotal: taken,
        debtSettlementTotal: debt,
      );

  testWidgets('catatan item tampil di pratinjau', (tester) async {
    await paper(tester, make());
    expect(find.text('Catatan: bungkus rapi'), findsOneWidget);
    expect(find.textContaining('Sisa Bayar'), findsNothing,
        reason: 'tanpa Pra-Bayar tidak ada blok sisa');
  });

  testWidgets('Pra-Bayar kurang dari total -> Sisa Bayar', (tester) async {
    await paper(
        tester, make(lines: [(label: 'Pra-Bayar Tunai', amount: 10000)]));
    expect(find.text('Pra-Bayar Tunai'), findsOneWidget);
    expect(find.text('Sisa Bayar'), findsOneWidget);
    expect(find.text('Rp 20.000'), findsOneWidget);
  });

  testWidgets(
      'Pra-Bayar lebih dari total + kembalian sudah diambil -> saldo & '
      'kembalian dihitung dari saldo', (tester) async {
    await paper(tester,
        make(lines: [(label: 'Pra-Bayar Tunai', amount: 50000)], taken: 5000));
    expect(find.text('Kembalian sudah diambil'), findsOneWidget);
    expect(find.text('Saldo Pra-Bayar'), findsOneWidget);
    // saldo 45.000 - total 30.000 = kembalian 15.000
    expect(find.text('Kembalian'), findsOneWidget);
    expect(find.text('Rp 15.000'), findsOneWidget);
  });

  testWidgets('Lunasi Hutang ikut menaikkan total tagihan', (tester) async {
    await paper(tester,
        make(lines: [(label: 'Pra-Bayar Tunai', amount: 30000)], debt: 20000));
    expect(find.text('+ Lunasi Hutang'), findsOneWidget);
    expect(find.text('Total Tagihan'), findsOneWidget);
    expect(find.text('Sisa Bayar'), findsOneWidget);
    expect(find.text('Rp 20.000'), findsWidgets);
  });

  testWidgets('toggle "Tampilkan Pra-Bayar" default ON & bisa dimatikan',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'u',
          storeKey: 'k',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(item);
    container.read(cartPrabayarProvider(kMainCartId).notifier).add(
        PrabayarEntry(
            id: 'e1',
            amount: 10000,
            method: 'tunai',
            lockedAt: DateTime(2026, 10, 6)));
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const CartSheet()),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bagikan Pratinjau'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cart-preview-prabayar-toggle')),
        findsOneWidget);
    expect(find.text('Pra-Bayar Tunai'), findsOneWidget, reason: 'default ON');
    expect(find.text('Sisa Bayar'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('cart-preview-prabayar-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Pra-Bayar Tunai'), findsNothing);
    expect(find.text('Sisa Bayar'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
