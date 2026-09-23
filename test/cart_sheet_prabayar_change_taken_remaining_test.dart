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
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Bug dilaporkan user (screenshot): sheet "Pra-Bayar" ("Tambah Bayar" di
/// keranjang yang sudah punya Pra-Bayar) menghitung "Sisa tagihan" dari
/// `CartPrabayarNotifier.totalLocked` MENTAH -- BUKAN `poolAvailable`
/// (`totalLocked - changeTakenTotal`). Begitu ada kembalian yang SUDAH
/// fisik diserahkan & dicentang "sudah diambil", uang itu tetap ikut
/// dihitung sbg Pra-Bayar yang "masih tersedia" di kalkulator ini, padahal
/// sudah di tangan pelanggan -- kalau barang ditambah lagi setelah itu,
/// "Sisa tagihan" bisa ke-clamp jadi Rp 0 walau seharusnya masih ada yang
/// harus dibayar penuh (kembalian yang sudah diambil TIDAK BOLEH dipakai
/// lagi menutup belanja baru).
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 1,
    price: 30000,
    originalPrice: 30000,
    costPrice: 20000,
  );
  const extraItem = CartItem(
    productId: 'p2',
    productUnitId: 'u2',
    productName: 'Minyak 1L',
    unitName: 'Botol',
    qty: 1,
    price: 20000,
    originalPrice: 20000,
    costPrice: 15000,
  );

  Future<
      ({
        AppDatabase db,
        ProviderContainer container,
      })> pumpCartSheetOpen(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(const KasirPermissionsCompanion(isEnabled: Value(true)));
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Owner',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(item);

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
                  builder: (_) => const CartSheet(cartId: kMainCartId),
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

  testWidgets(
      'kembalian sudah diambil (Rp54.900) lalu tambah barang Rp20.000 -> '
      '"Sisa tagihan" di kalkulator Tambah Bayar TETAP Rp20.000 penuh, '
      'BUKAN Rp0', (tester) async {
    final r = await pumpCartSheetOpen(tester);
    addTearDown(() async => r.db.close());

    // Total keranjang = 30000. Kunci Pra-Bayar Rp 84.900 (lebih besar dari
    // total -> muncul Kembalian 54.900), lalu centang "sudah diambil".
    r.container
        .read(cartPrabayarProvider(kMainCartId).notifier)
        .add(PrabayarEntry(
          id: 'e1',
          amount: 84900,
          method: 'tunai',
          lockedAt: DateTime.now(),
        ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kembalian '), findsOneWidget,
        reason: 'prakondisi: 84900 - 30000 = 54900 kembalian');
    final changeTakenCheckbox = find.descendant(
      of: find.ancestor(
          of: find.textContaining('Kembalian '), matching: find.byType(Row)),
      matching: find.byType(Checkbox),
    );
    await tester.tap(changeTakenCheckbox);
    await tester.pumpAndSettle();

    expect(find.textContaining('Sisa '), findsNothing,
        reason: 'prakondisi: setelah kembalian diambil, pool = 84900-54900 '
            '= 30000 = total, pas -> tidak ada Sisa/Kembalian');

    // Kasir menambah barang baru Rp 20.000 -> total jadi 50.000. Uang
    // kembalian 54.900 SUDAH di tangan pelanggan, TIDAK BOLEH dipakai lagi
    // menutup belanja baru -- customer harus bayar Rp 20.000 PENUH.
    r.container.read(cartProvider(kMainCartId).notifier).addItem(extraItem);
    await tester.pumpAndSettle();

    expect(find.text('Sisa ${formatRupiah(20000)}'), findsOneWidget,
        reason: 'footer keranjang (sudah benar) — pool tetap 30000, total '
            'jadi 50000, sisa = 20000');

    // Buka kalkulator "Tambah Bayar" (tombol Pra-Bayar yang sama, akumulatif).
    await tester.tap(find.byTooltip('Pra-Bayar'));
    await tester.pumpAndSettle();

    final sisaTagihanRow = find.ancestor(
        of: find.text('Sisa tagihan '), matching: find.byType(Row));
    expect(
        find.descendant(
            of: sisaTagihanRow, matching: find.text(formatRupiah(20000))),
        findsOneWidget,
        reason: 'tanpa fix: "Sisa tagihan" pakai totalLocked mentah (84900) '
            '-> 50000-84900 clamp ke 0, BUKAN 20000 yang sebenarnya harus '
            'dibayar penuh');
  });
}
