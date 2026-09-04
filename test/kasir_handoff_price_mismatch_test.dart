import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/order_parser_service.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Susulan (permintaan user): transfer transaksi antar device toko sendiri
/// (`OrderParserService.encodeHandoff`/`.parse`) — kalau pengirim BERWENANG
/// (harga dipercaya mentah, `trustPrices: true`) DAN device PENERIMA ini
/// JUGA berwenang, tapi harga yang dibawa pengirim ternyata BEDA dari
/// resolve fresh lokal device penerima SAAT INI (mis. owner baru saja ubah
/// harga di device lain sebelum sempat sync) — tampilkan peringatan
/// INFORMASIONAL di baris keranjang penerima (`CartItem.priceMismatchLocal`),
/// harga yang DIPAKAI tetap harga pengirim (BUKAN auto-koreksi).
///
/// Pola fake scanner & harness sama seperti `kasir_scan_order_code_test.dart`.
class _FakeMobileScannerPlatform extends MobileScannerPlatform {
  final _barcodesController =
      StreamController<BarcodeCapture?>.broadcast();
  final _torchController = StreamController<TorchState>.broadcast();
  final _zoomController = StreamController<double>.broadcast();

  void emitBarcode(String rawValue) {
    _barcodesController.add(
      BarcodeCapture(barcodes: [Barcode(rawValue: rawValue)]),
    );
  }

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodesController.stream;

  @override
  Stream<TorchState> get torchStateStream => _torchController.stream;

  @override
  Stream<double> get zoomScaleStateStream => _zoomController.stream;

  @override
  Widget buildCameraView() => const SizedBox();

  @override
  Future<void> resetZoomScale() async {}

  @override
  Future<void> setZoomScale(double zoomScale) async {}

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    return const MobileScannerViewAttributes(
      currentTorchMode: TorchState.off,
      numberOfCameras: 1,
      size: Size(100, 100),
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> toggleTorch() async {}

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> dispose() async {}
}

Future<String> _seedProduct(AppDatabase db, {required int livePrice}) async {
  await db
      .into(db.products)
      .insert(ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't1',
        productUnitId: 'u1',
        minQty: const Value(1),
        price: livePrice,
      ));
  return 'u1';
}

void main() {
  late _FakeMobileScannerPlatform fake;
  final MobileScannerPlatform original = MobileScannerPlatform.instance;

  setUp(() {
    fake = _FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = fake;
  });

  tearDown(() {
    MobileScannerPlatform.instance = original;
  });

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  /// Kode transfer transaksi dgn harga pengirim [senderPrice] utk unit 'u1'
  /// qty 2 — pakai `encodeHandoff` sungguhan (bukan format string manual)
  /// supaya persis payload nyata (`trustPrices: true` default).
  String handoffCode(int senderPrice) => OrderParserService.encodeHandoff(
        items: [
          const CartItem(
            productId: 'p1',
            productUnitId: 'u1',
            productName: 'Sedap Goreng',
            unitName: 'Pcs',
            qty: 2,
            price: 0, // diisi di bawah
            originalPrice: 0,
            costPrice: 0,
          ).copyWith(price: senderPrice),
        ],
        employeeName: 'Budi',
      );

  testWidgets(
      'penerima BERWENANG (owner) menerima transfer dari pengirim BERWENANG '
      'dgn harga BEDA dari resolve lokal → CartItem.priceMismatchLocal '
      'terisi harga lokal, badge tampil di CartSheet dgn kedua nominal',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedProduct(db, livePrice: 3000); // Harga LOKAL device ini.
    addTearDown(() async => db.close());

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'K1',
      deviceRole: 'owner', // Owner TIDAK PERNAH digerbang.
    );

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider
          .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    // Keranjang aktif SUDAH ada isi → item hasil scan masuk lewat jalur
    // merge langsung (bukan antrian held_orders) — jalur yg disentuh fix ini.
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'sudahAda',
          productUnitId: 'uSudahAda',
          productName: 'Teh Botol',
          unitName: 'Botol',
          qty: 1,
          price: 4000,
          originalPrice: 4000,
          costPrice: 3000,
        ));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await tester.pumpAndSettle();

    // Pengirim (jg berwenang) kirim dgn harga 2500 — BEDA dari harga lokal
    // penerima (3000, harga sudah naik sejak katalog pengirim dibuat).
    fake.emitBarcode(handoffCode(2500));
    await tester.pumpAndSettle();

    expect(find.textContaining('ditambahkan ke keranjang aktif'),
        findsOneWidget);

    final cart = container.read(cartProvider(kMainCartId));
    final item = cart.firstWhere((c) => c.productId == 'p1');
    expect(item.price, 2500,
        reason: 'harga yg DIPAKAI tetap harga pengirim, bukan koreksi');
    expect(item.priceMismatchLocal, 3000,
        reason: 'field mismatch harus berisi harga fresh LOKAL device ini');

    // Buka sheet keranjang (swipe ke atas) → badge peringatan harus tampil
    // dgn KEDUA nominal (lokal dicoret, dipakai tebal).
    final dragArea = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onVerticalDragEnd != null);
    expect(dragArea, findsOneWidget);
    await tester.fling(dragArea, const Offset(0, -400), 2000);
    await tester.pumpAndSettle();

    expect(find.textContaining('Harga pengirim beda dari lokal'),
        findsOneWidget);
    expect(find.textContaining(formatRupiah(3000)), findsWidgets,
        reason: 'nominal harga lokal (dicoret) harus tampil');
    expect(find.textContaining(formatRupiah(2500)), findsWidgets,
        reason: 'nominal harga yg dipakai (tebal) harus tampil');

    await drain(tester);
  });

  testWidgets(
      'penerima BERWENANG (owner) menerima transfer dgn harga SAMA persis '
      'dgn resolve lokal → TIDAK ada mismatch, badge tidak tampil',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedProduct(db, livePrice: 2500); // SAMA dgn harga pengirim.
    addTearDown(() async => db.close());

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider
          .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'sudahAda',
          productUnitId: 'uSudahAda',
          productName: 'Teh Botol',
          unitName: 'Botol',
          qty: 1,
          price: 4000,
          originalPrice: 4000,
          costPrice: 3000,
        ));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await tester.pumpAndSettle();

    fake.emitBarcode(handoffCode(2500));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final item = cart.firstWhere((c) => c.productId == 'p1');
    expect(item.priceMismatchLocal, isNull);

    final dragArea = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onVerticalDragEnd != null);
    await tester.fling(dragArea, const Offset(0, -400), 2000);
    await tester.pumpAndSettle();

    expect(find.textContaining('Harga pengirim beda dari lokal'),
        findsNothing);

    await drain(tester);
  });

  testWidgets(
      'penerima TIDAK berwenang (pegawai tanpa izin terima_pembayaran) '
      'menerima transfer dgn harga beda dari lokal → SKIP, tidak ada '
      'mismatch/badge (device ini toh tidak berwenang menimbang harga)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedProduct(db, livePrice: 3000);
    // Pastikan izin terima_pembayaran NONAKTIF (default kasirPermissions —
    // dipastikan eksplisit di sini biar tidak bergantung default seed).
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(const KasirPermissionsCompanion(isEnabled: Value(false)));
    addTearDown(() async => db.close());

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Kasir 2',
      deviceCode: 'K2',
      deviceRole: 'kasir', // Pegawai TANPA izin bayar → digerbang.
    );

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider
          .overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
          productId: 'sudahAda',
          productUnitId: 'uSudahAda',
          productName: 'Teh Botol',
          unitName: 'Botol',
          qty: 1,
          price: 4000,
          originalPrice: 4000,
          costPrice: 3000,
        ));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await tester.pumpAndSettle();

    fake.emitBarcode(handoffCode(2500));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    final item = cart.firstWhere((c) => c.productId == 'p1');
    expect(item.price, 2500, reason: 'harga pengirim tetap dipakai apa adanya');
    expect(item.priceMismatchLocal, isNull,
        reason:
            'penerima tak berwenang → skip, device ini toh ke-gate lagi di '
            'tombol Bayar');

    final dragArea = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onVerticalDragEnd != null);
    await tester.fling(dragArea, const Offset(0, -400), 2000);
    await tester.pumpAndSettle();

    expect(find.textContaining('Harga pengirim beda dari lokal'),
        findsNothing);

    await drain(tester);
  });
}
