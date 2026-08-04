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

/// Susulan (permintaan user): "ketika kita close keranjang dan open lagi,
/// itu bisa dibuat posisi terakhir scroll item di keranjang persis dengan
/// kondisi sebelum close?" — kasus konkret: misclick tap item (nyambung ke
/// modal entri kasir) di keranjang yang belanjaannya banyak & sudah
/// discroll jauh, lalu balik lagi harus scroll ulang dari atas.
void main() {
  // `_CartSheetState._scrollMemory` statis bertahan lintas test dlm 1
  // proses — WAJIB dibersihkan supaya test lain tidak saling bocor.
  setUp(() => CartSheetScrollTestSeam.clear());
  tearDown(() => CartSheetScrollTestSeam.clear());

  Future<ProviderContainer> pumpCartOpen(WidgetTester tester, AppDatabase db,
      {int itemCount = 25}) async {
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

    final notifier = container.read(cartProvider(kMainCartId).notifier);
    for (var i = 0; i < itemCount; i++) {
      notifier.addItem(CartItem(
        productId: 'P$i',
        productUnitId: 'U$i',
        productName: 'Produk ke-$i',
        unitName: 'Pcs',
        qty: 1,
        price: 1000,
        originalPrice: 1000,
        costPrice: 800,
      ));
    }

    await tester.binding.setSurfaceSize(const Size(360, 700));
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
                  builder: (_) => const CartSheet(),
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
    return container;
  }

  testWidgets(
      'scroll ke bawah, tutup sheet (pop), buka lagi -> posisi scroll SAMA '
      '(tidak kembali ke atas)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await pumpCartOpen(tester, db);

    final listFinder = find.byType(ListView);
    // `DraggableScrollableSheet` drag pertama membesarkan TINGGI sheet dulu
    // (initialChildSize 0.7 -> maxChildSize 0.95) — scroll konten dalamnya
    // baru mulai bergerak SETELAH sheet mentok maksimal, jadi butuh 2 drag
    // terpisah (dibuktikan lewat debug manual: drag pertama offset tetap 0).
    await tester.drag(listFinder, const Offset(0, -1500));
    await tester.pump();
    await tester.drag(listFinder, const Offset(0, -1500));
    await tester.pumpAndSettle();

    double listOffset() =>
        tester.widget<ListView>(listFinder).controller!.offset;

    final offsetBeforeClose = listOffset();
    expect(offsetBeforeClose, greaterThan(0),
        reason: 'prasyarat: memang sudah discroll turun, bukan masih di atas');

    // Tutup sheet (simulasi misclick tap item / tap di luar sheet).
    Navigator.of(tester.element(listFinder)).pop();
    await tester.pumpAndSettle();

    // Buka lagi.
    await tester.tap(find.text('buka keranjang'));
    await tester.pumpAndSettle();

    final offsetAfterReopen = listOffset();

    expect(offsetAfterReopen, closeTo(offsetBeforeClose, 1),
        reason: 'posisi scroll harus dipulihkan persis, bukan kembali ke '
            'atas (0)');
  });

  test(
      'posisi scroll disimpan per-cartId, bukan global — cart lain tidak '
      'ikut terpengaruh', () {
    CartSheetScrollTestSeam.set(kMainCartId, 500);
    CartSheetScrollTestSeam.set('lain', 0);

    expect(CartSheetScrollTestSeam.get(kMainCartId), 500);
    expect(CartSheetScrollTestSeam.get('lain'), 0);
  });
}
