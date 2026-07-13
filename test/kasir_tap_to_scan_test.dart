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
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Item 24e — tap-to-scan. `mobile_scanner` tidak punya platform kamera asli
/// di test env, tapi package-nya federated (ada `MobileScannerPlatform`
/// pluggable) — jadi kita pasang implementasi palsu yang bisa "menembakkan"
/// hasil scan kapan saja, mirip pola `HttpOverrides` untuk test sync LAN:
/// menyambung ke seam platform yang nyata, bukan mock logika bisnisnya.
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

Future<void> _pumpKasirWithScannerOpen(
  WidgetTester tester,
  AppDatabase db,
) async {
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
        ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1',
          productUnitId: 'u1',
          minQty: const Value(1),
          price: 2500,
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
      'mode default (tap-to-scan OFF): barcode terdeteksi langsung diproses '
      'tanpa perlu tap tombol bidik', (tester) async {
    final db = await seedProduct('8991234567890');
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    // Tombol bidik manual ada di tree tapi non-aktif (IgnorePointer) saat
    // tap-to-scan nonaktif (default) — tap di posisinya harus TIDAK hit-test
    // (warnIfMissed:false karena kegagalan hit-test justru yang dibuktikan).
    await tester.tap(find.byKey(const Key('scan_shutter_button')),
        warnIfMissed: false);
    await tester.pump();
    expect(find.text('1'), findsNothing,
        reason: 'tombol bidik tidak bisa ditap saat tap-to-scan OFF');

    fake.emitBarcode('8991234567890');
    await tester.pumpAndSettle();

    // Scanner auto-close setelah scan sekali sukses (perilaku lama, di luar
    // scope 24e) — dan produk benar-benar masuk keranjang (lingkaran "+"
    // berubah jadi label qty "1").
    expect(find.byIcon(Icons.arrow_back), findsNothing,
        reason: 'scanner harus otomatis tertutup (mode sekali-scan)');
    expect(find.text('1'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap-to-scan ON: barcode terdeteksi DITAHAN, baru diproses setelah '
      'tombol bidik ditap', (tester) async {
    final db = await seedProduct('8991234567890');
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    await tester.tap(find.text('Tap to Scan'));
    await tester.pumpAndSettle();

    fake.emitBarcode('8991234567890');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Belum diproses — masih di layar scanner, produk belum ke keranjang.
    expect(find.text('Sedap Goreng'), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget,
        reason: 'scanner belum menutup, barcode masih ditahan');

    final shutter = find.byKey(const Key('scan_shutter_button'));
    expect(shutter, findsOneWidget);
    await tester.tap(shutter);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing,
        reason: 'scanner tertutup setelah barcode ditahan diproses');
    expect(find.text('1'), findsWidgets,
        reason: 'setelah tap tombol bidik, barcode yang ditahan diproses');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap-to-scan ON + mode Berulang: tap bidik lagi TANPA barcode baru '
      'terdeteksi (kamera diarahkan ke tempat kosong) TIDAK mengulang scan '
      'produk sebelumnya', (tester) async {
    final db = await seedProduct('8991234567890');
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    // Mode Berulang — scanner TETAP terbuka setelah scan sukses (beda dari
    // mode Sekali yang auto-close), supaya tap bidik kedua bisa terjadi
    // sama sekali tanpa deteksi baru — ini kondisi yang memicu bug lama.
    await tester.tap(find.text('Berulang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to Scan'));
    await tester.pumpAndSettle();

    fake.emitBarcode('8991234567890');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final shutter = find.byKey(const Key('scan_shutter_button'));
    await tester.tap(shutter);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsOneWidget,
        reason: 'mode Berulang — scanner tetap terbuka setelah scan sukses');
    expect(find.text('1'), findsWidgets,
        reason: 'barang pertama berhasil masuk (qty 1)');

    // Cek langsung ikon tombol bidik (abu-abu = nonaktif, `enabled: false`
    // di `_ScanShutterButton`) — BUKAN tap-lagi-lalu-cek-qty, karena
    // `_handleBarcode` punya debounce 1.5 detik per-barcode yang sama; di
    // widget test dua tap terjadi nyaris seketika (real wall-clock, tidak
    // ikut fast-forward `tester.pump`), jadi debounce itu SENDIRI sudah
    // menyembunyikan bug lama (`_pendingBarcode` yang tak pernah
    // dikosongkan) — assertion qty basi/false-negative kalau tetap dipakai.
    final icon = tester.widget<Icon>(find.descendant(
      of: shutter,
      matching: find.byIcon(Icons.center_focus_strong),
    ));
    expect(icon.color, Colors.grey,
        reason: 'tombol bidik harus nonaktif (abu-abu) segera setelah '
            'barcode ditahan berhasil diproses — TANPA deteksi baru, tidak '
            'ada apa pun lagi yang bisa diulang');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap-to-scan ON + mode Berulang: deteksi BASI dari barcode yang BARU '
      'SAJA dikonfirmasi (kamera lambat "catch up" walau barcode sudah '
      'disingkirkan fisik) TIDAK mengisi ulang tombol bidik', (tester) async {
    final db = await seedProduct('8991234567890');
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    await tester.tap(find.text('Berulang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tap to Scan'));
    await tester.pumpAndSettle();

    fake.emitBarcode('8991234567890');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final shutter = find.byKey(const Key('scan_shutter_button'));
    await tester.tap(shutter);
    await tester.pumpAndSettle();

    // Kamera "kejar-mengejar" (frame basi) MASIH melaporkan barcode yang
    // sama SESAAT setelah confirm, walau secara fisik barcode itu sudah
    // disingkirkan pengguna — ini persis kondisi race yang dilaporkan user.
    fake.emitBarcode('8991234567890');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final icon = tester.widget<Icon>(find.descendant(
      of: shutter,
      matching: find.byIcon(Icons.center_focus_strong),
    ));
    expect(icon.color, Colors.grey,
        reason: 'deteksi basi dari barcode yang baru dikonfirmasi TIDAK '
            'boleh meng-isi ulang _pendingBarcode — tombol harus tetap '
            'nonaktif sampai ada barcode BARU (atau barcode LAMA lagi '
            'setelah jendela cooldown lewat) yang benar-benar terdeteksi');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap-to-scan ON: tombol bidik nonaktif (abu-abu, tidak bisa ditap) '
      'sebelum ada barcode terdeteksi', (tester) async {
    final db = await seedProduct('8991234567890');
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    await tester.tap(find.text('Tap to Scan'));
    await tester.pumpAndSettle();

    // Tap tombol bidik SEBELUM ada barcode ditahan → tidak melakukan apa-apa.
    final shutter = find.byKey(const Key('scan_shutter_button'));
    expect(shutter, findsOneWidget);
    await tester.tap(shutter);
    await tester.pumpAndSettle();

    expect(find.text('Sedap Goreng'), findsNothing,
        reason: 'tombol bidik tanpa barcode ditahan harus no-op');
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
