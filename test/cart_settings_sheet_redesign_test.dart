import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/theme_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Redesain "Pengaturan Keranjang" — dari `AlertDialog` generik ke bottom
/// sheet custom (gaya sama dgn "Pengaturan Struk" `receipt_screen.dart`).
/// Isi lama (posisi checkbox, konfirmasi minus qty) HARUS tetap ada, PLUS
/// toggle baru "Tampilkan chip Kategori Harga per-produk".
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
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
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  testWidgets(
      'sheet Pengaturan Keranjang terbuka sbg bottom sheet (bukan '
      'AlertDialog) & semua opsi ada, termasuk toggle chip kategori baru',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
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

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan Keranjang'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'redesain HARUS bottom sheet, bukan AlertDialog generik lagi');

    // Isi LAMA tetap ada.
    expect(find.text('Letak checkbox verifikasi'), findsOneWidget);
    for (final pos in CartCheckboxPosition.values) {
      expect(find.text(pos.label), findsOneWidget);
    }
    expect(find.text('Konfirmasi sebelum kurangi qty'), findsOneWidget);

    // Toggle BARU.
    expect(find.text('Tampilkan chip Kategori Harga per-produk'),
        findsOneWidget);
    final sw = tester.widget<SwitchListTile>(find.widgetWithText(
        SwitchListTile, 'Tampilkan chip Kategori Harga per-produk'));
    expect(sw.value, isTrue, reason: 'default ON');

    await drain(tester);
  });

  testWidgets('toggle baru di sheet mengubah cartPriceCategoryChipsProvider',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
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
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(container.read(cartPriceCategoryChipsProvider), isTrue);

    await tester.tap(find.widgetWithText(
        SwitchListTile, 'Tampilkan chip Kategori Harga per-produk'));
    await tester.pumpAndSettle();

    expect(container.read(cartPriceCategoryChipsProvider), isFalse);

    await drain(tester);
  });
}
