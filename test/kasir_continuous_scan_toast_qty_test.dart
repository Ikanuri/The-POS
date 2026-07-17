import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Bug dilaporkan user: toast melayang mode scan berulang (continuous scan)
/// membulatkan qty ke integer (`.round()`) sebelum ditampilkan — produk
/// dgn qty pecahan (mis. 0.25 kg, produk timbang) jadi tampil salah di
/// toast (mis. "1" padahal seharusnya "1.25"). Pola fake scanner sama
/// seperti `kasir_tap_to_scan_test.dart` — reuse seam platform
/// `mobile_scanner`, bukan mock logika bisnis.
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

  Future<AppDatabase> seedProduct(String barcode) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Bawang Merah'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1',
          productUnitId: 'u1',
          minQty: const Value(1),
          price: 40000,
        ));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'b1',
          productUnitId: 'u1',
          barcode: barcode,
          isPrimary: const Value(true),
        ));
    return db;
  }

  testWidgets(
      'toast mode scan berulang menampilkan qty pecahan APA ADANYA (1.25), '
      'BUKAN dibulatkan ke integer (dulu tampil "1")', (tester) async {
    const barcode = '8991234567890';
    final db = await seedProduct(barcode);
    addTearDown(() async => db.close());

    // Keranjang sudah berisi 0.25 (mis. sisa timbangan sebelumnya) sebelum
    // discan lagi — scan repeat menambah +1 (item barcode biasa, bukan
    // barcode timbang), hasil akhir seharusnya 1.25 (bukan 1).
    const existing = CartItem(
      productId: 'p1',
      productUnitId: 'u1',
      productName: 'Bawang Merah',
      unitName: 'Kg',
      qty: 0.25,
      price: 40000,
      originalPrice: 40000,
      costPrice: 0,
    );
    SharedPreferences.setMockInitialValues({
      'cart_v1_main': jsonEncode([existing.toJson()]),
      'scanner_continuous': true,
      // Matikan hint swipe-ke-atas (bug overflow TIDAK TERKAIT sudah ada di
      // teks hint itu sendiri, lihat kasir_screen.dart:2948 — di luar scope
      // test ini, jangan sampai test qty ini gagal krn bug lain).
      'kasir_swipe_hint_count': 3,
    });

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Kasir',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
    await tester.pumpAndSettle();

    fake.emitBarcode(barcode);
    await tester.pumpAndSettle();

    expect(find.text('1.25'), findsOneWidget,
        reason: 'qty efektif 0.25 + 1 (scan repeat) = 1.25, harus tampil '
            'persis, bukan dibulatkan jadi "1"');
    expect(find.text('1'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
