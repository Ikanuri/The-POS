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
        price: 10000,
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
            data: MediaQuery.of(c).copyWith(disableAnimations: reduced),
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
    testWidgets(
        'landing = rail ikon (tanpa header Klasik, tanpa tombol scan '
        'di rail); mengetik = lingkaran tunggal yang mengembang saat diketuk',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);

      expect(find.byKey(const Key('fab-rail')), findsOneWidget);
      for (final k in ['history', 'held', 'paste', 'sync', 'grid', 'theme']) {
        expect(find.byKey(Key('fab-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('fab-main')), findsNothing);
      // Scan hanya di kolom cari.
      expect(find.byKey(const Key('modern-scan')), findsOneWidget);
      // Header Klasik tidak ada (label tombol Klasik).
      expect(find.text('Antrian'), findsNothing);

      await tester.enterText(find.byKey(const Key('modern-search')), 'gula');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fab-rail')), findsNothing);
      expect(find.byKey(const Key('fab-main')), findsOneWidget);
      expect(find.byKey(const Key('fab-history')), findsNothing,
          reason: 'menyusut: harus diketuk dulu untuk mengembang');

      await tester.tap(find.byKey(const Key('fab-main')));
      await tester.pumpAndSettle();
      double y(String t) => tester.getCenter(find.text(t)).dy;
      expect(y('Riwayat Transaksi'), greaterThan(y('Antrian Pesanan')));
      expect(y('Antrian Pesanan'), greaterThan(y('Tempel Pesanan')));
      expect(y('Tempel Pesanan'), greaterThan(y('Sync LAN')),
          reason: 'urutan dari bawah: Riwayat, Antrian, Tempel, Sync');
      expect(find.byKey(const Key('fab-scrim')), findsOneWidget);

      // Ketuk latar menutup lagi.
      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fab-history')), findsNothing);
      expect(find.byKey(const Key('fab-main')), findsOneWidget);

      await _drain(tester);
      await db.close();
    });

    testWidgets(
        'Tempel Pesanan membuka sheet; Sync LAN membuka pop-up kecil '
        '(owner: Jadi host)', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern);

      await tester.tap(find.byKey(const Key('fab-paste')));
      await tester.pumpAndSettle();
      expect(find.byType(PasteOrderSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(PasteOrderSheet))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fab-sync')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-sync-dialog')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-host')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-ip')), findsNothing);

      await _drain(tester);
      await db.close();
    });

    testWidgets('Sync LAN untuk kasir: kolom IP/Token + Sinkron sekarang',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await _addProduct(db, 'Gula Pasir');
      await _pumpKasir(tester, db, prefs: modern, deviceRole: 'kasir');
      await tester.tap(find.byKey(const Key('fab-sync')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quick-sync-ip')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-token')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-go')), findsOneWidget);
      expect(find.byKey(const Key('quick-sync-host')), findsNothing);
      // Tanpa IP/Token -> pesan, tidak crash.
      await tester.tap(find.byKey(const Key('quick-sync-go')));
      await tester.pumpAndSettle();
      expect(find.text('Isi IP dan Token host dulu'), findsOneWidget);
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

      await tester.tap(find.byKey(const Key('fab-theme')));
      await tester.pump();
      expect(container.read(themeModeProvider), ThemeMode.dark);

      final before = container.read(kasirGridProvider);
      await tester.tap(find.byKey(const Key('fab-grid')));
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
}
