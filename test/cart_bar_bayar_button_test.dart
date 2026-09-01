import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart' show kMainCartId;

/// Item 55/56 — segmen "Bayar" terracotta di cart bar (tab meta, sejajar
/// "Tahan"): muncul utk owner/asisten/pegawai BERIZIN `terima_pembayaran`,
/// tap langsung ke layar Pembayaran (TANPA lewat sheet keranjang dulu).
/// Disembunyikan utk pegawai TANPA izin (jalur mereka tetap "Kirim ke
/// Owner/Asisten" via cart sheet, lihat kasir_handoff_qr_test.dart).
void main() {
  Future<AppDatabase> seedDb({bool terimaPembayaran = false}) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(KasirPermissionsCompanion(isEnabled: Value(terimaPembayaran)));
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Gula Pasir'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 15000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    return db;
  }

  Future<ProviderContainer> pumpKasir(WidgetTester tester, AppDatabase db,
      {required String deviceRole,
      double textScale = 1.0,
      double ambientLetterSpacing = 0}) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: deviceRole,
        )),
      licenseProvider.overrideWith((ref) =>
          LicenseNotifier()..state = const LicenseState(exp: 'selamanya')),
    ]);
    addTearDown(container.dispose);

    final router = container.read(routerProvider);
    router.go('/kasir');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          // `ambientLetterSpacing` (default 0) MELEBARKAN teks lewat
          // `DefaultTextStyle` ambient (disuntik via `theme.textTheme` —
          // `Material` MENGGANTI DefaultTextStyle dgn `bodyMedium`, jadi
          // membungkus `DefaultTextStyle.merge` di luar router TIDAK akan
          // sampai ke dalam Scaffold). Ini proxy DETERMINISTIK utk perbedaan
          // fontFamily ambient (tema app pakai Hanken Grotesk via
          // GoogleFonts) yg TIDAK BISA direproduksi langsung di
          // `flutter_test`: GoogleFonts tak bisa fetch font di test, jadi
          // painter & Text sama-sama jatuh ke font fallback yg SAMA dan
          // diskrepansinya hilang. Kelas bug-nya identik: properti style
          // TURUNAN yg melebarkan teks tapi tak terlihat oleh TextPainter
          // yg diberi TextSpan style mentah.
          theme: () {
            final base = AppTheme.light();
            if (ambientLetterSpacing == 0) return base;
            final ls = TextStyle(letterSpacing: ambientLetterSpacing);
            return base.copyWith(
              textTheme: base.textTheme.copyWith(
                bodyMedium: (base.textTheme.bodyMedium ?? const TextStyle())
                    .merge(ls),
                bodySmall: (base.textTheme.bodySmall ?? const TextStyle())
                    .merge(ls),
                bodyLarge: (base.textTheme.bodyLarge ?? const TextStyle())
                    .merge(ls),
              ),
            );
          }(),
          routerConfig: router,
          // `textScale` (default 1.0, dipakai regresi textScaler di bawah) —
          // meniru pengali skala font global yang diterapkan `main.dart`.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tambah item ke keranjang lewat tap ikon "+" (AddControl/quickAdd) di
    // kartu produk (menaikkan cartProvider melalui alur nyata, bukan seed
    // langsung provider — memastikan trigger reservasi nomor nota Item 55
    // ikut teruji). Tap BODY kartu hanya membuka ItemEntrySheet, tidak
    // langsung menambah ke keranjang — lihat onTapBody vs onQuickAdd di
    // kasir_screen.dart.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.pump();
    return container;
  }

  testWidgets('owner melihat segmen Bayar di cart bar, tap ke Pembayaran',
      (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'owner');

    expect(find.text('Bayar'), findsOneWidget);

    await tester.tap(find.text('Bayar'));
    await tester.pumpAndSettle();

    expect(find.text('Pembayaran'), findsOneWidget,
        reason: 'tap Bayar harus langsung ke AppBar layar Pembayaran');
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran TIDAK melihat segmen Bayar di '
      'cart bar', (tester) async {
    final db = await seedDb(terimaPembayaran: false);
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'kasir');

    expect(find.text('Bayar'), findsNothing);
  });

  testWidgets(
      'pegawai DENGAN izin terima_pembayaran melihat segmen Bayar',
      (tester) async {
    final db = await seedDb(terimaPembayaran: true);
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'kasir');

    expect(find.text('Bayar'), findsOneWidget);
  });

  testWidgets(
      'nomor nota (#1) muncul di cart bar setelah item pertama masuk '
      '(reservasi Item 55)', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    await pumpKasir(tester, db, deviceRole: 'owner');

    // Reservasi async — beri kesempatan selesai.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.textContaining('#1'), findsWidgets);
  });

  testWidgets(
      'REDESAIN: layout cart bar TIDAK BERUBAH SAMA SEKALI walau nama '
      'pelanggan sangat panjang — nama panjang ditangani teks berjalan, '
      'BUKAN dgn melipat baris (permintaan user)', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db, deviceRole: 'owner');

    // Rekam posisi SEMUA tombol sebelum nama panjang dipasang.
    final bayarBefore = tester.getRect(find.text('Bayar'));
    final tahanBefore = tester.getRect(find.text('Tahan'));

    container.read(cartMetaProvider(kMainCartId).notifier).setCustomer(
        'c1', 'Pelanggan Dengan Nama Sangat Sangat Sangat Panjang Sekali');
    await tester.pump();
    await tester.pump();

    final bayarAfter = tester.getRect(find.text('Bayar'));
    final tahanAfter = tester.getRect(find.text('Tahan'));

    // INTI permintaan user: "sekiranya semua tombol mendapat porsi pas nya
    // tanpa harus diubah ubah lagi layoutnya" — posisi tombol harus IDENTIK,
    // bukan sekadar "Bayar tetap di kanan".
    expect(bayarAfter, bayarBefore,
        reason: 'posisi tombol Bayar WAJIB identik — layout tidak boleh '
            'bergeser/melipat hanya karena nama pelanggan panjang');
    expect(tahanAfter, tahanBefore,
        reason: 'tombol Tahan pun tidak boleh bergeser (dulu ikut melipat '
            'ke baris ke-2 saat nama panjang)');

    // Dan nama panjangnya memang dirender utuh (untuk digeser), bukan
    // dipotong ellipsis — bukti jalur marquee yang dipakai.
    expect(find.textContaining('Sangat Panjang Sekali'), findsOneWidget);
  });

  testWidgets(
      'nama panjang BENAR-BENAR berjalan (offset bergeser seiring waktu), '
      'bukan sekadar dipotong ellipsis', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db, deviceRole: 'owner');

    container.read(cartMetaProvider(kMainCartId).notifier).setCustomer(
        'c1', 'Pelanggan Dengan Nama Sangat Sangat Sangat Panjang Sekali');
    await tester.pump();
    await tester.pump();

    // Teks yang meluber dirender di dalam ClipRect+Transform (jalur marquee),
    // BUKAN sebagai Text ber-ellipsis biasa.
    Offset offsetOfName() {
      final t = tester.widget<Transform>(find.ancestor(
        of: find.textContaining('Sangat Panjang Sekali'),
        matching: find.byType(Transform),
      ).first);
      return Offset(t.transform.getTranslation().x, 0);
    }

    final awal = offsetOfName();
    // Lewati fase "diam di ujung" (18% durasi) lalu ukur lagi.
    await tester.pump(const Duration(milliseconds: 1500));
    final sesudah = offsetOfName();

    expect(sesudah.dx, lessThan(awal.dx),
        reason: 'teks harus BERGESER ke kiri seiring waktu — kalau diam saja, '
            'berarti jatuh ke ellipsis biasa, bukan teks berjalan');
  });

  testWidgets(
      'marquee ISTIRAHAT sebentar lalu OTOMATIS ULANG lagi, bukan berhenti '
      'selamanya (laporan user: nama kelihatan "kepotong" krn layar dilihat '
      'SETELAH putaran-nyala pertama selesai, bukan sedang berjalan)',
      (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db, deviceRole: 'owner');

    // Cari nama yg overflow SEKECIL mungkin (bukan nama sangat panjang) —
    // overflow kecil -> durasi 1 putaran diklem ke MINIMUM (2 detik), jadi
    // jeda baca bawaan di titik balik `repeat(reverse:true)` (`2 * 0.18 * 2
    // detik` ~= 0.72 detik) jauh LEBIH PENDEK drpd `_restPause` (3 detik) —
    // perbedaan tegas ini penting utk membedakan jeda baca NORMAL (yang
    // terjadi berulang selama marquee aktif) dari jeda ISTIRAHAT ANTAR
    // putaran-nyala yg sungguhan sedang diuji di sini.
    bool marqueeActiveFor(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(OverflowBox))
        .evaluate()
        .isNotEmpty;
    const base =
        'Kartika Wulandari Setiawan Pratama Handayani Suherman Aminah';
    String? name;
    for (var i = 1; i <= base.length; i++) {
      final candidate = base.substring(0, i);
      container
          .read(cartMetaProvider(kMainCartId).notifier)
          .setCustomer('c1', candidate);
      await tester.pump();
      await tester.pump();
      if (marqueeActiveFor(candidate)) {
        name = candidate;
        break;
      }
    }
    expect(name, isNotNull,
        reason: 'harus ada prefix yg overflow (marquee aktif) di lebar chip '
            'Pelanggan');

    Offset offsetOfName() {
      final t = tester.widget<Transform>(
          find.ancestor(of: find.text(name!), matching: find.byType(Transform))
              .first);
      return Offset(t.transform.getTranslation().x, 0);
    }

    const step = Duration(milliseconds: 100);
    const longRestThreshold = 1.5; // detik — di antara jeda baca (~0.72s) & _restPause (3s)
    var moved = false;
    var zeroRunSeconds = 0.0;
    var longRestSeen = false;
    var resumedAfterLongRest = false;
    for (var i = 0; i < 200 && !resumedAfterLongRest; i++) {
      await tester.pump(step);
      final dx = offsetOfName().dx;
      if (dx < 0) {
        if (longRestSeen) resumedAfterLongRest = true;
        moved = true;
        zeroRunSeconds = 0;
      } else if (moved) {
        zeroRunSeconds += step.inMilliseconds / 1000;
        if (zeroRunSeconds >= longRestThreshold) longRestSeen = true;
      }
    }
    expect(moved, isTrue, reason: 'marquee harus sempat bergerak (baseline)');
    expect(longRestSeen, isTrue,
        reason: 'harus ada jeda diam PANJANG (>= $longRestThreshold detik) — '
            'kalau tidak pernah diam selama itu, berarti tidak sedang '
            'menguji jeda istirahat antar-putaran, cuma jeda baca singkat '
            'biasa');
    expect(resumedAfterLongRest, isTrue,
        reason: 'setelah jeda diam PANJANG, marquee HARUS bergerak LAGI '
            'otomatis — kalau tetap diam selamanya di sini, itu persis bug '
            'yg dilaporkan user (nama kelihatan kepotong permanen krn '
            'dilihat setelah putaran-nyala pertama selesai)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'porsi chip Pelanggan TIDAK dikurangi oleh fitur teks berjalan — tetap '
      'segmen terlebar di baris meta', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db, deviceRole: 'owner');

    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', 'Bu Artia');
    await tester.pump();
    await tester.pump();

    final pelangganW = tester.getRect(find.text('Bu Artia')).width;
    final pegawaiW = tester.getRect(find.text('Pegawai')).width;
    expect(pelangganW, greaterThan(pegawaiW),
        reason: 'chip Pelanggan dapat porsi lebih besar (flex 4 vs 3) — '
            'permintaan user: porsinya jangan dikurangi');
  });

  testWidgets(
      'skala font besar (aksesibilitas) TIDAK bikin nama yg baru overflow di '
      'skala itu malah dikira muat & terpotong permanen (regresi textScaler, '
      'laporan user: kata kedua nama pelanggan hilang bukan geser)',
      (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());

    // `OverflowBox` HANYA dipakai di jalur marquee overflow (`MarqueeText`)
    // di seluruh codebase ini — penanda struktural yg jauh lebih spesifik
    // drpd `Transform` polos (halaman ini jg punya Transform lain dari
    // animasi transisi rute Material 3/ZoomPageTransitionsBuilder).
    bool marqueeActiveFor(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(OverflowBox))
        .evaluate()
        .isNotEmpty;

    // Batas dicari EMPIRIS thd widget sungguhan (BUKAN konstanta hardcode —
    // konstanta jadi basi tiap pengukuran `MarqueeText` diperbaiki): prefix
    // TERPANJANG yg masih MUAT di skala 1.0.
    const base = 'Kartikawulandarisetiawanpratamahandayanisuhermanaminah';
    final c1 = await pumpKasir(tester, db, deviceRole: 'owner');
    String? fitting;
    for (var i = 1; i <= base.length; i++) {
      final candidate = base.substring(0, i);
      c1.read(cartMetaProvider(kMainCartId).notifier)
          .setCustomer('c1', candidate);
      await tester.pump();
      await tester.pump();
      if (marqueeActiveFor(candidate)) break;
      fitting = candidate;
    }
    expect(fitting, isNotNull,
        reason: 'harus ada prefix yg muat di skala 1.0 (baseline)');

    // Teks yg SAMA di skala 1.4x (mis. aksesibilitas font besar) HARUS
    // overflow: hurufnya melebar 40% DAN chip lain (Tahan/Bayar) juga
    // melebar shg porsi Pelanggan menyempit. Tanpa fix `textScaler` di
    // `MarqueeText`, pengukuran tetap memakai skala 1.0 & keliru simpul
    // "masih muat" — nama terjebak di Text terpotong permanen, persis bug
    // yg dilaporkan user.
    final c2 =
        await pumpKasir(tester, db, deviceRole: 'owner', textScale: 1.4);
    c2.read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', fitting!);
    await tester.pump();
    await tester.pump();
    expect(marqueeActiveFor(fitting), isTrue,
        reason: 'di skala font besar teks yg tadinya muat HARUS overflow -> '
            'marquee aktif, bukan dikira muat lalu terpotong permanen');

    // Drain: marquee AKTIF berarti `_stopTimer` (`Timer` sungguhan, bukan
    // driven fake clock) masih berjalan — ganti tree ke widget kosong dulu
    // supaya `dispose()` membatalkannya, jangan biarkan pending saat test
    // berakhir (lihat gotcha Timer di CLAUDE.md).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'style AMBIENT yg melebarkan teks (fontFamily tema / letterSpacing) '
      'WAJIB ikut diukur — kalau tidak, nama dikira muat lalu WRAP di spasi & '
      'hanya kata pertama tersisa ("Buk Khotimah" -> "Buk" + ruang kosong '
      'lebar, laporan user)', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());

    bool marqueeActiveFor(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(OverflowBox))
        .evaluate()
        .isNotEmpty;

    // Nama 2 KATA — penting: gejala yg dilaporkan user (kata KEDUA hilang,
    // sisanya ruang kosong lebar) hanya muncul kalau ada spasi utk di-wrap.
    const name = 'Buk Khotimah';

    // Baseline: TANPA pelebaran ambient, nama ini MUAT (marquee tidak aktif).
    final c1 = await pumpKasir(tester, db, deviceRole: 'owner');
    c1.read(cartMetaProvider(kMainCartId).notifier).setCustomer('c1', name);
    await tester.pump();
    await tester.pump();
    expect(marqueeActiveFor(name), isFalse,
        reason: 'prakondisi: tanpa pelebaran ambient, nama ini memang muat');

    // Sekarang lebarkan teks lewat style AMBIENT (proxy fontFamily tema —
    // lihat dok `ambientLetterSpacing` di `pumpKasir`). Lebar SUNGGUHAN teks
    // jadi melebihi porsi chip, jadi marquee HARUS aktif. Tanpa fix
    // (`DefaultTextStyle.of(context).style.merge(...)` di `MarqueeText`),
    // `TextPainter` tidak melihat pelebaran ini, mengukur teks lebih SEMPIT
    // dari kenyataan, menyimpulkan "muat", lalu jatuh ke cabang `Text` biasa.
    final c2 = await pumpKasir(tester, db,
        deviceRole: 'owner', ambientLetterSpacing: 2.5);
    c2.read(cartMetaProvider(kMainCartId).notifier).setCustomer('c1', name);
    await tester.pump();
    await tester.pump();
    expect(marqueeActiveFor(name), isTrue,
        reason: 'pelebaran style ambient HARUS ikut terukur -> marquee aktif; '
            'kalau tidak, teks jatuh ke Text biasa lalu WRAP di spasi dan '
            'hanya "Buk" yang tersisa (persis screenshot user)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'jaring pengaman: cabang non-marquee memakai softWrap:false, jadi kalau '
      'pengukuran MASIH meleset sedikit teksnya terpotong MEPET — bukan '
      'runtuh jadi kata pertama saja', (tester) async {
    final db = await seedDb();
    addTearDown(() async => db.close());
    final container = await pumpKasir(tester, db, deviceRole: 'owner');

    // Nama pendek 2 kata yg PASTI muat -> cabang non-marquee (`Text` biasa).
    const name = 'Bu Ani';
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('c1', name);
    await tester.pump();
    await tester.pump();

    final txt = tester.widget<Text>(find.text(name));
    expect(txt.softWrap, isFalse,
        reason: 'tanpa softWrap:false, teks yg (nyaris) tidak muat akan WRAP '
            'di spasi dan maxLines:1 menyisakan kata pertama saja — terlihat '
            'seperti data hilang, bukan seperti terpotong');
    expect(txt.maxLines, 1);
  });
}
