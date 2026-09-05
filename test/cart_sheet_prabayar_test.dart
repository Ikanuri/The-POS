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
    // Sheet showDebtPaymentSheet terbuka, prefillRemaining=true → langsung
    // tap tombol Bayar (satu-satunya FilledButton di sheet itu) mengunci
    // Rp 30.000 (seluruh sisa) sbg entri Tunai.
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
}
