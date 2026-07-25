import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/inline_banner.dart';

/// Usulan user: nama produk yang bertabrakan di notif di-highlight, dan
/// diketuk → membuka produk itu. Dua hal yang diuji di sini:
///  1. `InlineBanner` merender potongan `linkText` sbg span terpisah yang
///     bisa diketuk, DAN tidak auto-dismiss selama punya aksi (4 detik jelas
///     tidak cukup utk membaca lalu mengetuk — banner yang hilang sendiri
///     membuat aksinya mustahil diraih).
///  2. Fallback aman: kalau `linkText` tidak ada di pesan, banner tetap
///     tampil sebagai teks biasa (tidak kosong / tidak error).
void main() {
  /// Ambil seluruh teks banner (gabungan semua span) supaya pesan tetap
  /// terverifikasi utuh walau sudah dipecah jadi RichText.
  String bannerText(WidgetTester tester) {
    final rich = tester.widget<Text>(find.descendant(
      of: find.byType(InlineBanner),
      matching: find.byType(Text),
    ));
    return rich.textSpan?.toPlainText() ?? rich.data ?? '';
  }

  testWidgets(
      'nama produk di banner jadi span yang bisa diketuk & memanggil aksinya',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InlineBanner(
          message: 'Barcode "899" sudah dipakai produk "Indomie Goreng". '
              'Gunakan barcode lain.',
          type: InlineBannerType.error,
          linkText: 'Indomie Goreng',
          onLinkTap: () => tapped++,
          onDismiss: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(bannerText(tester), contains('Indomie Goreng'),
        reason: 'pesan utuh harus tetap terbaca walau dipecah jadi span');

    // Cari span tautannya & jalankan recognizer-nya — inti fiturnya.
    final rich = tester.widget<Text>(find.descendant(
      of: find.byType(InlineBanner),
      matching: find.byType(Text),
    ));
    TapGestureRecognizer? recognizer;
    (rich.textSpan! as TextSpan).visitChildren((span) {
      if (span is TextSpan && span.text == 'Indomie Goreng') {
        recognizer = span.recognizer as TapGestureRecognizer?;
      }
      return true;
    });
    expect(recognizer, isNotNull,
        reason: 'nama produk harus jadi span ber-recognizer, bukan teks polos');

    recognizer!.onTap!();
    expect(tapped, 1);
  });

  testWidgets(
      'banner yang punya aksi TIDAK auto-dismiss (4 detik tak cukup untuk '
      'diketuk)', (tester) async {
    var dismissed = 0;
    Widget build(String? msg, {String? link, VoidCallback? onLinkTap}) =>
        MaterialApp(
          home: Scaffold(
            body: InlineBanner(
              message: msg,
              linkText: link,
              onLinkTap: onLinkTap,
              onDismiss: () => dismissed++,
            ),
          ),
        );

    // WAJIB null dulu lalu non-null: timer hanya di-arm di `didUpdateWidget`
    // saat `message` BERUBAH. Kalau kedua pump pakai message yang sama, timer
    // tidak pernah jalan & test ini lolos tanpa menguji apa pun (ketahuan
    // saat revert-verify: dulu lolos juga walau fitur dimatikan).
    await tester.pumpWidget(build(null));
    await tester.pumpWidget(build('Barcode dipakai produk "Kopi ABC".',
        link: 'Kopi ABC', onLinkTap: () {}));
    await tester.pump(const Duration(seconds: 10));
    expect(dismissed, 0,
        reason: 'selama ada aksi, banner harus menetap sampai ditutup manual');
  });

  testWidgets('tanpa aksi: auto-dismiss lama tetap berjalan (tidak regresi)',
      (tester) async {
    var dismissed = 0;
    Widget build(String? msg) => MaterialApp(
          home: Scaffold(
            body: InlineBanner(
              message: msg,
              onDismiss: () => dismissed++,
            ),
          ),
        );

    await tester.pumpWidget(build(null));
    await tester.pumpWidget(build('Pesan biasa tanpa aksi'));
    await tester.pump(const Duration(seconds: 5));
    expect(dismissed, 1,
        reason: 'perilaku auto-dismiss banner biasa tidak boleh berubah');
  });

  testWidgets(
      'linkText yang TIDAK ada di pesan: tetap tampil sebagai teks biasa',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: InlineBanner(
          message: 'Pesan tanpa nama produk di dalamnya.',
          linkText: 'Produk Yang Tidak Disebut',
          onLinkTap: () {},
          onDismiss: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(bannerText(tester), 'Pesan tanpa nama produk di dalamnya.',
        reason: 'fallback tidak boleh mengosongkan/merusak pesan');
  });

  testWidgets(
      'end-to-end lewat router asli: simpan produk dgn barcode milik produk '
      'lain -> banner menyebut produk itu, dan mengetuk namanya BENAR-BENAR '
      'membuka produk tersebut', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    // Produk A: pemegang barcode.
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'A', name: 'Indomie Goreng'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'A-u', productId: 'A', isBaseUnit: const Value(true)));
    await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'A-bc',
          productUnitId: 'A-u',
          barcode: '8991234567890',
          isPrimary: const Value(true),
        ));

    // Produk B: yang diedit & diberi barcode yang sama.
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'B', name: 'Mie Sedaap'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'B-u', productId: 'B', isBaseUnit: const Value(true)));

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
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      licenseProvider.overrideWith((ref) =>
          LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/produk/B');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
          theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.ancestor(
        of: find.text('Barcode'),
        matching: find.byType(TextFormField),
      ),
      '8991234567890',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simpan Produk'));
    await tester.pumpAndSettle();

    expect(find.byType(InlineBanner), findsOneWidget);
    expect(bannerText(tester), contains('Indomie Goreng'),
        reason: 'banner harus menyebut produk pemegang barcode-nya');

    // Produk B TIDAK boleh tersimpan (transaksi rollback), & barcode A utuh.
    expect((await db.getProductBarcodes('A-u')).single.barcode,
        '8991234567890');
    expect(await db.getProductBarcodes('B-u'), isEmpty);

    // Ketuk nama produk di banner -> harus membuka form produk A.
    final rich = tester.widget<Text>(find.descendant(
      of: find.byType(InlineBanner),
      matching: find.byType(Text),
    ));
    TapGestureRecognizer? recognizer;
    (rich.textSpan! as TextSpan).visitChildren((span) {
      if (span is TextSpan && span.text == 'Indomie Goreng') {
        recognizer = span.recognizer as TapGestureRecognizer?;
      }
      return true;
    });
    expect(recognizer, isNotNull);
    recognizer!.onTap!();
    await tester.pumpAndSettle();

    // Form produk A sekarang di atas: field nama berisi "Indomie Goreng".
    final nameField = tester.widget<TextFormField>(find.ancestor(
      of: find.text('Nama Produk *'),
      matching: find.byType(TextFormField),
    ));
    expect(nameField.controller!.text, 'Indomie Goreng',
        reason: 'ketuk nama di banner harus benar-benar redirect ke produk itu');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
