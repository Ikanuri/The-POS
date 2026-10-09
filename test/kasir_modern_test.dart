import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/providers/theme_provider.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';
import 'package:the_pos/features/kasir/widgets/paste_order_sheet.dart';

/// Kasir gaya BARU (kasir_modern.dart): landing, kolom cari yang naik saat
/// mengetik, tanpa Terlaris, logika kasir tetap (stepper, select-all, dst.).
int _seq = 0;

Future<String> _addProduct(AppDatabase db, String name,
    {String? parentProductId,
    bool isActive = true,
    int price = 10000,
    bool markedOutOfStock = false}) async {
  final id = 'p${_seq++}';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: id,
        name: name,
        isActive: Value(isActive),
        parentProductId: Value(parentProductId),
        markedOutOfStock: Value(markedOutOfStock),
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: '$id-u',
        productId: id,
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: '$id-u-t1',
        productUnitId: '$id-u',
        price: price,
      ));
  return id;
}

Future<void> _sale(AppDatabase db, DateTime at, List<(String, double)> lines,
    {String status = 'lunas'}) async {
  final txId = 't${_seq++}';
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: txId,
        localId: 'K-$txId',
        status: status,
        total: 1000,
        paid: 1000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(at),
      ));
  var n = 0;
  for (final l in lines) {
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: '$txId-${n++}',
          transactionId: txId,
          productId: l.$1,
          productUnitId: '${l.$1}-u',
          qty: l.$2,
          priceAtSale: 1000,
          originalPrice: 1000,
          subtotal: 1000,
        ));
  }
}

Future<void> _pumpKasir(WidgetTester tester, AppDatabase db,
    {Map<String, Object> prefs = const {},
    Size size = const Size(430, 2400),
    bool stickers = false,
    bool reduced = false,
    double textScale = 1.0,
    String deviceRole = 'owner'}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues(
      {'kasir_swipe_hint_count': 3, ...prefs});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // Stiker berulang selamanya -> pumpAndSettle tak pernah selesai.
        // Test umum mematikannya; test stiker khusus menyalakannya.
        if (!stickers)
          kasirStickerProvider.overrideWith((ref, slot) async => null),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            deviceName: 'Kasir Uji',
            deviceCode: 'K1',
            deviceRole: deviceRole,
          )),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
                disableAnimations: reduced,
                textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: const KasirScreen(),
      ),
    ),
  );
  if (stickers) {
    // Stiker berulang: jangan pumpAndSettle.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  } else {
    await tester.pumpAndSettle();
  }
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  const modern = {'kasir_style': 'modern'};

  testWidgets('default = Klasik (tanpa kolom cari gaya Baru)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, 'Gula Pasir');
    await _pumpKasir(tester, db);
    expect(find.byKey(const Key('modern-search')), findsNothing);
    await _drain(tester);
    await db.close();
  });

  testWidgets(
      'gaya Baru: landing + kolom cari; kolom cari NAIK saat '
      'mengetik, teks & fokus tetap', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final a = await _addProduct(db, 'Gula Pasir');
    await _addProduct(db, 'Beras Rojolele');
    await _sale(db, DateTime.now(), [(a, 1)]);
    await _pumpKasir(tester, db, prefs: modern);

    expect(find.byKey(const Key('modern-search')), findsOneWidget);
    expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
    expect(find.text('Mau jual apa hari ini?'), findsOneWidget);
    expect(find.text('Terlaris'), findsNothing,
        reason: 'Terlaris dihapus di gaya Baru');
    expect(find.text('Terakhir dijual'), findsOneWidget);
    final yLanding =
        tester.getTopLeft(find.byKey(const Key('modern-search'))).dy;

    await tester.tap(find.byKey(const Key('modern-search')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
    await tester.pumpAndSettle();

    expect(find.text('Mau jual apa hari ini?'), findsNothing);
    expect(find.byKey(const Key('kasir-landing')), findsNothing);
    final yTop = tester.getTopLeft(find.byKey(const Key('modern-search'))).dy;
    expect(yTop, lessThan(yLanding - 20),
        reason: 'kolom cari harus pindah ke atas setelah mengetik');
    expect(find.text('Gula Pasir'), findsOneWidget);
    expect(find.text('Beras Rojolele'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('modern-search')))
            .controller!
            .text,
        'gula');

    // Hapus -> kembali ke landing, kolom cari turun lagi.
    await tester.tap(find.byKey(const Key('modern-search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('modern-search'))).dy,
        closeTo(yLanding, 2));

    await _drain(tester);
    await db.close();
  });

  testWidgets('"Semua produk" -> daftar penuh; Beranda kembali ke landing',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, 'Gula Pasir');
    await _addProduct(db, 'Sabun Mandi');
    await _pumpKasir(tester, db, prefs: modern);
    await tester.tap(find.byKey(const Key('landing-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kasir-landing')), findsNothing);
    expect(find.text('Sabun Mandi'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kasir-home-chip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
    await _drain(tester);
    await db.close();
  });

  testWidgets(
      'stepper "+" di daftar gaya Baru menambah ke keranjang '
      '(jari menempel beberapa frame) dan select-all pencarian tetap '
      'berjalan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _addProduct(db, 'Gula Pasir');
    await _pumpKasir(tester, db, prefs: modern);
    await tester.tap(find.byKey(const Key('modern-search')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
    await tester.pumpAndSettle();

    final g = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.add_rounded).first));
    await tester.pump(const Duration(milliseconds: 60));
    await g.up();
    await tester.pumpAndSettle();

    expect(find.text('1'), findsWidgets);
    final ctrl = tester
        .widget<TextField>(find.byKey(const Key('modern-search')))
        .controller!;
    expect(ctrl.text, 'gula', reason: 'teks cari tidak boleh terhapus');
    expect(ctrl.selection.start, 0);
    expect(ctrl.selection.end, 4,
        reason: 'select-all setelah tap + supaya ketik berikutnya menimpa');
    await _drain(tester);
    await db.close();
  });

  group('tombol pojok', () {
    const keys = ['sync', 'paste', 'held', 'history'];

    testWidgets(
        'tombol bulat PERMANEN di header (kiri->kanan Sync, Tempel, Antrian, '
        'Riwayat); landing berketerangan + saklar tema, kompak tanpa '
        'keterangan + grid/list; tanpa FAB', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);

      expect(find.byKey(const Key('fab-rail')), findsNothing);
      expect(find.byKey(const Key('fab-main')), findsNothing);
      expect(find.byKey(const Key('fab-scrim')), findsNothing);

      void expectOrder() {
        final xs = [
          for (final k in keys) tester.getCenter(find.byKey(Key('hdr-$k'))).dx
        ];
        for (var i = 1; i < xs.length; i++) {
          expect(xs[i], greaterThan(xs[i - 1]), reason: 'urutan kiri->kanan');
        }
      }

      Color bgOf(String k) => tester
          .widget<Material>(find
              .descendant(
                  of: find.byKey(Key('hdr-$k')),
                  matching: find.byType(Material))
              .first)
          .color!;
      void expectColors() {
        expect(bgOf('history'), AppTheme.riwayatBg(false));
        expect(bgOf('held'), AppTheme.antrianBg(false));
        expect(bgOf('paste'), AppTheme.tempelBg(false));
        expect(bgOf('sync'), AppTheme.scanBg(false));
      }

      // Landing: keterangan kecil di bawah lingkaran, saklar ada, grid tidak.
      for (final k in keys) {
        expect(find.byKey(Key('hdr-$k')), findsOneWidget, reason: k);
        final item = find.byKey(Key('hdr-$k'));
        final label = find.descendant(of: item, matching: find.byType(Text));
        final circle =
            find.descendant(of: item, matching: find.byType(Material));
        expect(tester.getCenter(label.first).dy,
            greaterThan(tester.getCenter(circle.first).dy));
        expect(tester.widget<Text>(label.first).style!.fontSize!, lessThan(11));
      }
      expectOrder();
      expectColors();
      expect(find.byKey(const Key('hdr-theme')), findsOneWidget);
      expect(find.byKey(const Key('hdr-grid')), findsNothing);
      expect(find.text('The POS'), findsOneWidget);
      expect(tester.getCenter(find.byKey(const Key('hdr-history'))).dx,
          lessThan(tester.getCenter(find.byKey(const Key('hdr-theme'))).dx));

      // Mengetik: kompak.
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      for (final k in keys) {
        expect(find.byKey(Key('hdr-$k')), findsOneWidget, reason: k);
        expect(
            find.descendant(
                of: find.byKey(Key('hdr-$k')), matching: find.byType(Text)),
            findsNothing,
            reason: 'tanpa keterangan teks di mode kompak');
      }
      expectOrder();
      expectColors();
      expect(find.byKey(const Key('hdr-theme')), findsNothing);
      expect(find.byKey(const Key('hdr-grid')), findsOneWidget);
      expect(find.text('The POS'), findsNothing);
      expect(find.byIcon(Icons.shopping_basket_rounded), findsOneWidget);
      expect(find.byKey(const Key('fab-main')), findsNothing);

      await _drain(tester);
      await db.close();
    });

    testWidgets('badge jumlah antrian di tombol Antrian header',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await db.into(db.heldOrders).insert(HeldOrdersCompanion.insert(
            id: 'h1',
            label: 'Bu Sari',
            cartJson: jsonEncode({'items': [], 'meta': {}}),
          ));
      await _pumpKasir(tester, db, prefs: modern);
      expect(
          find.descendant(
              of: find.byKey(const Key('hdr-held')), matching: find.text('1')),
          findsOneWidget);
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'muat di lebar 360 tanpa overflow (landing & kompak, skala 1.3)',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db,
          prefs: modern, size: const Size(360, 800), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'Tempel Pesanan membuka sheet; Sync LAN membuka pop-up kecil '
        '(owner: Jadi host)', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);

      await tester.tap(find.byKey(const Key('hdr-paste')));
      await tester.pumpAndSettle();
      expect(find.byType(PasteOrderSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(PasteOrderSheet))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('hdr-sync')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-sync-dialog')), findsOneWidget);
      // Owner: mode Host terpilih, ada pilihan Host/Klien.
      expect(find.byKey(const Key('quick-sync-mode')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-host')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-camera')), findsNothing);

      await _drain(tester);
      await db.close();
    });

    testWidgets('Sync LAN untuk kasir: mode Klien (kamera) + isian manual',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern, deviceRole: 'kasir');
      await tester.tap(find.byKey(const Key('hdr-sync')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-sync-camera')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('quick-sync-manual')));
      await tester.tap(find.byKey(const Key('quick-sync-manual')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-sync-ip')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-token')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-go')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-host')), findsNothing);
      // Tanpa IP/Token -> pesan, tidak crash.
      await tester.tap(find.byKey(const Key('quick-sync-go')));
      await tester.pumpAndSettle();
      expect(find.text('Pindai QR host atau isi IP dan Token dulu'), findsOneWidget);
      await _drain(tester);
      await db.close();
    });

    testWidgets('sakelar tema & grid/list bekerja dari tombol pojok',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(KasirScreen)));

      await tester.tap(find.byKey(const Key('hdr-theme')));
      await tester.pump();
      expect(container.read(themeModeProvider), ThemeMode.dark);

      final before = container.read(kasirGridProvider);
      // grid/list hanya di mode non-landing.
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hdr-grid')));
      await tester.pump();
      expect(container.read(kasirGridProvider), !before);

      await _drain(tester);
      await db.close();
    });
  });

  group('saran pelanggan di kolom cari', () {
    Future<void> saleFor(
        AppDatabase db, String customerId, String productId, int times) async {
      for (var i = 0; i < times; i++) {
        final txId = 'tc${_seq++}';
        await db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: txId,
              localId: 'K-$txId',
              status: 'lunas',
              total: 1000,
              paid: 1000,
              changeAmount: 0,
              paymentMethod: 'tunai',
              customerId: Value(customerId),
              createdAt: Value(DateTime.now()),
            ));
        await db
            .into(db.transactionItems)
            .insert(TransactionItemsCompanion.insert(
              id: '$txId-0',
              transactionId: txId,
              productId: productId,
              productUnitId: '$productId-u',
              qty: 1,
              priceAtSale: 1000,
              originalPrice: 1000,
              subtotal: 1000 * (3 - i % 2),
            ));
      }
    }

    testWidgets('tanpa pelanggan: hint statis "Cari produk…", tanpa panah',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      expect(find.text('Cari produk…'), findsOneWidget);
      expect(find.byKey(const Key('modern-suggest-go')), findsNothing);
      await _drain(tester);
      await db.close();
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('hint bergilir tidak terpotong (skala font $scale)',
          (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final gula = await _addProduct(db, 'Gula Pasir');
        final beras = await _addProduct(db, 'Beras Rojolele');
        await saleFor(db, 'c1', gula, 3);
        await saleFor(db, 'c1', beras, 1);
        await _pumpKasir(tester, db,
            prefs: modern, size: const Size(360, 800), textScale: scale);
        ProviderScope.containerOf(tester.element(find.byType(KasirScreen)))
            .read(cartMetaProvider(kMainCartId).notifier)
            .setCustomer('c1', 'Bu Rina');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        final hint = find.textContaining('Cari Gula Pasir', findRichText: true);
        expect(hint, findsOneWidget);
        final el = tester.element(hint);
        final tp = TextPainter(
          text: TextSpan(
              text: 'Cari Xg',
              style: DefaultTextStyle.of(el).style.merge(
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          textScaler: MediaQuery.textScalerOf(el),
          textDirection: TextDirection.ltr,
        )..layout();
        final window = tester
            .getSize(
                find.ancestor(of: hint, matching: find.byType(ClipRect)).first)
            .height;
        expect(window, greaterThanOrEqualTo(tp.height),
            reason: 'jendela hint >= tinggi teks');
        expect(
            tester.getSize(hint).height, greaterThanOrEqualTo(tp.height - 0.5),
            reason: 'baris teks tidak dijepit lebih rendah dari tingginya');
        // Teks tetap rata-tengah vertikal di pil.
        expect(
            tester.getCenter(hint).dy,
            closeTo(
                tester
                    .getCenter(find.byKey(const Key('modern-search-pill')))
                    .dy,
                2));
        await _drain(tester);
        await db.close();
      });
    }

    testWidgets(
        'dengan pelanggan: hint bergilir produk yang sering dibeli '
        'pelanggan itu; panah mencari saran yang tampil', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final gula = await _addProduct(db, 'Gula Pasir');
      final beras = await _addProduct(db, 'Beras Rojolele');
      await _addProduct(db, 'Sabun Mandi');
      await saleFor(db, 'c1', gula, 3);
      await saleFor(db, 'c1', beras, 1);
      await _pumpKasir(tester, db, prefs: modern);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(KasirScreen)));
      container
          .read(cartMetaProvider(kMainCartId).notifier)
          .setCustomer('c1', 'Bu Rina');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Cari Gula Pasir', findRichText: true),
          findsOneWidget);
      expect(find.byKey(const Key('modern-suggest-go')), findsOneWidget);

      // Bergilir ke saran berikutnya.
      await tester.pump(const Duration(milliseconds: 3300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Cari Beras Rojolele', findRichText: true),
          findsOneWidget);

      // Panah mencari saran yang sedang tampil.
      await tester.tap(find.byKey(const Key('modern-suggest-go')));
      await tester.pumpAndSettle();
      final ctrl = tester
          .widget<TextField>(find.byKey(const Key('modern-search')))
          .controller!;
      expect(ctrl.text, 'Beras Rojolele');
      expect(find.text('Sabun Mandi'), findsNothing);
      expect(find.byKey(const Key('modern-suggest-go')), findsNothing,
          reason: 'saran/panah hilang begitu ada teks');

      await _drain(tester);
      await db.close();
    });
  });

  group('cart bar & antrian gaya Baru', () {
    testWidgets(
        'cart bar baru muncul setelah item masuk: total, Tahan, '
        'Bayar, chip Pelanggan/Pegawai; tanpa tab Klasik', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      expect(find.byKey(const Key('modern-cart-bar')), findsNothing);

      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modern-cart-bar')), findsOneWidget);
      expect(find.text(formatRupiah(10000)), findsWidgets);
      expect(find.byKey(const Key('modern-hold')), findsOneWidget);
      expect(find.byKey(const Key('modern-bayar')), findsOneWidget);
      expect(find.byKey(const Key('pill-customer')), findsOneWidget);
      expect(find.byKey(const Key('pill-employee')), findsOneWidget);
      expect(find.text('Pelanggan'), findsOneWidget);
      // Tab Klasik (Tahan/Bayar berlabel segmen) tidak dipakai.
      expect(find.text('Tahan'), findsNothing);

      // Pelanggan terpilih -> chip aktif + tombol hapus.
      final container =
          ProviderScope.containerOf(tester.element(find.byType(KasirScreen)));
      container
          .read(cartMetaProvider(kMainCartId).notifier)
          .setCustomer('c1', 'Bu Rina');
      await tester.pumpAndSettle();
      expect(find.text('Bu Rina'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byKey(const Key('pill-customer')),
          matching: find.byIcon(Icons.close_rounded)));
      await tester.pumpAndSettle();
      expect(find.text('Pelanggan'), findsOneWidget);

      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'Antrian Pesanan: lembar bergaya struk menampilkan pesanan '
        'ditahan; kosong -> pesan; tutup', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);

      await tester.tap(find.byKey(const Key('hdr-held')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modern-held-sheet')), findsOneWidget);
      expect(find.text('Tidak ada pesanan ditahan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('modern-held-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modern-held-sheet')), findsNothing);

      await db.into(db.heldOrders).insert(HeldOrdersCompanion.insert(
            id: 'h1',
            label: 'Bu Sari',
            cartJson: jsonEncode({'items': [], 'meta': {}}),
          ));
      await tester.tap(find.byKey(const Key('hdr-held')));
      await tester.pumpAndSettle();
      expect(find.text('Bu Sari'), findsOneWidget);
      expect(find.textContaining('Ditahan'), findsOneWidget);

      await _drain(tester);
      await db.close();
    });
  });

  group('list tile & chip gaya Baru', () {
    final tileCard = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ModernTileCard');

    testWidgets(
        'produk = kartu lembut di landing & daftar; Klasik tidak '
        'dibungkus', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final a = await _addProduct(db, 'Gula Pasir');
      await _addProduct(db, 'Gula Merah');
      await _sale(db, DateTime.now(), [(a, 1)]);
      await _pumpKasir(tester, db,
          prefs: {...modern, 'kasir_grid_view': false});
      expect(tileCard, findsOneWidget, reason: 'landing: 1 produk terakhir');

      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      expect(tileCard, findsNWidgets(2));
      await _drain(tester);

      await _pumpKasir(tester, db, prefs: {'kasir_grid_view': false});
      await tester.enterText(find.byType(TextField).first, 'gula');
      await tester.pumpAndSettle();
      expect(tileCard, findsNothing);
      await _drain(tester);
      await db.close();
    });

    testWidgets('chip kategori aktif = pil terracotta penuh', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
          id: const Value(700), name: const Value('Minuman')));
      await _addProduct(db, 'Teh Botol');
      await _pumpKasir(tester, db, prefs: modern);
      await tester.tap(find.byKey(const Key('landing-cat-700')));
      await tester.pumpAndSettle();
      final chip =
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'Minuman'));
      expect(chip.selected, isTrue);
      expect(chip.selectedColor, AppTheme.accent);
      expect(chip.shape, isA<StadiumBorder>());
      expect(chip.showCheckmark, isFalse);
      await _drain(tester);
      await db.close();
    });
  });

  group('penyesuaian desain (9 Okt)', () {
    testWidgets(
        'header: ikon + nama aplikasi di kiri, grid/list & saklar '
        'listrik di kanan atas; kolom cari TANPA border kedua; aksen fokus '
        'memudar', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);

      expect(find.text('The POS'), findsOneWidget);
      expect(find.byIcon(Icons.shopping_basket_rounded), findsOneWidget);
      const w = 430.0;
      expect(tester.getCenter(find.byKey(const Key('hdr-theme'))).dx,
          greaterThan(w * 0.8));
      expect(find.byKey(const Key('hdr-grid')), findsNothing,
          reason: 'grid/list tidak tampil di landing');
      // Saklar = pelat dengan tuas matahari/bulan, bukan Switch/toggle.
      expect(find.byType(Switch), findsNothing);
      expect(find.byIcon(Icons.wb_sunny_rounded), findsOneWidget);
      expect(find.byIcon(Icons.nightlight_round), findsOneWidget);

      // Tidak ada lingkaran kedua: semua border TextField dimatikan.
      final dec = tester
          .widget<TextField>(find.byKey(const Key('modern-search')))
          .decoration!;
      for (final b in [
        dec.border,
        dec.enabledBorder,
        dec.focusedBorder,
        dec.errorBorder,
        dec.disabledBorder,
        dec.focusedErrorBorder,
      ]) {
        expect(b, InputBorder.none);
      }
      BoxDecoration pill() => tester
          .widget<AnimatedContainer>(
              find.byKey(const Key('modern-search-pill')))
          .decoration! as BoxDecoration;
      final idle = (pill().border! as Border).top;
      await tester.tap(find.byKey(const Key('modern-search')));
      await tester.pumpAndSettle();
      final focus = (pill().border! as Border).top;
      expect(focus.color.alpha, lessThan(255),
          reason: 'aksen fokus memudar (tidak tegas)');
      expect(focus.color.red, AppTheme.accent.red);
      expect(focus.color, isNot(idle.color));
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'landing: kolom cari dipusatkan vertikal; mengetik -> naik '
        'ke atas', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern, size: const Size(430, 900));
      double cy() =>
          tester.getCenter(find.byKey(const Key('modern-search-pill'))).dy;
      expect(cy(), inInclusiveRange(900 * 0.30, 900 * 0.58),
          reason: 'landing: pil di sekitar tengah layar');
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      expect(cy(), lessThan(900 * 0.20), reason: 'mengetik: pil di atas');
      await _drain(tester);
      await db.close();
    });

    testWidgets('chip kategori landing: SATU baris, bisa digeser mendatar',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      for (var i = 0; i < 9; i++) {
        await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
            id: Value(800 + i), name: Value('Kategori Panjang $i')));
      }
      await _pumpKasir(tester, db, prefs: modern, size: const Size(360, 800));
      final scroll = tester.widget<SingleChildScrollView>(
          find.byKey(const Key('landing-chips')));
      expect(scroll.scrollDirection, Axis.horizontal);
      final ys = {
        for (var i = 0; i < 3; i++)
          tester.getCenter(find.byKey(Key('landing-cat-${800 + i}'))).dy
      };
      expect(ys.length, 1, reason: 'semua chip sejajar di satu baris');
      expect(tester.getCenter(find.byKey(const Key('landing-cat-808'))).dx,
          greaterThan(360),
          reason: 'chip ujung di luar layar (harus digeser)');
      await tester.drag(
          find.byKey(const Key('landing-chips')), const Offset(-3000, 0));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byKey(const Key('landing-cat-808'))).dx,
          lessThan(360));
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'blok seleksi-semua pada kolom cari membulat (digambar '
        'sendiri), bukan seleksi lancip bawaan', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modern-search-selection')), findsNothing);

      final ctrl = tester
          .widget<TextField>(find.byKey(const Key('modern-search')))
          .controller!;
      ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();
      final box = tester
          .widget<Container>(find.byKey(const Key('modern-search-selection')));
      final r =
          (box.decoration! as BoxDecoration).borderRadius! as BorderRadius;
      expect(r.topLeft.x, greaterThanOrEqualTo(8));
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'teks sugesti berganti mulus: tidak bergeser horizontal '
        'selama transisi', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final gula = await _addProduct(db, 'Gula Pasir');
      final beras = await _addProduct(db, 'Beras Rojolele');
      for (final (p, n) in [(gula, 3), (beras, 2)]) {
        for (var i = 0; i < n; i++) {
          final tx = 'tx${_seq++}';
          await db.into(db.transactions).insert(TransactionsCompanion.insert(
                id: tx,
                localId: 'K-$tx',
                status: 'lunas',
                total: 1000,
                paid: 1000,
                changeAmount: 0,
                paymentMethod: 'tunai',
                customerId: const Value('c9'),
                createdAt: Value(DateTime.now()),
              ));
          await db.into(db.transactionItems).insert(
              TransactionItemsCompanion.insert(
                  id: '$tx-0',
                  transactionId: tx,
                  productId: p,
                  productUnitId: '$p-u',
                  qty: 1,
                  priceAtSale: 1000,
                  originalPrice: 1000,
                  subtotal: 1000));
        }
      }
      await _pumpKasir(tester, db, prefs: modern);
      ProviderScope.containerOf(tester.element(find.byType(KasirScreen)))
          .read(cartMetaProvider(kMainCartId).notifier)
          .setCustomer('c9', 'Pak Budi');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final rich = find.textContaining('Cari ', findRichText: true);
      expect(rich, findsOneWidget);
      final x0 = tester.getTopLeft(rich).dx;

      // Lewati ke tengah transisi (timer 3,4 dtk + ~300 ms).
      await tester.pump(const Duration(milliseconds: 3200));
      await tester.pump(const Duration(milliseconds: 250));
      final during = find.textContaining('Cari ', findRichText: true);
      expect(during, findsNWidgets(2), reason: 'lama & baru tampil bersama');
      for (final e in during.evaluate()) {
        expect(tester.getTopLeft(find.byWidget(e.widget)).dx, closeTo(x0, 0.5),
            reason: 'tidak ada geseran horizontal (hanya vertikal)');
      }
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.textContaining('Cari ', findRichText: true), findsOneWidget);
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'teks di bawah stiker: bawaan, kustom dari setting (hasil '
        'sync), dan kunci ikut tersinkron', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      expect(find.text('Mau jual apa hari ini?'), findsOneWidget);
      await _drain(tester);

      await db.setSetting('kasir_landing_title', 'Selamat datang di Toko Maju');
      await db.setSetting('kasir_landing_subtitle', 'Silakan scan barang Anda');
      await _pumpKasir(tester, db, prefs: modern);
      expect(find.text('Selamat datang di Toko Maju'), findsOneWidget);
      expect(find.text('Silakan scan barang Anda'), findsOneWidget);
      expect(find.text('Mau jual apa hari ini?'), findsNothing);

      for (final k in [
        'kasir_landing_title',
        'kasir_landing_subtitle',
        'kasir_sticker_landing',
        'kasir_sticker_notfound',
      ]) {
        expect(AppDatabase.syncableSettingKeys.contains(k), isTrue,
            reason: '$k harus ikut sync');
      }
      await _drain(tester);
      await db.close();
    });
  });

  group('fokus & kursor kolom cari (9 Okt)', () {
    testWidgets(
        'ketik -> hapus sampai kosong (backspace) -> landing, KEYBOARD '
        'TETAP (fokus tetap)', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      final field = find.byKey(const Key('modern-search'));
      FocusNode node() => tester.widget<TextField>(field).focusNode!;

      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'g');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kasir-landing')), findsNothing);
      expect(node().hasFocus, isTrue);

      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
      expect(node().hasFocus, isTrue, reason: 'fokus tak boleh hilang');

      // Tombol X saat ada teks: hapus + tetap fokus.
      await tester.enterText(field, 'gula');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modern-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
      expect(node().hasFocus, isTrue);
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'regresi kursor: EditableText TIDAK dibangun ulang saat seleksi-semua '
        'dan kosong/berisi berganti (state identik, fokus tetap)',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);
      final field = find.byKey(const Key('modern-search'));
      EditableTextState st() =>
          tester.state<EditableTextState>(find.byType(EditableText));
      FocusNode node() => tester.widget<TextField>(field).focusNode!;

      await tester.tap(field);
      await tester.pump();
      final first = st();
      await tester.enterText(field, 'gula');
      await tester.pumpAndSettle();
      expect(identical(st(), first), isTrue, reason: 'berisi');

      // Keluar lalu ketuk lagi -> seleksi-semua (blok membulat muncul).
      node().unfocus();
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modern-search-selection')), findsOneWidget);
      expect(identical(st(), first), isTrue, reason: 'seleksi-semua');
      expect(node().hasFocus, isTrue);

      // Seleksi-semua -> kosong (slot hint masuk, slot seleksi keluar).
      await tester.tap(find.byKey(const Key('modern-search-clear')));
      await tester.pumpAndSettle();
      expect(identical(st(), first), isTrue, reason: 'kosong');
      expect(node().hasFocus, isTrue);

      await tester.enterText(field, 'abc');
      await tester.pumpAndSettle();
      expect(identical(st(), first), isTrue);
      await _drain(tester);
      await db.close();
    });
  });

  group('cart bar: nominal dinamis (9 Okt)', () {
    testWidgets('nominal 9 digit tetap SATU baris & tidak overflow di 360dp',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Emas Batang', price: 999999999);
      await _pumpKasir(tester, db,
          prefs: modern, size: const Size(360, 800), textScale: 1.3);
      await tester.enterText(find.byKey(const Key('modern-search')), 'emas');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      final amount = find.descendant(
          of: find.byKey(const Key('modern-cart-bar')),
          matching: find.text(formatRupiah(999999999)));
      expect(amount, findsOneWidget);
      expect(tester.takeException(), isNull);
      final h = tester.getSize(amount).height;
      expect(h, lessThan(60), reason: 'satu baris (tidak pecah dua)');
      final bar = tester.getRect(find.byKey(const Key('modern-cart-bar')));
      expect(tester.getRect(amount).right, lessThan(bar.right));
      await _drain(tester);
      await db.close();
    });
  });

  group('pencarian global', () {
    testWidgets(
        'kategori terpilih + mengetik = hasil dari SEMUA produk; '
        'kolom cari dikosongkan = kembali ke kategori', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
          id: const Value(910), name: const Value('Minuman')));
      await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
          id: const Value(911), name: const Value('Snack')));
      Future<void> addIn(String name, int group) async {
        final id = await _addProduct(db, name);
        await (db.update(db.products)..where((t) => t.id.equals(id)))
            .write(ProductsCompanion(productGroupId: Value(group)));
      }

      await addIn('Teh Botol', 910);
      await addIn('Keripik Singkong', 911);
      await _pumpKasir(tester, db,
          prefs: {...modern, 'kasir_grid_view': false});

      await tester.tap(find.byKey(const Key('landing-cat-910')));
      await tester.pumpAndSettle();
      expect(find.text('Teh Botol'), findsOneWidget);
      expect(find.text('Keripik Singkong'), findsNothing,
          reason: 'kategori Minuman: tanpa Snack');

      await tester.enterText(find.byKey(const Key('modern-search')), 'keripik');
      await tester.pumpAndSettle();
      expect(find.text('Keripik Singkong'), findsOneWidget,
          reason: 'pencarian global: produk di kategori lain tetap ketemu');
      expect(find.text('Teh Botol'), findsNothing);

      await tester.enterText(find.byKey(const Key('modern-search')), '');
      await tester.pumpAndSettle();
      expect(find.text('Teh Botol'), findsOneWidget);
      expect(find.text('Keripik Singkong'), findsNothing,
          reason: 'kosongkan teks -> filter kategori berlaku lagi');
      await _drain(tester);
      await db.close();
    });
  });

  group('keyboard di landing', () {
    testWidgets(
        'kolom cari TIDAK bergeser saat keyboard naik (posisi dari '
        'ukuran layar, bukan area yang menyusut) - tanpa layout ulang '
        'sapaan', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern, size: const Size(430, 900));
      double y() =>
          tester.getTopLeft(find.byKey(const Key('modern-search-pill'))).dy;
      final before = y();
      tester.view.viewInsets = const FakeViewPadding(bottom: 1200);
      addTearDown(tester.view.resetViewInsets);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(y(), closeTo(before, 1),
          reason: 'pil tetap di tempat saat keyboard terbuka');
      expect(find.byKey(const Key('kasir-landing')), findsOneWidget);
      await _drain(tester);
      await db.close();
    });
  });

  group('keyboard & cart bar tetap di bawah', () {
    testWidgets(
        'Scaffold tidak mengecil; cart bar TETAP di bawah saat '
        'keyboard terbuka; list diberi ruang bawah setinggi keyboard',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db,
          prefs: {...modern, 'kasir_grid_view': false},
          size: const Size(430, 900));
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.descendant(
          of: find.byType(KasirScreen), matching: find.byType(Scaffold)));
      expect(scaffold.resizeToAvoidBottomInset, isFalse);

      double barY() =>
          tester.getTopLeft(find.byKey(const Key('modern-cart-bar'))).dy;
      final yBefore = barY();
      double listBottomPad() {
        final lv = tester.widget<ListView>(find
            .descendant(
                of: find.byType(KasirScreen), matching: find.byType(ListView))
            .first);
        return (lv.padding as EdgeInsets).bottom;
      }

      final padBefore = listBottomPad();
      tester.view.viewInsets = const FakeViewPadding(bottom: 1200);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(barY(), closeTo(yBefore, 1),
          reason: 'cart bar tidak naik oleh keyboard (tertutup keyboard)');
      expect(listBottomPad(), greaterThan(padBefore + 100),
          reason: 'daftar diberi ruang bawah agar baris terakhir bisa '
              'digulir ke atas keyboard');
      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'daftar menggulir di belakang cart bar (extendBody) & diberi ruang '
        'setinggi cart bar', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db,
          prefs: {...modern, 'kasir_grid_view': false},
          size: const Size(430, 900));
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();
      final scaffold = tester.widget<Scaffold>(find.descendant(
          of: find.byType(KasirScreen), matching: find.byType(Scaffold)));
      expect(scaffold.extendBody, isTrue);
      final lv = tester.widget<ListView>(find
          .descendant(
              of: find.byType(KasirScreen), matching: find.byType(ListView))
          .first);
      final barH = tester
          .getSize(find.byKey(const Key('modern-cart-bar')))
          .height;
      expect((lv.padding as EdgeInsets).bottom, greaterThanOrEqualTo(barH));
      await _drain(tester);
      await db.close();
    });

    testWidgets('cart bar: ada jarak ke tepi & kartu kontras dgn latar',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern, size: const Size(430, 900));
      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      final r = tester.getRect(find.byKey(const Key('modern-cart-bar')));
      expect(r.left, greaterThanOrEqualTo(12), reason: 'jarak kiri');
      expect(430 - r.right, greaterThanOrEqualTo(12), reason: 'jarak kanan');
      final scaffold = tester.widget<Scaffold>(find.descendant(
          of: find.byType(KasirScreen), matching: find.byType(Scaffold)));
      final card = tester
          .widget<Container>(find.byKey(const Key('modern-cart-bar')))
          .decoration as BoxDecoration;
      expect(card.color, isNot(scaffold.backgroundColor),
          reason: 'kartu putih beda dgn latar -> tidak menyatu');
      await _drain(tester);
      await db.close();
    });
  });
}
