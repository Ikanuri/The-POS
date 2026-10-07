import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Sheet "Pengaturan Keranjang": terbuka 3/4 layar, bisa ditarik penuh, dan
/// TETAP bisa ditutup dengan swipe turun (dulu SingleChildScrollView biasa
/// menelan gestur turun).
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'a',
          productUnitId: 'a_u',
          productName: 'Produk A',
          unitName: 'Pcs',
          qty: 1,
          price: 1000,
          originalPrice: 1000,
          costPrice: 500,
        ));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> openSettings(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const CartSheet(cartId: kMainCartId),
                ),
                child: const Text('buka keranjang'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka keranjang'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pengaturan Keranjang'));
    await tester.pumpAndSettle();
  }

  Finder title() => find.text('Pengaturan Keranjang');

  double sheetTop(WidgetTester tester) =>
      tester.getTopLeft(find.byIcon(Icons.tune)).dy;

  testWidgets('terbuka sekitar 3/4 layar (bukan penuh)', (tester) async {
    await openSettings(tester);
    expect(title(), findsOneWidget);
    // 3/4 dari 800 = sheet mulai di y~200; ikon judul sedikit di bawahnya.
    final top = sheetTop(tester);
    expect(top, greaterThan(180));
    expect(top, lessThan(260));
    await drain(tester);
  });

  testWidgets('swipe turun dari judul menutup sheet', (tester) async {
    await openSettings(tester);
    await tester.fling(title(), const Offset(0, 500), 1500);
    await tester.pumpAndSettle();
    expect(title(), findsNothing);
    await drain(tester);
  });

  testWidgets('ditarik penuh, lalu tetap bisa di-swipe turun untuk menutup',
      (tester) async {
    await openSettings(tester);
    // Tarik pegangan/judul ke atas: sheet melebar (bukan isi yang tergulir).
    await tester.drag(find.byIcon(Icons.tune), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(sheetTop(tester), lessThan(100), reason: 'sheet melebar ke penuh');
    // Dua kali swipe turun: penuh -> 3/4/lebih rendah -> tertutup.
    for (var i = 0; i < 3 && title().evaluate().isNotEmpty; i++) {
      await tester.fling(find.byIcon(Icons.tune), const Offset(0, 600), 2000);
      await tester.pumpAndSettle();
    }
    expect(title(), findsNothing);
    await drain(tester);
  });
}
