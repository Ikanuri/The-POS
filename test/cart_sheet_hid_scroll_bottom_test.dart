import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet_scan_signal.dart';

/// Scan HID: produk masuk ke keranjang -> daftar HARUS menggulir sampai
/// MENTOK bawah (item terbaru terlihat penuh), baik saat keranjang dibuka oleh
/// scan pertama maupun saat sudah terbuka dan item baru masuk (baris baru
/// membuka tingginya dgn animasi — gulir tidak boleh berhenti sebelum itu
/// selesai).
void main() {
  scanExistingTests();
  setUp(() => CartSheetScrollTestSeam.clear());
  tearDown(() => CartSheetScrollTestSeam.clear());

  CartItem item(int i) => CartItem(
        productId: 'P$i',
        productUnitId: 'U$i',
        productName: 'Produk ke-$i',
        unitName: 'Pcs',
        qty: 1,
        price: 1000,
        originalPrice: 1000,
        costPrice: 800,
      );

  Future<ProviderContainer> pump(WidgetTester tester, AppDatabase db,
      {required bool hid, int count = 25}) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Owner',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    final n = container.read(cartProvider(kMainCartId).notifier);
    for (var i = 0; i < count; i++) {
      n.addItem(item(i));
    }
    await tester.binding.setSurfaceSize(const Size(360, 700));
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
                builder: (_) => CartSheet(scrollToBottom: hid),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    return container;
  }

  double offset(WidgetTester t) =>
      t.widget<ListView>(find.byType(ListView).first).controller!.offset;
  double maxExtent(WidgetTester t) => t
      .widget<ListView>(find.byType(ListView).first)
      .controller!
      .position
      .maxScrollExtent;

  testWidgets('dibuka scan HID: daftar mentok di bawah', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pump(tester, db, hid: true);
    expect(maxExtent(tester), greaterThan(0),
        reason: 'prasyarat: daftar panjang');
    expect(offset(tester), closeTo(maxExtent(tester), 1.0));
  });

  testWidgets(
      'sheet sudah terbuka, item baru masuk (scan HID): mentok di bawah',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final c = await pump(tester, db, hid: true);
    c.read(cartProvider(kMainCartId).notifier).addItem(item(99));
    await tester.pumpAndSettle();
    expect(offset(tester), closeTo(maxExtent(tester), 1.0),
        reason: 'baris baru (animasi tinggi) harus ikut terlihat penuh');
  });
}

void scanExistingTests() {
  CartItem item(int i) => CartItem(
        productId: 'P$i',
        productUnitId: 'U$i',
        productName: 'Produk ke-$i',
        unitName: 'Pcs',
        qty: 1,
        price: 1000,
        originalPrice: 1000,
        costPrice: 800,
      );

  testWidgets(
      'scan produk YANG SUDAH ADA (qty bertambah) saat sheet terbuka: baris itu '
      'digulir ke layar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Owner',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    final n = container.read(cartProvider(kMainCartId).notifier);
    for (var i = 0; i < 40; i++) {
      n.addItem(item(i));
    }
    await tester.binding.setSurfaceSize(const Size(360, 700));
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
                builder: (_) => const CartSheet(scrollToBottom: true),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    // Awal: di dasar -> baris ke-2 jauh di luar layar.
    expect(find.text('Produk ke-2'), findsNothing);

    // Scan HID produk ke-2 yang sudah ada: qty +1 lalu sinyal.
    n.addItem(item(2));
    CartSheetScanSignal.notify('U2');
    await tester.pumpAndSettle();

    expect(find.text('Produk ke-2'), findsOneWidget,
        reason: 'baris produk yang di-scan harus terlihat');
    final y = tester.getCenter(find.text('Produk ke-2')).dy;
    expect(y, inInclusiveRange(0, 700));
  });
}
