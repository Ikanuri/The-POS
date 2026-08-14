import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/order_parser_service.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Item 24d — gerbang tombol "Bayar" di `CartSheet`: pegawai (deviceRole
/// 'kasir') TANPA izin `terima_pembayaran` melihat "Kirim ke Owner/Asisten"
/// (tampilkan QR) alih-alih "Bayar" langsung. Owner/Asisten TIDAK PERNAH
/// digerbang.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 2,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
  );

  Future<AppDatabase> pumpCartSheetOpen(
    WidgetTester tester, {
    required String deviceRole,
    bool terimaPembayaran = false,
    String cartId = kMainCartId,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(KasirPermissionsCompanion(isEnabled: Value(terimaPembayaran)));
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Kasir 2',
          deviceCode: 'K2',
          deviceRole: deviceRole,
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(cartId).notifier).addItem(item);

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => CartSheet(cartId: cartId),
                ),
                child: const Text('buka keranjang'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka keranjang'));
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets(
      'pegawai TANPA izin terima_pembayaran: tombol jadi "Kirim ke '
      'Owner/Asisten", tap menampilkan QR', (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: false);
    addTearDown(() async => db.close());

    expect(find.text('Kirim ke Owner/Asisten'), findsOneWidget);
    expect(find.text('Bayar'), findsNothing);

    await tester.tap(find.text('Kirim ke Owner/Asisten'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Share Pesanan'), findsOneWidget);
  });

  testWidgets(
      'pegawai DENGAN izin terima_pembayaran ON: tombol tetap "Bayar" '
      'normal (tidak digerbang)', (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: true);
    addTearDown(() async => db.close());

    expect(find.text('Bayar'), findsOneWidget);
    expect(find.text('Kirim ke Owner/Asisten'), findsNothing);
  });

  testWidgets('owner TIDAK PERNAH digerbang, selalu lihat "Bayar" langsung',
      (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'owner', terimaPembayaran: false);
    addTearDown(() async => db.close());

    expect(find.text('Bayar'), findsOneWidget);
    expect(find.text('Kirim ke Owner/Asisten'), findsNothing);
  });

  testWidgets('asisten TIDAK PERNAH digerbang, selalu lihat "Bayar" langsung',
      (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'asisten', terimaPembayaran: false);
    addTearDown(() async => db.close());

    expect(find.text('Bayar'), findsOneWidget);
    expect(find.text('Kirim ke Owner/Asisten'), findsNothing);
  });

  testWidgets(
      'susulan: tombol "Share Pesanan" TIDAK mengosongkan keranjang sendiri '
      '(dulu "Sudah Dikirim, Kosongkan Keranjang" persis di atas "Tutup" '
      'sering ke-misclick, menghapus keranjang yang belum benar-benar '
      'terkirim) — mengosongkan cuma lewat ikon tempat sampah di header, '
      'lihat cart_sheet_transfer_icon_test.dart', (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: false);
    addTearDown(() async => db.close());

    final container = ProviderScope.containerOf(
        tester.element(find.byType(CartSheet)),
        listen: false);

    await tester.tap(find.text('Kirim ke Owner/Asisten'));
    await tester.pumpAndSettle();

    expect(find.text('Share Pesanan'), findsOneWidget);
    // TIDAK ditekan sampai tuntas — memanggil plugin native `Share.share`
    // yg tak ada mock method channel-nya di codebase ini (lihat pola sama
    // di backup_share_option_test.dart). Cukup buktikan keranjang MASIH
    // utuh sebelum ditekan (tombol ini tidak lagi mengosongkan apa pun).
    expect(container.read(cartProvider(kMainCartId)), isNotEmpty);

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();

    expect(container.read(cartProvider(kMainCartId)), isNotEmpty,
        reason: 'menutup sheet QR tanpa share tidak boleh menghapus '
            'keranjang');
  });

  testWidgets(
      'mode Katalog (kCatalogCartId) TIDAK PERNAH digerbang walau pegawai '
      'tanpa izin — bukan transaksi sungguhan', (tester) async {
    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir',
        terimaPembayaran: false,
        cartId: kCatalogCartId);
    addTearDown(() async => db.close());

    expect(find.text('Bayar'), findsOneWidget);
    expect(find.text('Kirim ke Owner/Asisten'), findsNothing);
  });

  testWidgets(
      'tombol "Salin Teks Pesanan" — jalur cadangan kalau scan QR susah — '
      'menyalin teks LENGKAP (beda dari isi QR yang diperkecil demi '
      'kepadatan modul) ke clipboard', (tester) async {
    // Clipboard.getData TIDAK di-mock otomatis oleh flutter_test di
    // environment ini (beda dari asumsi umum) — tanpa handler manual,
    // `await Clipboard.getData(...)` menggantung SELAMANYA (bukan error
    // cepat), bikin seluruh test hang. Simulasikan clipboard asli lewat
    // channel platform manual.
    String? clipboardStore;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardStore = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return {'text': clipboardStore};
      }
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));

    final db = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: false);
    addTearDown(() async => db.close());

    await tester.tap(find.text('Kirim ke Owner/Asisten'));
    await tester.pumpAndSettle();

    // QrImageView tidak expose data-nya lewat getter publik — bangun ulang
    // teks yang SEHARUSNYA sama persis dgn cara `_showHandoffQr` membuatnya
    // (device tanpa pegawai/pelanggan terpilih di meta → employeeName =
    // nama device sendiri, customerName null). Device ini `terimaPembayaran:
    // false` (needsGate true) — susulan (kekhawatiran user, valid): harga
    // TIDAK ikut dibawa dari device tanpa izin bayar (`trustPrices: false`),
    // supaya owner tidak menerima harga yang belum pernah divalidasi.
    final expectedText = OrderParserService.encodeHandoff(
      items: [item],
      employeeName: 'HP Kasir 2',
      customerName: null,
      trustPrices: false,
      // Item 54 — `_showHandoffQr` sekarang selalu kirim storeName device.
      storeName: 'Toko Uji',
    );

    // Sengaja `pump()` biasa (bukan `pumpAndSettle`) — SnackBar punya timer
    // auto-dismiss (default 4 detik) yang tidak pernah "settle" di clock
    // sintetis widget test, `pumpAndSettle` bisa menunggu selamanya (gotcha
    // yang sama persis dgn drift StreamProvider, lihat CLAUDE.md §Gotcha).
    await tester.tap(find.text('Salin Teks Pesanan'));
    await tester.pump();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, expectedText,
        reason: 'teks yang disalin harus LENGKAP (blok manusiawi + kode '
            'mesin) supaya enak dibaca kalau ditempel manual (WhatsApp/'
            'Telegram) & tetap terbaca parser "Tempel Pesanan" kalau scan '
            'tidak memungkinkan — beda dari isi QR yang diperkecil '
            '(storeName dibuang) demi kepadatan modul, lihat dok '
            '`_showHandoffQr`');
    expect(find.text('Teks pesanan disalin'), findsOneWidget);
    // Susulan (permintaan user, 14 Agt 2026): buktikan Copy/Share
    // MEMPERTAHANKAN blok manusiawi (beda dari QR yang membuangnya) —
    // lihat `order_parser_service_test.dart` group "Item 54" utk
    // pembuktian sisi lain (storeName: null -> header hilang total).
    expect(clipboard?.text, contains('PESANAN — Toko Uji'),
        reason: 'Copy/Share TETAP bawa blok manusiawi (nama toko + daftar '
            'produk + Total) — cuma isi QR yang diperkecil, bukan Copy/'
            'Share');

    // Drain timer SnackBar yang masih pending sebelum teardown (kalau
    // tidak, "A Timer is still pending" saat disposal binding).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
