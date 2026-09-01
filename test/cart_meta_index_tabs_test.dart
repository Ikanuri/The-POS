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

/// Redesain (permintaan user, mengacu contoh tab indeks map folder). Lewat
/// 2 iterasi bentuk "tab folder" (jajar-genjang/trapesium menumpuk) yang
/// SAMA SEKALI TIDAK cocok ekspektasi user meski sudah lewat proses mockup
/// — akhirnya user kirim contoh KONKRET yg diminta ditiru PERSIS: EMPAT
/// segmen RATA/DATAR dalam SATU baris (bukan tab terpisah yg saling
/// menumpuk), dipisah garis vertikal tipis, sudut ATAS baris membulat sbg
/// SATU GRUP. Warna semua segmen non-"Bayar" DEFAULT (sama dgn badan
/// cart); "Bayar" tetap dikecualikan, tetap pekat + teks putih supaya
/// tidak kehilangan penekanan sbg aksi utama.
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

  /// `_MetaTabDivider` private — dihitung lewat nama runtime-nya, pola sama
  /// dgn `add_control_idle_flat_style_test.dart`. Jumlah SEGMEN = jumlah
  /// divider + 1 (segmen pertama tidak didahului divider).
  int countMetaDividers(WidgetTester tester) => tester
      .widgetList(find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_MetaTabDivider'))
      .length;

  testWidgets(
      'owner: EMPAT segmen (Pelanggan/Pegawai/Tahan/Bayar) dlm satu baris '
      'flat, dipisah 3 garis', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasirWithCart(tester, db, deviceRole: 'owner');

    expect(countMetaDividers(tester), 3,
        reason: '4 segmen -> 3 garis pemisah di antaranya');
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
    // support returning intrinsic dimensions" begitu isinya `MarqueeText`.
    // Tinggi tab sekarang dihitung eksplisit, tanpa kueri intrinsik.
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasirWithCart(tester, db,
        deviceRole: 'owner',
        customerName: 'Buk Khotimah Rahmawati Kusumaningrum');

    expect(tester.takeException(), isNull);
    expect(countMetaDividers(tester), 3);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran: cuma TIGA segmen (tanpa Bayar)',
      (tester) async {
    final db = await seedDb(terimaPembayaran: false);
    addTearDown(() async => db.close());
    await pumpKasirWithCart(tester, db, deviceRole: 'kasir');

    expect(countMetaDividers(tester), 2,
        reason: '3 segmen (Pelanggan/Pegawai/Tahan) -> 2 garis pemisah');
    expect(find.text('Bayar'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
