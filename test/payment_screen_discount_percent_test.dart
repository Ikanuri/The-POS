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
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Fase A "Kategori Harga" — dialog "Ubah Total" di layar bayar kini punya
/// 2 mode: "Nominal" (perilaku ASLI, tidak berubah) & "Diskon %" (baru).
/// Test level UI (`ProviderContainer` manual, pola sama dgn
/// `payment_screen_buttons_test.dart`) — lihat CLAUDE.md §Metode Test poin 2.
const _item = CartItem(
  productId: 'p1',
  productUnitId: 'u1',
  productName: 'Barang A',
  unitName: 'Pcs',
  qty: 1,
  price: 317000,
  originalPrice: 317000,
  costPrice: 200000,
);

void main() {
  Future<AppDatabase> pumpPaymentScreen(WidgetTester tester,
      {Map<String, Object> initialPrefs = const {}}) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(_item);

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: PaymentScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets(
      'mode Nominal (default) tetap bekerja sama persis seperti sebelumnya',
      (tester) async {
    await pumpPaymentScreen(tester);

    expect(find.text('Total'), findsOneWidget);
    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();

    expect(find.text('Ubah Total'), findsOneWidget);
    expect(find.text('Nominal'), findsOneWidget);
    expect(find.text('Diskon %'), findsOneWidget);
    // Default mode: Nominal — field nominal muncul, bukan field %.
    expect(find.byKey(const Key('editTotal_nominalField')), findsOneWidget);
    expect(find.byKey(const Key('editTotal_percentField')), findsNothing);

    await tester.enterText(
        find.byKey(const Key('editTotal_nominalField')), '250000');
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(find.textContaining(formatRupiah(250000)), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'mode Diskon % : 5% dari 317.000, kelipatan 500, arah Turun -> 301.000',
      (tester) async {
    await pumpPaymentScreen(tester);

    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diskon %'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('editTotal_percentField')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('editTotal_percentField')), '5');
    await tester.pumpAndSettle();

    // Pilih kelipatan 500 lewat dropdown (default sudah 500, tapi tegaskan).
    await tester.tap(find.byKey(const Key('editTotal_multipleDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('500').last);
    await tester.pumpAndSettle();

    // Pilih arah Turun.
    await tester.tap(find.byKey(const Key('editTotal_dirDown')));
    await tester.pumpAndSettle();

    // Preview live menampilkan hasil dibulatkan Rp 301.000.
    expect(find.textContaining('301.000'), findsWidgets);

    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(find.textContaining(formatRupiah(301000)), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'mode Diskon % : kelipatan 1.000 arah Naik -> 5% dari 317.000 jadi 302.000',
      (tester) async {
    await pumpPaymentScreen(tester);

    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diskon %'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('editTotal_percentField')), '5');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editTotal_multipleDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.000').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editTotal_dirUp')));
    await tester.pumpAndSettle();

    // 317000 - 15850 = 301150 -> naik ke kelipatan 1000 = 302000.
    expect(find.textContaining('302.000'), findsWidgets);

    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(find.textContaining(formatRupiah(302000)), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'preferensi kelipatan+arah TERAKHIR tersimpan & ke-restore lain kali dialog dibuka',
      (tester) async {
    await pumpPaymentScreen(tester);

    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diskon %'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('editTotal_percentField')), '10');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('editTotal_multipleDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.000').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editTotal_dirUp')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    // Buka lagi dialog "Ubah Total" — preferensi kelipatan 1.000 & arah Naik
    // harus sudah ke-restore dari SharedPreferences, TANPA perlu diatur ulang.
    await tester.tap(find.text('Total'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diskon %'));
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<int>>(
        find.byKey(const Key('editTotal_multipleDropdown')));
    expect(dropdown.value, 1000);

    final upChip =
        tester.widget<ChoiceChip>(find.byKey(const Key('editTotal_dirUp')));
    expect(upChip.selected, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
