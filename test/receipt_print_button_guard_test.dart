import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Regresi — tombol cetak struk (`Icons.print_outlined`, tooltip "Cetak
/// Struk") tidak punya guard `_isPrinting`: tap cepat berulang selagi
/// rangkaian async `_printReceipt` (getSavedMac -> ensurePermissions ->
/// _getStorePrefs -> `PrinterService.printReceipt` -> connect -> write)
/// masih berjalan bisa memicu 2 write BERSAMAAN ke socket Bluetooth
/// printer yang SAMA — native `doWrite` (`MainActivity.kt`) SPAWN THREAD
/// BARU tiap panggilan MethodChannel `write`, TANPA sinkronisasi apa pun
/// di level native, sehingga byte stream ESC/POS 2 print bisa
/// ke-interleave/rusak (struk dobel/garbled), bukan cuma "tercetak dua
/// kali" yang tampak jinak.
///
/// Setup mock channel `com.thepos/bt_print` (channel CUSTOM app ini,
/// bukan channel internal package `print_bluetooth_thermal`) + channel
/// `permission_handler` supaya `_printReceipt` benar2 melewati SELURUH
/// rangkaian sampai native `write` — bukan early-return "printer belum
/// dikonfigurasi"/"izin ditolak" yang tidak membuktikan apa-apa soal
/// guard konkurensi. `status` di-mock `true` (anggap Bluetooth SUDAH
/// terhubung) supaya `PrinterService.connect()` lewat jalur cepat tanpa
/// jeda stabilisasi 600ms — bagian rangkaian yang genap MELIBATKAN kerja
/// async nyata (load asset profil printer via `CapabilityProfile.load()`)
/// makanya dibungkus `tester.runAsync()` (bukan `tester.pump(duration)`
/// biasa) — pola ini WAJIB dipakai di sini, sudah dibuktikan lewat
/// eksperimen: `pump(duration)` SENDIRIAN tidak bisa memajukan kerja
/// tersebut (macet permanen), sedangkan `runAsync` + `pump` bergantian
/// berhasil menyelesaikannya.
///
/// Inti pembuktian: tombol di-tap 2x SANGAT CEPAT (tanpa `pump` di
/// antaranya, supaya tap kedua diproses SELAGI rangkaian async tap
/// pertama masih berjalan) — channel `write` (satu-satunya titik yang
/// benar2 mengirim byte ke socket printer) WAJIB cuma terpanggil TEPAT
/// 1x. 2x berarti guard bocor: 2 instance `_printReceipt` berjalan
/// bersamaan, persis skenario yang bisa merusak byte stream ESC/POS di
/// socket Bluetooth yang sama.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedTx() async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 8000,
        subtotal: 10000));
    return txId;
  }

  /// Mock channel custom printer app ini (`com.thepos/bt_print`, dipakai
  /// langsung oleh `PrinterService` — BUKAN channel internal package
  /// `print_bluetooth_thermal`) + channel `permission_handler`, supaya
  /// `_printReceipt` bisa lewat SELURUH rangkaian sampai `write` — bukan
  /// early-return "printer belum dikonfigurasi"/"izin ditolak" (yang
  /// tidak membuktikan apa2 soal guard konkurensi). `status` -> true
  /// (anggap sudah terhubung) supaya `PrinterService.connect()` lewat
  /// jalur cepat, TIDAK melalui jeda stabilisasi 600ms (`Future.delayed`
  /// di kode produksi) yang sengaja DIHINDARI di sini — bukan krn tidak
  /// relevan, tapi krn jalur "sudah terhubung" tetap 100% valid
  /// membuktikan guard konkurensi tanpa perlu menyentuh jeda tsb sama
  /// sekali. [writeCalls] menghitung tiap kali method `write` terpanggil.
  void mockPrinterChannels(List<String> writeCalls) {
    const btChannel = MethodChannel('com.thepos/bt_print');
    const permChannel =
        MethodChannel('flutter.baseflow.com/permissions/methods');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(btChannel, (call) async {
      switch (call.method) {
        case 'status':
          return true; // sudah terhubung -> connect() jalur cepat
        case 'write':
          writeCalls.add(call.method);
          return {'ok': true};
        case 'disconnect':
          return null;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(btChannel, null));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permChannel, (call) async {
      if (call.method == 'requestPermissions') {
        // bluetoothScan=28, bluetoothConnect=30 -> granted(1) keduanya.
        return {28: 1, 30: 1};
      }
      if (call.method == 'checkPermissionStatus') return 1;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permChannel, null));
  }

  testWidgets(
      'tombol cetak struk di-tap 2x cepat berurutan -> channel write '
      'CUMA terpanggil 1x (guard _isPrinting mencegah 2 instance '
      '_printReceipt berjalan bersamaan)', (tester) async {
    final txId = await seedTx();
    final writeCalls = <String>[];
    mockPrinterChannels(writeCalls);

    await pumpWithFakeApp(tester,
        db: db,
        child: ReceiptScreen(transactionId: txId),
        initialPrefs: {'printer_mac': 'AA:BB:CC:DD:EE:FF'});

    final printButtonFinder = find.byTooltip('Cetak Struk');
    expect(printButtonFinder, findsOneWidget);
    final iconButtonFinder = find.ancestor(
        of: printButtonFinder, matching: find.byType(IconButton));
    IconButton btn() => tester.widget<IconButton>(iconButtonFinder);

    expect(btn().onPressed, isNotNull,
        reason: 'tombol harus aktif sebelum dicetak sama sekali');

    // Tap 2x SANGAT CEPAT — SENGAJA tanpa `pump()` di antara keduanya,
    // supaya tap kedua diproses SELAGI rangkaian async tap pertama masih
    // berjalan (persis skenario "tap dobel cepat" di dunia nyata).
    await tester.tap(printButtonFinder);
    await tester.tap(printButtonFinder, warnIfMissed: false);

    // Selesaikan rangkaian async (termasuk kerja async NYATA spt load
    // asset profil printer) — `runAsync` diselingi `pump` per iterasi
    // (lihat dok kelas di atas kenapa `pump(duration)` saja tidak cukup).
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (writeCalls.isNotEmpty) break;
    }

    expect(writeCalls, hasLength(1),
        reason: 'channel write cuma boleh terpanggil TEPAT 1x walau '
            'tombol di-tap 2x cepat berurutan — 2x berarti guard bocor '
            'dan 2 write bisa terjadi BERSAMAAN ke socket Bluetooth '
            'printer yang sama (byte stream ESC/POS bisa ke-interleave/'
            'rusak)');

    // try/finally harus SELALU melepas guard setelah rangkaian selesai —
    // tombol tidak boleh permanen terkunci.
    await tester.pump();
    expect(btn().onPressed, isNotNull,
        reason: 'try/finally harus SELALU melepas guard setelah selesai, '
            'tombol tidak boleh permanen terkunci');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
