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

/// Item 24d — scan kode `#PSN:` (bukan barcode produk biasa) lewat scanner
/// kasir yang sudah ada. Dua alur: baris "Pegawai:" ada → masuk antrian
/// held_orders (awaitingPayment); tidak ada → buka "Tempel Pesanan"
/// pra-diisi (alur pesanan pelanggan yang sudah ada, cuma pemicunya baru).
///
/// Pola fake scanner sama seperti `kasir_tap_to_scan_test.dart` — reuse
/// platform interface `mobile_scanner` yang federated, bukan mock logika
/// bisnis.
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
    deviceName: 'Owner',
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

  Future<AppDatabase> seedProduct() async {
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
    return db;
  }

  testWidgets(
      'scan kode #PSN: dgn baris "Pegawai:" → masuk antrian held_orders '
      '(awaitingPayment), scanner tertutup, banner sukses', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    fake.emitBarcode('#PSN:u1=2;\nPegawai: Budi');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing,
        reason: 'scanner harus tertutup setelah kode pesanan diproses');
    expect(find.textContaining('Pesanan dari Budi masuk antrian'),
        findsOneWidget);

    final rows = await db.select(db.heldOrders).get();
    expect(rows, hasLength(1));
    // Susulan Item 24d — label kartu = nama PELANGGAN (tidak ada di sini,
    // tidak ada baris "Nama:"), BUKAN nama pegawai lagi (lihat test
    // terpisah utk kasus dgn "Nama:").
    expect(rows.first.label, 'Tanpa Nama');
    expect(rows.first.cartJson, contains('"awaitingPayment":true'));
    expect(rows.first.cartJson, contains('Sedap Goreng'));
    expect(rows.first.cartJson, contains('"employeeName":"Budi"'));

    // Buka panel antrian → kartu handoff harus beda dari pesanan ditahan
    // biasa (chip terracotta "siap dibayarkan" alih-alih waktu polos, lihat
    // redesign kartu _HeldCard). Nama pegawai tampil di chip status di
    // dalam kartu (susulan Item 24d), bukan di judul kartu.
    await tester.tap(find.byIcon(Icons.pause_circle_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('siap dibayarkan'), findsOneWidget);
    expect(find.text('Tanpa Nama'), findsOneWidget);
    expect(find.textContaining('Budi'), findsWidgets,
        reason: 'nama pegawai tampil di chip status (banner sukses jg masih '
            'menyebutnya, jadi bisa >1 match)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'scan kode #PSN: TANPA baris "Pegawai:" → buka Tempel Pesanan '
      'pra-diisi & otomatis diproses (pesanan pelanggan biasa)',
      (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    fake.emitBarcode('#PSN:u1=3;\nNama: Ani');
    await tester.pumpAndSettle();

    expect(find.text('Tempel Pesanan'), findsOneWidget,
        reason: 'harus membuka sheet Tempel Pesanan, bukan langsung ke keranjang');
    expect(find.text('Nama: Ani'), findsOneWidget);
    expect(find.text('Sedap Goreng'), findsWidgets,
        reason: 'muncul di preview Tempel Pesanan (grid produk di baliknya '
            'juga masih menampilkan nama yang sama)');

    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty,
        reason: 'pesanan pelanggan TIDAK masuk antrian, beda dari handoff pegawai');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'scan kode #PSN: rusak/tidak ada barang dikenali → banner error, '
      'TIDAK masuk antrian atau buka Tempel Pesanan', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    fake.emitBarcode('#PSN:tidak-ada-begini=abc;\nPegawai: Budi');
    await tester.pumpAndSettle();

    expect(find.textContaining('tidak valid'), findsOneWidget);
    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'susulan Item 24d — scan #PSN: dgn baris "Pegawai:" DAN "Nama:" → '
      'kartu antrian judulnya nama PELANGGAN, tab di atasnya nama PEGAWAI '
      '(bukan tertukar seperti bug lama)', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    fake.emitBarcode('#PSN:u1=2;\nPegawai: Budi\nNama: Siti');
    await tester.pumpAndSettle();

    final rows = await db.select(db.heldOrders).get();
    expect(rows, hasLength(1));
    expect(rows.first.label, 'Siti',
        reason: 'judul kartu antrian harus nama PELANGGAN, bukan pegawai');
    expect(rows.first.cartJson, contains('"employeeName":"Budi"'));
    expect(rows.first.cartJson, contains('"customerName":"Siti"'));

    await tester.tap(find.byIcon(Icons.pause_circle_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Siti'), findsOneWidget,
        reason: 'judul kartu = nama pelanggan');
    expect(find.textContaining('Budi ·'), findsOneWidget,
        reason: 'chip status di dalam kartu = nama pegawai pengirim + jam '
            '("·" pembeda dari banner sukses yg jg menyebut Budi)');
    expect(find.textContaining('siap dibayarkan'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'susulan Item 24d — scan #PSN: dgn "Pegawai:" TANPA "Nama:" (pegawai '
      'belum pilih pelanggan) → kartu antrian judulnya "Tanpa Nama", tab '
      'pegawai tetap tampil', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await _pumpKasirWithScannerOpen(tester, db);

    fake.emitBarcode('#PSN:u1=2;\nPegawai: Budi');
    await tester.pumpAndSettle();

    final rows = await db.select(db.heldOrders).get();
    expect(rows.first.label, 'Tanpa Nama');
    expect(rows.first.cartJson, contains('"employeeName":"Budi"'));

    await tester.tap(find.byIcon(Icons.pause_circle_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Tanpa Nama'), findsOneWidget);
    expect(find.textContaining('Budi ·'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
