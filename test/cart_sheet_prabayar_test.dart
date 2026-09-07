import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Fitur "Pra-Bayar" (UI, `cart_sheet.dart`) — tombol muncul/hilang sesuai
/// gerbang izin `terima_pembayaran`, kunci entri → badge live, hapus entri →
/// badge update, ubah qty item keranjang → "Sisa" ikut berubah otomatis.
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

  Future<
      ({
        AppDatabase db,
        ProviderContainer container,
      })> pumpCartSheetOpen(
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
          deviceName: 'HP Kasir',
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
    return (db: db, container: container);
  }

  testWidgets('owner (bergerbang) melihat tombol Pra-Bayar', (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    expect(find.byTooltip('Pra-Bayar'), findsOneWidget);
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran TIDAK melihat tombol Pra-Bayar',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: false);
    addTearDown(() async => r.db.close());

    expect(find.byTooltip('Pra-Bayar'), findsNothing);
  });

  testWidgets('mode Katalog TIDAK menampilkan tombol Pra-Bayar', (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner', cartId: kCatalogCartId);
    addTearDown(() async => r.db.close());

    expect(find.byTooltip('Pra-Bayar'), findsNothing);
  });

  testWidgets(
      'kunci Pra-Bayar via tombol → badge "terkunci/Sisa" tampil LIVE, hapus '
      'entri → badge update, ubah qty item → Sisa ikut berubah otomatis',
      (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    // Total keranjang = 2 x 15000 = 30000. Belum ada badge Pra-Bayar.
    expect(find.textContaining('Pra-Bayar:'), findsNothing);

    await tester.tap(find.byTooltip('Pra-Bayar'));
    await tester.pumpAndSettle();
    // Sheet showDebtPaymentSheet terbuka dgn `prefillRemaining: false` (fix
    // bug "kalkulator harus mulai nol") → nominal AWALNYA 0, tap "Uang Pas"
    // dulu supaya jadi Rp 30.000 (seluruh sisa), baru tap tombol Bayar
    // (satu-satunya FilledButton di sheet itu) mengunci sbg entri Tunai.
    await tester.tap(find.text('Uang Pas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    // Sudah lunas PAS (30000 dikunci dari total 30000) → baris "Pra-Bayar Rp
    // X" tampil, TAPI baris "Sisa"/"Kembalian" TIDAK ada sama sekali.
    expect(find.text('Pra-Bayar ${formatRupiah(30000)}'), findsOneWidget);
    expect(find.textContaining('Sisa '), findsNothing);
    expect(find.textContaining('Kembalian '), findsNothing);

    // Warna "Pra-Bayar Rp X" harus NETRAL (bukan `scheme.primary` seperti
    // desain lama) — style tanpa override warna berarti `color` null,
    // mewarisi warna teks default tema.
    final prabayarLabelStyle = tester
        .widget<Text>(find.text('Pra-Bayar ${formatRupiah(30000)}'))
        .style;
    expect(prabayarLabelStyle?.color, isNull);

    final prabayar =
        r.container.read(cartPrabayarProvider(kMainCartId));
    expect(prabayar, hasLength(1));
    expect(prabayar.single.amount, 30000);

    // Ubah qty item keranjang (tambah 1 lagi via stepper — item sudah di
    // keranjang, lingkaran utama `AddControl` menampilkan ANGKA qty, bukan
    // ikon "+" lagi, jadi tap widget-nya langsung, bukan cari ikon) → total
    // naik jadi 45000, "Sisa" harus muncul (merah) jadi 15000 TANPA aksi lain.
    await tester.tap(find.byType(AddControl).first);
    await tester.pumpAndSettle();

    expect(find.text('Pra-Bayar ${formatRupiah(30000)}'), findsOneWidget);
    expect(find.text('Sisa ${formatRupiah(15000)}'), findsOneWidget);
    expect(find.textContaining('Kembalian '), findsNothing);

    final sisaStyle =
        tester.widget<Text>(find.text('Sisa ${formatRupiah(15000)}')).style;
    expect(sisaStyle?.color, AppTheme.debtFg(false));

    // Hapus entri Pra-Bayar via daftar (tap area ringkasan → sheet daftar →
    // hapus). Pakai teks PERSIS (bukan `textContaining`) — SnackBar sisa
    // "Pra-Bayar Rp X dikunci" dari langkah kunci di atas juga cocok dgn
    // substring "Pra-Bayar Rp" dan bikin finder ambigu.
    await tester.tap(find.text('Pra-Bayar ${formatRupiah(30000)}'));
    await tester.pumpAndSettle();
    expect(find.text('Entri Pra-Bayar'), findsOneWidget);
    await tester.tap(find.byTooltip('Hapus'));
    await tester.pumpAndSettle();

    expect(r.container.read(cartPrabayarProvider(kMainCartId)), isEmpty);

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();

    // Cek dgn predicate PERSIS (bukan `textContaining`) — SnackBar sisa
    // "Pra-Bayar Rp X dikunci" dari langkah kunci di atas juga cocok dgn
    // substring "Pra-Bayar Rp" tapi BUKAN ringkasan footer yang dimaksud.
    expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
                RegExp(r'^Pra-Bayar Rp [\d.]+$').hasMatch(w.data ?? '')),
        findsNothing,
        reason: 'ringkasan hilang total setelah entri terakhir dihapus');
  });

  testWidgets(
      'Pra-Bayar melebihi total keranjang -> baris "Kembalian" HIJAU '
      'tampil (bukan "Sisa")', (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    // Total keranjang = 30000. Kunci Rp 40.000 (lebih dari total) langsung
    // lewat notifier (skip alur sheet manual — sudah dibuktikan tombolnya
    // benar di test sebelumnya) supaya skenario "kelebihan" mudah disusun.
    r.container.read(cartPrabayarProvider(kMainCartId).notifier).add(
          PrabayarEntry(
            id: 'e1',
            amount: 40000,
            method: 'tunai',
            lockedAt: DateTime.now(),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('Pra-Bayar ${formatRupiah(40000)}'), findsOneWidget);
    expect(find.text('Kembalian ${formatRupiah(10000)}'), findsOneWidget);
    expect(find.textContaining('Sisa '), findsNothing);

    final kembalianStyle = tester
        .widget<Text>(find.text('Kembalian ${formatRupiah(10000)}'))
        .style;
    expect(kembalianStyle?.color, AppTheme.changeFg(false));
  });

  testWidgets(
      'tombol Pra-Bayar (sekunder, sebelah tombol Bayar) & ringkasan tidak '
      'overflow di layar sempit 360dp', (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpAndSettle();

    r.container.read(cartPrabayarProvider(kMainCartId).notifier).add(
          PrabayarEntry(
            id: 'e1',
            amount: 40000,
            method: 'tunai',
            lockedAt: DateTime.now(),
          ),
        );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'baris footer (badge + ringkasan + tombol Pra-Bayar + Bayar) '
            'harus render tanpa overflow di 360dp walau nominal panjang');
    expect(find.byTooltip('Pra-Bayar'), findsOneWidget);
    expect(find.text('Bayar'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  // Keranjang juga punya Checkbox per baris item (checklist verifikasi
  // sebelum bayar) — finder generik `find.byType(Checkbox)` jadi ambigu.
  // Scope ke Checkbox yang SEBARIS dgn Text "Kembalian ..." saja.
  // Baris diff footer "Kembalian Rp X" SPESIFIK (bukan baris riwayat
  // "Kembalian diambil Rp X" — susulan fitur riwayat, keduanya sama-sama
  // mengandung substring "Kembalian ", jadi `textContaining` generik jadi
  // ambigu begitu changeTakenTotal > 0).
  Finder kembalianDiffRowFinder() => find.byWidgetPredicate((w) =>
      w is Text && RegExp(r'^Kembalian Rp').hasMatch(w.data ?? ''));

  Finder kembalianCheckboxFinder() => find.descendant(
        of: find
            .ancestor(
              of: find.textContaining('Kembalian '),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(Checkbox),
      );

  testWidgets(
      'Fitur "kembalian sudah diambil": centang checkbox di baris Kembalian '
      '→ langsung Rp 0/hilang (recompute pool), lalu kurangi barang lagi → '
      'Kembalian baru muncul dgn checkbox BARU (belum tercentang)',
      (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    // Total keranjang = 30000 (qty 2 x 15000). Kunci Rp 40.000 → Kembalian
    // Rp 10.000 tampil dgn checkbox.
    r.container.read(cartPrabayarProvider(kMainCartId).notifier).add(
          PrabayarEntry(
            id: 'e1',
            amount: 40000,
            method: 'tunai',
            lockedAt: DateTime.now(),
          ),
        );
    await tester.pumpAndSettle();

    expect(find.text('Kembalian ${formatRupiah(10000)}'), findsOneWidget);
    final checkbox = tester.widget<Checkbox>(kembalianCheckboxFinder());
    expect(checkbox.value, false,
        reason: 'checkbox SELALU tampil belum tercentang — bukan penanda '
            'status permanen, murni tombol aksi sekali-tap per kemunculan');

    // Centang → kembalian yg SEDANG tampil (10000) masuk ke
    // changeTakenTotal, baris Kembalian langsung hilang (pool = 40000 -
    // 10000 = 30000, PAS dgn total → tidak ada Sisa/Kembalian sama sekali).
    await tester.tap(kembalianCheckboxFinder());
    await tester.pumpAndSettle();

    // Baris "Kembalian Rp X" (diff footer) harus hilang — TAPI baris
    // riwayat baru "Kembalian diambil Rp X" (susulan fitur riwayat) MEMANG
    // muncul sekarang (changeTakenTotal > 0), jadi cek dgn predicate yg
    // SPESIFIK excl. "diambil", bukan `textContaining('Kembalian ')` generik
    // (yang sekarang ambigu, ikut cocok dgn baris riwayat).
    expect(kembalianDiffRowFinder(), findsNothing);
    expect(find.textContaining('Sisa '), findsNothing);
    expect(
        r.container
            .read(cartPrabayarProvider(kMainCartId).notifier)
            .changeTakenTotal,
        10000);

    // Kurangi 1 barang lagi (qty 2 -> 1, total turun jadi 15000) → pool
    // tersedia (40000-10000=30000) sekarang MELEBIHI total baru →
    // Kembalian BARU (Rp 15.000) muncul dgn checkbox BARU (belum tercentang
    // lagi, walau sebelumnya sudah pernah dicentang sekali). Ubah qty
    // LANGSUNG via notifier (bukan cari tombol minus widget-nya — bukan
    // fokus test ini, sudah dibuktikan benar di test "kunci Pra-Bayar via
    // tombol" di atas).
    r.container
        .read(cartProvider(kMainCartId).notifier)
        .setEffectiveQty('u1', 1);
    await tester.pumpAndSettle();

    expect(find.text('Kembalian ${formatRupiah(15000)}'), findsOneWidget,
        reason: 'kembalian BARU = pool(30000) - total_baru(15000) = 15000');
    final checkbox2 = tester.widget<Checkbox>(kembalianCheckboxFinder());
    expect(checkbox2.value, false);

    // Ambil kembalian baru itu juga → akumulasi changeTakenTotal (BUKAN
    // menimpa nilai lama).
    await tester.tap(kembalianCheckboxFinder());
    await tester.pumpAndSettle();
    expect(
        r.container
            .read(cartPrabayarProvider(kMainCartId).notifier)
            .changeTakenTotal,
        25000,
        reason: 'akumulasi 10000 (pertama) + 15000 (kedua)');
    expect(kembalianDiffRowFinder(), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'checkbox "kembalian sudah diambil" TIDAK menyebabkan checkout final '
      'menghitung ulang kembalian yg sudah diambil sbg kredit tersedia '
      '(dicek via poolAvailable notifier, bukan lockedSum mentah)',
      (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    r.container.read(cartPrabayarProvider(kMainCartId).notifier).add(
          PrabayarEntry(
            id: 'e1',
            amount: 40000,
            method: 'tunai',
            lockedAt: DateTime.now(),
          ),
        );
    await tester.pumpAndSettle();
    await tester.tap(kembalianCheckboxFinder());
    await tester.pumpAndSettle();

    final notifier =
        r.container.read(cartPrabayarProvider(kMainCartId).notifier);
    expect(notifier.totalLocked, 40000,
        reason: 'total terkunci mentah TIDAK berubah — hanya pool yg '
            'terpotong');
    expect(notifier.poolAvailable, 30000,
        reason: 'poolAvailable = totalLocked(40000) - changeTaken(10000)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'Riwayat Kembalian Diambil: tap baris "Kembalian diambil Rp X" → '
      'sheet riwayat tampil isi, hapus 1 entri via tombol → footer '
      'Sisa/Kembalian LANGSUNG recompute (misclick undo)', (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    // Total keranjang TETAP 30000 (qty tidak diubah di test ini) — nominal
    // riwayat (8000/12000) & Pra-Bayar (50000) SENGAJA dibuat beda dari
    // 30000 supaya finder teks per-entri (`formatRupiah` polos, tanpa
    // prefix) tidak ambigu dgn Total/label lain di layar yg sama.
    final notifier =
        r.container.read(cartPrabayarProvider(kMainCartId).notifier);
    notifier.add(PrabayarEntry(
      id: 'e1',
      amount: 50000,
      method: 'tunai',
      lockedAt: DateTime.now(),
    ));
    notifier.recordChangeTaken(8000);
    notifier.recordChangeTaken(12000);
    await tester.pumpAndSettle();

    expect(notifier.changeTakenEntries, hasLength(2));
    expect(notifier.changeTakenTotal, 20000);

    // Baris ringkasan "Kembalian diambil Rp 20.000" harus tampil & tappable.
    final historyRow =
        find.text('Kembalian diambil ${formatRupiah(20000)}');
    expect(historyRow, findsOneWidget);

    await tester.tap(historyRow);
    await tester.pumpAndSettle();

    expect(find.text('Riwayat Kembalian Diambil'), findsOneWidget);
    expect(find.text(formatRupiah(8000)), findsOneWidget);
    expect(find.text(formatRupiah(12000)), findsOneWidget);

    // Tombol hapus DI DALAM ListTile entri 8000 — di-scope (bukan
    // `find.byIcon(Icons.delete_outline)` polos, yg JUGA cocok dgn ikon
    // hapus per-baris item keranjang di layar belakang sheet ini).
    Finder deleteButtonFor(int amount) => find.descendant(
          of: find
              .ancestor(
                of: find.text(formatRupiah(amount)),
                matching: find.byType(ListTile),
              )
              .first,
          matching: find.byIcon(Icons.delete_outline),
        );

    // Hapus entri Rp 8.000 (undo misclick) — sisa 1 entri (12000).
    await tester.tap(deleteButtonFor(8000));
    await tester.pumpAndSettle();

    expect(notifier.changeTakenEntries, hasLength(1));
    expect(notifier.changeTakenTotal, 12000);
    expect(find.text(formatRupiah(8000)), findsNothing,
        reason: 'entri terhapus tidak tampil lagi di sheet (masih terbuka)');
    expect(find.text(formatRupiah(12000)), findsOneWidget);

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();

    // Footer harus recompute dari total riwayat yg TERSISA (12000), bukan
    // nilai lama (20000).
    expect(find.text('Kembalian diambil ${formatRupiah(12000)}'),
        findsOneWidget);
    expect(find.text('Kembalian diambil ${formatRupiah(20000)}'),
        findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  group('bug "Kembalian terpotong" (_PrabayarFooterSummary) di layar sempit',
      () {
    testWidgets(
        'nominal BESAR (Pra-Bayar + Kembalian + riwayat + Lunasi Hutang '
        'sekaligus) di 360dp: render TANPA overflow exception DAN teks '
        'baris-baris itu TIDAK pakai TextOverflow.ellipsis lagi',
        (tester) async {
      final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
      addTearDown(() async => r.db.close());
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpAndSettle();

      // Entri Pra-Bayar nominal sangat besar (>Rp 12 juta) supaya "Kembalian"
      // (diff thd total keranjang 30000) juga jadi nominal besar sekaligus.
      r.container.read(cartPrabayarProvider(kMainCartId).notifier).add(
            PrabayarEntry(
              id: 'eBesar',
              amount: 12345678,
              method: 'tunai',
              lockedAt: DateTime.now(),
            ),
          );
      // Sebagian kecil sudah diambil sbg kembalian sebelumnya → baris
      // "riwayat kembalian diambil" ikut tampil bersamaan.
      r.container
          .read(cartPrabayarProvider(kMainCartId).notifier)
          .recordChangeTaken(1000000);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'kolom ringkasan Pra-Bayar dgn banyak baris teks nominal '
              'besar HARUS tetap render tanpa RenderFlex overflow di 360dp');

      expect(find.text('Pra-Bayar ${formatRupiah(12345678)}'), findsOneWidget);
      expect(find.text('Kembalian ${formatRupiah(12345678 - 1000000 - 30000)}'),
          findsOneWidget);
      expect(
          find.text('Kembalian diambil ${formatRupiah(1000000)}'),
          findsOneWidget);

      // Fix: baris2 nominal ini WAJIB sudah tidak pakai `overflow:
      // TextOverflow.ellipsis` lagi (yg memotong teks scr permanen) — kalau
      // diganti balik ke kode lama, assert di bawah ini akan GAGAL
      // (overflow == TextOverflow.ellipsis), membuktikan test ini benar2
      // mendeteksi mekanisme fix-nya (bukan cuma "tidak exception").
      final prabayarText = tester.widget<Text>(
          find.text('Pra-Bayar ${formatRupiah(12345678)}'));
      expect(prabayarText.overflow, isNot(TextOverflow.ellipsis),
          reason: 'harus pakai FittedBox(scaleDown), bukan ellipsis, supaya '
              'nominal besar mengecil BUKAN terpotong');

      final kembalianText = tester.widget<Text>(find.text(
          'Kembalian ${formatRupiah(12345678 - 1000000 - 30000)}'));
      expect(kembalianText.overflow, isNot(TextOverflow.ellipsis));

      final historyText = tester.widget<Text>(
          find.text('Kembalian diambil ${formatRupiah(1000000)}'));
      expect(historyText.overflow, isNot(TextOverflow.ellipsis));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  testWidgets(
      'kalkulator Pra-Bayar mulai dari NOL — bukan prefill sisa keranjang',
      (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    // Total keranjang = 30000 (belum ada entri Pra-Bayar sama sekali,
    // jadi remaining = 30000 kalau prefill AKTIF).
    await tester.tap(find.byTooltip('Pra-Bayar'));
    await tester.pumpAndSettle();

    // Baris "Dibayar" (nominal yg diketik kasir) HARUS Rp 0 — beda dari
    // baris "Sisa"/label remaining di atasnya yg MEMANG selalu menampilkan
    // Rp 30.000 (label info, bukan nominal kalkulator).
    final dibayarValue = tester.widget<Text>(find
        .descendant(
          of: find.ancestor(
              of: find.text('Dibayar'), matching: find.byType(Row)),
          matching: find.byType(Text),
        )
        .at(1));
    expect(dibayarValue.data, formatRupiah(0),
        reason: 'kalkulator Pra-Bayar HARUS mulai kosong/nol, bukan '
            'prefill dgn sisa keranjang (beda dgn Lunasi Hutang/Buku Hutang '
            'yang MEMANG mau prefill)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
