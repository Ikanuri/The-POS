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
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Fitur "Pra-Bayar" — Item 4 (transfer QR/`#PSN:`): entri Pra-Bayar dari
/// kode transfer HANYA boleh diadopsi (masuk `cartPrabayarProvider`) kalau
/// device PENERIMA JUGA bergerbang `terima_pembayaran` — kalau tidak, DIBUANG
/// SEPENUHNYA (item barang tetap masuk normal). Pola fake scanner & harness
/// SAMA PERSIS dgn `kasir_handoff_price_mismatch_test.dart`.
class _FakeMobileScannerPlatform extends MobileScannerPlatform {
  final _barcodesController = StreamController<BarcodeCapture?>.broadcast();
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

Future<String> _seedProduct(AppDatabase db) async {
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
        price: 3000,
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

  String handoffCode() => OrderParserService.encodeHandoff(
        items: [
          const CartItem(
            productId: 'p1',
            productUnitId: 'u1',
            productName: 'Sedap Goreng',
            unitName: 'Pcs',
            qty: 2,
            price: 3000,
            originalPrice: 3000,
            costPrice: 2000,
          ),
        ],
        employeeName: 'Budi',
        prabayar: const [
          (amount: 25000, method: 'tunai', methodName: null, lockedAtMs: 1700000000000),
        ],
      );

  Future<ProviderContainer> pumpKasir(
    WidgetTester tester,
    AppDatabase db,
    DeviceIdentity device,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = device),
    ]);
    addTearDown(container.dispose);

    // Keranjang aktif SUDAH ada isi → kode masuk lewat jalur merge langsung
    // (bukan antrian held_orders) — sama seperti pola mismatch harga.
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
      child: const MaterialApp(home: Scaffold(body: KasirScreen())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await tester.pumpAndSettle();

    return container;
  }

  testWidgets(
      'penerima BERGERBANG (owner) menerima transfer dgn Pra-Bayar → entri '
      'DIADOPSI ke cartPrabayarProvider, item barang tetap masuk normal',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedProduct(db);
    addTearDown(() async => db.close());

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'K1',
      deviceRole: 'owner', // Owner TIDAK PERNAH digerbang.
    );

    final container = await pumpKasir(tester, db, fakeDevice);

    fake.emitBarcode(handoffCode());
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    expect(cart.any((c) => c.productId == 'p1'), isTrue,
        reason: 'barang tetap masuk normal apa pun status Pra-Bayar');

    final prabayar = container.read(cartPrabayarProvider(kMainCartId));
    expect(prabayar, hasLength(1));
    expect(prabayar.single.amount, 25000);
    expect(prabayar.single.method, 'tunai');
    expect(prabayar.single.lockedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
        reason: 'lockedAt ASLI dari pengirim harus terbawa utuh');

    await drain(tester);
  });

  testWidgets(
      'penerima TIDAK bergerbang (pegawai tanpa izin terima_pembayaran) '
      'menerima transfer dgn Pra-Bayar → entri DIBUANG SEPENUHNYA, item '
      'barang tetap masuk normal', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _seedProduct(db);
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(const KasirPermissionsCompanion(isEnabled: Value(false)));
    addTearDown(() async => db.close());

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Kasir 2',
      deviceCode: 'K2',
      deviceRole: 'kasir', // Pegawai TANPA izin bayar → digerbang.
    );

    final container = await pumpKasir(tester, db, fakeDevice);

    fake.emitBarcode(handoffCode());
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider(kMainCartId));
    expect(cart.any((c) => c.productId == 'p1'), isTrue,
        reason: 'barang tetap masuk normal walau Pra-Bayar dibuang');

    final prabayar = container.read(cartPrabayarProvider(kMainCartId));
    expect(prabayar, isEmpty,
        reason: 'penerima tak bergerbang → Pra-Bayar dibuang sepenuhnya, '
            'BUKAN sebagian');

    await drain(tester);
  });
}
