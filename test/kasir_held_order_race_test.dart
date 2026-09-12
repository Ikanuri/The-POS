import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Regresi insiden produksi: pesanan pra-bayar yang ditahan (uang sudah
/// diterima) bisa LENYAP total — tidak di daftar antrian, tidak di
/// keranjang — kalau kasir menyentuh dua aksi ganti-pesanan (tap kartu
/// antrian & tombol "Tahan") nyaris bersamaan, sebelum DB round-trip yang
/// pertama selesai. Akar masalah: `_resumeHeld`/`_holdCurrent` baca provider
/// cart aktif, `await` ke DB (`holdOrder`/`deleteHeldOrder`), BARU memutasi
/// provider cart — tanpa kunci apa pun sebelumnya.
///
/// `KasirScreen` pakai `StreamProvider` (drift `.watch()`, antrian held
/// orders) — WAJIB `drain()` di akhir tiap test yg mem-pump-nya, lihat
/// CLAUDE.md §Gotcha (`kasir_add_mode_paste_order_test.dart`).
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  const fakeDevice = DeviceIdentity(
    storeUuid: 's',
    storeKey: 'k',
    storeName: 'Toko',
    deviceName: 'Kasir',
    deviceCode: 'K1',
    deviceRole: 'owner',
  );

  /// Payload held-order minimal berisi satu `CartItem` dgn [productId] unik
  /// — dipakai sbg penanda identitas utk membuktikan tidak ada data yang
  /// lenyap (setiap productId harus tetap bisa ditemukan di SALAH SATU
  /// tempat: tabel held-orders ATAU keranjang aktif akhir).
  String payloadFor(String productId, String productName) => jsonEncode({
        'items': [
          CartItem(
            productId: productId,
            productUnitId: 'u-$productId',
            productName: productName,
            unitName: 'pcs',
            qty: 1,
            price: 1000,
            originalPrice: 1000,
            costPrice: 500,
          ).toJson(),
        ],
        'meta': <String, dynamic>{},
        'prabayar': <Map<String, dynamic>>[],
      });

  /// Kumpulan `productId` yang muncul di payload SATU held order.
  Set<String> productIdsOfHeld(HeldOrder h) {
    final decoded = jsonDecode(h.cartJson) as Map<String, dynamic>;
    final items = (decoded['items'] as List).cast<Map<String, dynamic>>();
    return items.map((e) => e['productId'] as String).toSet();
  }

  testWidgets(
      'tap kartu antrian A lalu (TANPA pump) tap kartu antrian B — hanya '
      'SATU resume yang jalan, order B TIDAK lenyap (tetap di antrian atau '
      'di keranjang), tidak ada data yang hilang', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    // Dua pesanan ditahan pra-existing (skenario nyata: >= 2 di antrian).
    await db.holdOrder(
        id: 'ho-a', label: 'Pesanan A', cartJson: payloadFor('p-a', 'A'));
    await db.holdOrder(
        id: 'ho-b', label: 'Pesanan B', cartJson: payloadFor('p-b', 'B'));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider
          .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    // Keranjang aktif TIDAK kosong & sudah punya pelanggan (Item 18 auto-
    // hold balik langsung jalan tanpa dialog label) — item ini juga harus
    // tetap "ada" (di held-orders baru) setelah race, bukan lenyap.
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p-active',
          productUnitId: 'u-active',
          productName: 'Aktif',
          unitName: 'pcs',
          qty: 1,
          price: 2000,
          originalPrice: 2000,
          costPrice: 1000,
        ));
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c-active', 'Bu Aktif');

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // Buka panel antrian.
    await tester.tap(find.text('Antrian').first);
    await tester.pumpAndSettle();

    expect(find.text('Pesanan A'), findsOneWidget);
    expect(find.text('Pesanan B'), findsOneWidget);

    // Race: panggil `onTap` kartu A lalu SEGERA (tanpa pump/settle & tanpa
    // "await" di antaranya) `onTap` kartu B — meniru kasir yang menyentuh
    // dua kartu nyaris bersamaan sebelum DB round-trip pertama selesai.
    // `WidgetTester.tap` TIDAK BISA dipakai dua kali tanpa `await` di
    // antaranya (guard `TestAsyncUtils` menolak pemanggilan bertumpuk) —
    // panggil langsung `onTap` (`VoidCallback`, persis field yang dipasang
    // `InkWell` sungguhan di `_HeldCard`) supaya urutan sinkron murni Dart
    // ini deterministik: baris kedua jalan SEBELUM baris pertama sempat
    // melewati `await` pertamanya di dalam `_resumeHeld`.
    InkWell inkWellFor(String label) => tester.widget<InkWell>(find
        .ancestor(of: find.text(label), matching: find.byType(InkWell))
        .first);
    inkWellFor('Pesanan A').onTap!();
    inkWellFor('Pesanan B').onTap!();
    await tester.pumpAndSettle();

    final heldAfter = await db.select(db.heldOrders).get();
    final cartAfter = container.read(cartProvider(kMainCartId));

    // Kumpulkan SEMUA productId yang masih "ada" di manapun (antrian ATAU
    // keranjang aktif akhir).
    final survivingIds = <String>{
      for (final h in heldAfter) ...productIdsOfHeld(h),
      for (final c in cartAfter) c.productId,
    };

    // Uang utk KETIGA pesanan (A, B, keranjang aktif semula) sudah pernah
    // diterima — tidak satu pun boleh lenyap total dari kedua tempat ini.
    expect(survivingIds, containsAll(<String>{'p-a', 'p-b', 'p-active'}),
        reason: 'tidak boleh ada pesanan yang lenyap total dari antrian '
            'maupun keranjang aktif akibat race dua resume berbarengan');

    await drain(tester);
  });

  testWidgets(
      'tombol "Tahan" ditap dua kali cepat berturut-turut (TANPA pump di '
      'antaranya) -> hanya SATU held order baru yang tercipta, tidak '
      'duplikat', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider
          .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'p-hold',
          productUnitId: 'u-hold',
          productName: 'Kopi',
          unitName: 'pcs',
          qty: 1,
          price: 3000,
          originalPrice: 3000,
          costPrice: 2000,
        ));
    // Pelanggan sudah dipilih -> `_holdCurrent` langsung tahan tanpa dialog
    // label (pola sama `kasir_price_category_hold_resume_test.dart`).
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', 'Bu Sari');

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // Panggil langsung `onTap` InkWell "Tahan" dua kali berturut-turut
    // tanpa `await`/pump di antaranya — lihat komentar di test pertama
    // soal kenapa `tester.tap` ganda tidak bisa dipakai di sini.
    final holdInkWell = tester.widget<InkWell>(find
        .ancestor(
            of: find.byIcon(Icons.pause_circle_outline),
            matching: find.byType(InkWell))
        .first);
    holdInkWell.onTap!();
    holdInkWell.onTap!();
    await tester.pumpAndSettle();

    final held = await db.select(db.heldOrders).get();
    expect(held, hasLength(1),
        reason: 'tap ganda-cepat pada tombol Tahan tidak boleh membuat '
            'held order duplikat');

    await drain(tester);
  });
}
