import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Bug lapor user: scan kode `#PSN:` (handoff pegawai) lewat scanner
/// EKSTERNAL (HID/keyboard-wedge) — bukan kamera — salah rute ke "Tempel
/// Pesanan" alih-alih antrian. Akar masalah: payload `#PSN:` multi-baris
/// (kode mesin + baris opsional `Pegawai:`/`Nama:`), tapi scanner eksternal
/// keyboard-wedge mengirim newline DI DALAM payload QR sebagai keystroke
/// Enter TERPISAH — jadi 1 scan QR pecah jadi beberapa "scan" beruntun dari
/// sudut pandang `_onHardwareKey`. Baris `#PSN:...` tiba SENDIRIAN tanpa
/// baris `Pegawai:` yang menyusul beberapa puluh/ratus ms kemudian.
///
/// Test ini mensimulasikan raw HID key event via `tester.sendKeyEvent`
/// (BUKAN `mobile_scanner`/kamera) — beda dari `kasir_scan_order_code_test.dart`
/// yang pakai fake platform kamera. `_onHardwareKey` didaftarkan lewat
/// `HardwareKeyboard.instance.addHandler`, jalur RAW key event (bukan kanal
/// IME/TextField) — `sendKeyEvent(..., character: ch)` menjangkaunya (beda
/// dari gotcha lama soal TextField yang TIDAK bisa menerima digit via raw
/// key event, itu soal jalur IME `EditableText`, bukan handler mentah ini).
void main() {
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

  Future<void> pumpKasir(WidgetTester tester, AppDatabase db) async {
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
  }

  /// Ketik 1 "baris" HID lalu Enter — meniru satu keystroke-burst dari
  /// scanner keyboard-wedge (yang mengirim newline di dalam payload SEBAGAI
  /// Enter terpisah, bukan sebagai karakter '\n' biasa).
  Future<void> hidLine(WidgetTester tester, String line) async {
    for (final rune in line.runes) {
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA,
          character: String.fromCharCode(rune));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  }

  testWidgets(
      'scan #PSN: via HID eksternal: baris kode mesin + baris "Pegawai:" '
      'terpisah (2 keystroke-burst) DIGABUNG lagi → masuk antrian, BUKAN '
      'Tempel Pesanan', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await pumpKasir(tester, db);

    // Simulasikan scanner keyboard-wedge: newline DI DALAM payload QR
    // terkirim sebagai Enter terpisah → 2 burst tiba beruntun cepat.
    await hidLine(tester, '#PSN:u1=2');
    await hidLine(tester, 'Pegawai: Budi');

    // Lewati jendela gabung (350ms) supaya timer finalize jalan.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Tempel Pesanan'), findsNothing,
        reason: 'HARUS masuk antrian, bukan salah rute ke Tempel Pesanan '
            '(baris Pegawai: harus sempat tergabung dulu)');

    final rows = await db.select(db.heldOrders).get();
    expect(rows, hasLength(1));
    expect(rows.first.cartJson, contains('"employeeName":"Budi"'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'scan #PSN: via HID eksternal TANPA baris lanjutan (pesanan pelanggan '
      'satu baris) tetap diproses normal setelah jendela gabung lewat',
      (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());

    await pumpKasir(tester, db);

    await hidLine(tester, '#PSN:u1=3');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Tempel Pesanan'), findsOneWidget,
        reason: 'tanpa baris Pegawai: sama sekali → tetap alur pesanan '
            'pelanggan biasa (Tempel Pesanan), bukan antrian');
    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
