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

/// Header keranjang 2 baris: baris 1 = judul + Kosongkan; baris 2 = ikon aksi
/// (termasuk "Cetak Struk Ambil Barang" & "Tandai Semua"). Diuji di 360dp.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  late AppDatabase db;
  late ProviderContainer container;

  CartItem item(String id, String name) => CartItem(
        productId: id,
        productUnitId: '${id}_u',
        productName: name,
        unitName: 'Pcs',
        qty: 2,
        price: 10000,
        originalPrice: 10000,
        costPrice: 7000,
      );

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
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> pumpCartSheet(WidgetTester tester) async {
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
  }

  Finder tip(String t) => find.byTooltip(t);

  testWidgets(
      'Kosongkan di baris judul, ikon aksi di baris kedua; tidak '
      'overflow di 360dp', (tester) async {
    final n = container.read(cartProvider(kMainCartId).notifier);
    n.addItem(item('a', 'Produk A'));
    await pumpCartSheet(tester);

    final title = tester.getCenter(find.text('Keranjang')).dy;
    final clear = tester.getCenter(tip('Kosongkan')).dy;
    final print = tester.getCenter(tip('Cetak Struk Ambil Barang')).dy;
    final all = tester.getCenter(tip('Tandai Semua')).dy;
    expect((clear - title).abs(), lessThan(14),
        reason: 'Kosongkan sebaris dgn judul');
    expect(print, greaterThan(title + 20), reason: 'cetak di baris kedua');
    expect(all, closeTo(print, 2));
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets(
      'baris ikon kanan-ke-kiri: Tahan Pesanan paling kanan, ikon '
      'menempel tepi kanan', (tester) async {
    container
        .read(cartProvider(kMainCartId).notifier)
        .addItem(item('a', 'Produk A'));
    await pumpCartSheet(tester);

    final order = [
      'Tahan Pesanan',
      'Tempel Pesanan',
      'Bagikan Pratinjau',
      'Cetak Struk Ambil Barang',
      'Tandai Semua',
      'Pengaturan Keranjang',
    ];
    var prev = double.infinity;
    for (final t in order) {
      final x = tester.getCenter(tip(t)).dx;
      expect(x, lessThan(prev), reason: '$t harus di kiri ikon sebelumnya');
      prev = x;
    }
    expect(tester.getRect(tip('Tahan Pesanan')).right, greaterThan(360 - 32),
        reason: 'ikon paling kanan menempel tepi kanan (padding 16)');
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets(
      'Tandai Semua mencentang semua baris, lalu Hapus Tanda '
      'melepas semuanya', (tester) async {
    final n = container.read(cartProvider(kMainCartId).notifier);
    n.addItem(item('a', 'Produk A'));
    n.addItem(item('b', 'Produk B'));
    n.setChecked('a_u', true);
    await pumpCartSheet(tester);

    await tester.tap(tip('Tandai Semua'));
    await tester.pumpAndSettle();
    expect(n.current.every((c) => c.checked), isTrue);
    expect(tip('Hapus Tanda'), findsOneWidget);

    await tester.tap(tip('Hapus Tanda'));
    await tester.pumpAndSettle();
    expect(n.current.any((c) => c.checked), isFalse);
    await drain(tester);
  });

  testWidgets(
      'cetak dinonaktifkan saat keranjang kosong; tanpa printer '
      'tersimpan -> pesan "belum dikonfigurasi"', (tester) async {
    await pumpCartSheet(tester);
    final emptyBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.print_outlined));
    expect(emptyBtn.onPressed, isNull);
    await drain(tester);

    container
        .read(cartProvider(kMainCartId).notifier)
        .addItem(item('a', 'Produk A'));
    await pumpCartSheet(tester);
    await tester.tap(tip('Cetak Struk Ambil Barang'));
    await tester.pumpAndSettle();
    expect(find.text('Printer belum dikonfigurasi'), findsOneWidget);
    await drain(tester);
  });
}
