import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart' show kMainCartId;

/// Item 55/56 — segmen "Bayar" terracotta di cart bar (tab meta, sejajar
/// "Tahan"): muncul utk owner/asisten/pegawai BERIZIN `terima_pembayaran`,
/// tap langsung ke layar Pembayaran (TANPA lewat sheet keranjang dulu).
/// Disembunyikan utk pegawai TANPA izin (jalur mereka tetap "Kirim ke
/// Owner/Asisten" via cart sheet, lihat kasir_handoff_qr_test.dart).
void main() {
  Future<AppDatabase> seedDb({bool terimaPembayaran = false}) async {
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
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 15000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    return db;
  }

  Future<ProviderContainer> pumpKasir(WidgetTester tester, AppDatabase db,
      {required String deviceRole}) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
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
      licenseProvider.overrideWith((ref) =>
          LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/kasir');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tambah item ke keranjang lewat tap ikon "+" (AddControl/quickAdd) di
    // kartu produk (menaikkan cartProvider melalui alur nyata, bukan seed
    // langsung provider — memastikan trigger reservasi nomor nota Item 55
    // ikut teruji). Tap BODY kartu hanya membuka ItemEntrySheet, tidak
    // langsung menambah ke keranjang — lihat onTapBody vs onQuickAdd di
    // kasir_screen.dart.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('owner melihat segmen Bayar di cart bar, tap ke Pembayaran',
      (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'owner');

    expect(find.text('Bayar'), findsOneWidget);

    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran'), findsOneWidget,
        reason: 'tap Bayar harus langsung ke AppBar layar Pembayaran');
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran TIDAK melihat segmen Bayar di '
      'cart bar', (tester) async {
    final db = await seedDb(terimaPembayaran: false);
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'kasir');

    expect(find.text('Bayar'), findsNothing);
  });

  testWidgets(
      'pegawai DENGAN izin terima_pembayaran melihat segmen Bayar',
      (tester) async {
    final db = await seedDb(terimaPembayaran: true);
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'kasir');

    expect(find.text('Bayar'), findsOneWidget);
  });

  testWidgets(
      'nomor nota (#1) muncul di cart bar setelah item pertama masuk '
      '(reservasi Item 55)', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'owner');

    // Reservasi async — beri kesempatan selesai.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.textContaining('#1'), findsWidgets);
  });

  testWidgets(
      'REDESAIN: layout cart bar TIDAK BERUBAH SAMA SEKALI walau nama '
      'pelanggan sangat panjang — nama panjang ditangani teks berjalan, '
      'BUKAN dgn melipat baris (permintaan user)', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db, deviceRole: 'owner');

    // Rekam posisi SEMUA tombol sebelum nama panjang dipasang.
    final bayarBefore = tester.getRect(find.text('Bayar'));
    final tahanBefore = tester.getRect(find.text('Tahan'));

    container.read(cartMetaProvider(kMainCartId).notifier).setCustomer(
        'c1', 'Pelanggan Dengan Nama Sangat Sangat Sangat Panjang Sekali');
    await tester.pump();
    await tester.pump();

    final bayarAfter = tester.getRect(find.text('Bayar'));
    final tahanAfter = tester.getRect(find.text('Tahan'));

    // INTI permintaan user: "sekiranya semua tombol mendapat porsi pas nya
    // tanpa harus diubah ubah lagi layoutnya" — posisi tombol harus IDENTIK,
    // bukan sekadar "Bayar tetap di kanan".
    expect(bayarAfter, bayarBefore,
        reason: 'posisi tombol Bayar WAJIB identik — layout tidak boleh '
            'bergeser/melipat hanya karena nama pelanggan panjang');
    expect(tahanAfter, tahanBefore,
        reason: 'tombol Tahan pun tidak boleh bergeser (dulu ikut melipat '
            'ke baris ke-2 saat nama panjang)');

    // Dan nama panjangnya memang dirender utuh (untuk digeser), bukan
    // dipotong ellipsis — bukti jalur marquee yang dipakai.
    expect(find.textContaining('Sangat Panjang Sekali'), findsOneWidget);
  });

  testWidgets(
      'nama panjang BENAR-BENAR berjalan (offset bergeser seiring waktu), '
      'bukan sekadar dipotong ellipsis', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db, deviceRole: 'owner');

    container.read(cartMetaProvider(kMainCartId).notifier).setCustomer(
        'c1', 'Pelanggan Dengan Nama Sangat Sangat Sangat Panjang Sekali');
    await tester.pump();
    await tester.pump();

    // Teks yang meluber dirender di dalam ClipRect+Transform (jalur marquee),
    // BUKAN sebagai Text ber-ellipsis biasa.
    Offset offsetOfName() {
      final t = tester.widget<Transform>(find.ancestor(
        of: find.textContaining('Sangat Panjang Sekali'),
        matching: find.byType(Transform),
      ).first);
      return Offset(t.transform.getTranslation().x, 0);
    }

    final awal = offsetOfName();
    // Lewati fase "diam di ujung" (18% durasi) lalu ukur lagi.
    await tester.pump(const Duration(milliseconds: 1500));
    final sesudah = offsetOfName();

    expect(sesudah.dx, lessThan(awal.dx),
        reason: 'teks harus BERGESER ke kiri seiring waktu — kalau diam saja, '
            'berarti jatuh ke ellipsis biasa, bukan teks berjalan');
  });

  testWidgets(
      'porsi chip Pelanggan TIDAK dikurangi oleh fitur teks berjalan — tetap '
      'segmen terlebar di baris meta', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db, deviceRole: 'owner');

    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', 'Bu Artia');
    await tester.pump();
    await tester.pump();

    final pelangganW = tester.getRect(find.text('Bu Artia')).width;
    final pegawaiW = tester.getRect(find.text('Pegawai')).width;
    expect(pelangganW, greaterThan(pegawaiW),
        reason: 'chip Pelanggan dapat porsi lebih besar (flex 4 vs 3) — '
            'permintaan user: porsinya jangan dikurangi');
  });
}
