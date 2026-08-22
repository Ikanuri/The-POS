import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart' show kMainCartId;

/// Redesain (permintaan user, mengacu contoh tab indeks map folder — bentuk
/// dikoreksi ulang setelah diukur langsung dari piksel referensi): tab meta
/// cart bar (Pelanggan/Pegawai/Tahan/Bayar) dulu SATU trapesium tunggal
/// berisi semua segmen, sekarang EMPAT tab jajar-genjang terpisah yang
/// saling menumpuk (kanan paling depan). Warna tab non-"Bayar" DEFAULT
/// (sama dgn badan cart) — bukan lagi gradasi terracotta lembut; "Bayar"
/// tetap dikecualikan, tetap pekat + teks putih supaya tidak kehilangan
/// penekanan sbg aksi utama.
void main() {
  Future<AppDatabase> seedDb({bool terimaPembayaran = true}) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(KasirPermissionsCompanion(isEnabled: Value(terimaPembayaran)));
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Gula Pasir'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(
              id: 't1', productUnitId: 'u1', price: 15000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    return db;
  }

  /// Render layar Kasir sungguhan lalu masukkan 1 produk ke keranjang —
  /// tab meta HANYA dirender saat keranjang tidak kosong.
  Future<ProviderContainer> pumpKasirWithCart(
    WidgetTester tester,
    AppDatabase db, {
    required String deviceRole,
    String? customerName,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: deviceRole,
        )),
      licenseProvider.overrideWith(
          (ref) => LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/kasir');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    // Produk datang dari stream drift — beri beberapa frame utk terisi.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.pump();
    if (customerName != null) {
      container
          .read(cartMetaProvider(kMainCartId).notifier)
          .setCustomer('c1', customerName);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    return container;
  }

  /// `_IndexTabPainter` private — dihitung lewat nama runtime-nya, pola
  /// sama dgn `add_control_idle_flat_style_test.dart`.
  int countIndexTabs(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .where((w) => w.painter.runtimeType.toString() == '_IndexTabPainter')
      .length;

  testWidgets(
      'owner: EMPAT tab indeks terpisah (Pelanggan/Pegawai/Tahan/Bayar), '
      'bukan satu tab gabungan', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasirWithCart(tester, db, deviceRole: 'owner');

    expect(countIndexTabs(tester), 4);
    // "Pelanggan" juga jadi label tab bottom-nav, jadi cukup pastikan ADA
    // (bukan tepat satu).
    expect(find.text('Pelanggan'), findsWidgets);
    expect(find.text('Tahan'), findsOneWidget);
    expect(find.text('Bayar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      '"Bayar" TETAP tegas (teks putih di tab pekat) sementara tab lain '
      'lembut (teks tetap berwarna aksen/normal)', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasirWithCart(tester, db, deviceRole: 'owner');

    final bayar = tester.widget<Text>(find.text('Bayar'));
    expect(bayar.style?.color, Colors.white,
        reason: 'Bayar harus kontras penuh — ia aksi utama');

    final tahan = tester.widget<Text>(find.text('Tahan'));
    expect(tahan.style?.color, isNot(Colors.white),
        reason: 'tab lembut TIDAK boleh ikut memakai teks putih — kalau '
            'ikut, penekanan Bayar sbg CTA hilang');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'nama pelanggan PANJANG (marquee, berbasis LayoutBuilder) di dalam tab '
      'TIDAK bikin layout meledak', (tester) async {
    // Regresi kelas bug nyata: versi pertama redesain ini menyamakan tinggi
    // tab pakai `IntrinsicHeight`, dan itu melempar "LayoutBuilder does not
    // support returning intrinsic dimensions" begitu isinya `_MarqueeText`.
    // Tinggi tab sekarang dihitung eksplisit, tanpa kueri intrinsik.
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasirWithCart(tester, db,
        deviceRole: 'owner',
        customerName: 'Buk Khotimah Rahmawati Kusumaningrum');

    expect(tester.takeException(), isNull);
    expect(countIndexTabs(tester), 4);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran: cuma TIGA tab (tanpa Bayar)',
      (tester) async {
    final db = await seedDb(terimaPembayaran: false);
    addTearDown(() async => db.close());
    await pumpKasirWithCart(tester, db, deviceRole: 'kasir');

    expect(countIndexTabs(tester), 3);
    expect(find.text('Bayar'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
