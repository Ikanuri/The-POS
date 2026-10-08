import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/enter_animation.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Keranjang: baris yang BARU masuk setelah sheet terbuka beranimasi masuk
/// (tinggi + fade); baris awal tidak.
void main() {
  CartItem item(String id, String name) => CartItem(
        productId: 'p$id',
        productUnitId: 'u$id',
        productName: name,
        unitName: 'Pcs',
        qty: 1,
        price: 15000,
        originalPrice: 15000,
        costPrice: 10000,
      );

  testWidgets('baris awal langsung penuh; baris baru memudar + membuka tinggi',
      (tester) async {
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
    final notifier = container.read(cartProvider(kMainCartId).notifier);
    notifier.addItem(item('1', 'Gula'));

    await tester.binding.setSurfaceSize(const Size(360, 800));
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
                    child: const Text('buka')))),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    EnterAnimation rowOf(String name) => tester.widget<EnterAnimation>(find
        .ancestor(of: find.text(name), matching: find.byType(EnterAnimation))
        .first);
    expect(find.text('Gula'), findsOneWidget);
    expect(rowOf('Gula').enabled, isFalse); // baris awal: tanpa animasi

    notifier.addItem(item('2', 'Kopi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(rowOf('Kopi').enabled, isTrue);
    final fade = tester
        .widget<FadeTransition>(find
            .descendant(
                of: find.ancestor(
                    of: find.text('Kopi'),
                    matching: find.byType(EnterAnimation)).first,
                matching: find.byType(FadeTransition))
            .first)
        .opacity
        .value;
    expect(fade, inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.text('Kopi'), findsOneWidget);
    expect(find.text('Gula'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  Future<(ProviderContainer, CartNotifier)> openSheet(WidgetTester tester,
      {bool reduced = false}) async {
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
    final notifier = container.read(cartProvider(kMainCartId).notifier);
    notifier.addItem(item('1', 'Gula'));
    notifier.addItem(item('2', 'Kopi'));
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (ctx) => ElevatedButton(
                    onPressed: () => showModalBottomSheet(
                        context: ctx,
                        isScrollControlled: true,
                        builder: (_) => const CartSheet()),
                    child: const Text('buka')))),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    return (container, notifier);
  }

  testWidgets('baris dihapus: tetap tampil sbg hantu yang menutup + memudar, '
      'lalu hilang; baris lain tetap', (tester) async {
    final (_, notifier) = await openSheet(tester);
    expect(find.text('Gula'), findsOneWidget);
    expect(find.text('Kopi'), findsOneWidget);

    notifier.removeItem('u1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Masih terlihat (sedang beranimasi keluar) dgn opasitas < 1.
    expect(find.text('Gula'), findsOneWidget);
    final fade = tester
        .widget<FadeTransition>(find
            .descendant(
                of: find.byType(ExitAnimation),
                matching: find.byType(FadeTransition))
            .first)
        .opacity
        .value;
    expect(fade, inExclusiveRange(0, 1));
    // Hantu tidak bisa disentuh.
    expect(
        find.ancestor(
            of: find.text('Gula'), matching: find.byType(IgnorePointer)),
        findsWidgets);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Gula'), findsNothing);
    expect(find.text('Kopi'), findsOneWidget);
    expect(find.byType(ExitAnimation), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('animasi dimatikan: baris yang dihapus langsung hilang',
      (tester) async {
    final (_, notifier) = await openSheet(tester, reduced: true);
    notifier.removeItem('u1');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Gula'), findsNothing);
    expect(find.byType(ExitAnimation), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('baris dihapus lalu ditambah lagi cepat: tidak ada hantu dobel',
      (tester) async {
    final (_, notifier) = await openSheet(tester);
    notifier.removeItem('u1');
    await tester.pump();
    notifier.addItem(item('1', 'Gula'));
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('Gula'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Gula'), findsOneWidget);
    expect(find.byType(ExitAnimation), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
