import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/router/app_router.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Poin 4 — bug lapor user: dari keranjang kasir, tap item → modal → tombol
/// edit (pojok kanan atas) → navigasi ke ProdukFormScreen → field "Harga
/// Jual" tidak bisa menerima input digit (hanya delete).
///
/// Akar masalah TERBUKTI (via debug print manual, sebelum test ini ditulis):
/// `_openCartSheet()` di kasir_screen.dart membuka lagi cart sheet SETELAH
/// ItemEntrySheet ditutup — termasuk saat ItemEntrySheet ditutup karena
/// tombol "Edit produk" navigasi ke ProdukFormScreen (bukan hanya saat
/// selesai edit item biasa). Cart sheet yang terbuka ulang ini membuat
/// `_cartSheetOpen = true` LAGI persis saat pengguna berada di
/// ProdukFormScreen, sehingga guard di `_onHardwareKey`
/// (`if (!_cartSheetOpen && !isCurrent) return false;`) gagal bail-out —
/// handler HID keyboard global lanjut menelan karakter (termasuk digit
/// harga) sebagai kemungkinan scan barcode.
///
/// Catatan metodologi: Flutter widget test TIDAK bisa mensimulasikan digit
/// fisik/HID benar-benar masuk ke TextField (dibuktikan lewat test kontrol
/// terpisah: `tester.sendKeyEvent` tidak mengubah teks TextField SAMA SEKALI
/// bahkan tanpa handler custom apa pun — karakter hanya masuk lewat kanal
/// IME/`enterText`, bukan raw hardware key event). Test ini karena itu
/// menguji GEJALA yang BENAR-BENAR bisa diamati: cart sheet TIDAK BOLEH
/// terbuka lagi di belakang ProdukFormScreen.
void main() {
  testWidgets(
      'tap "Edit produk" dari modal item keranjang → cart sheet TIDAK '
      'terbuka lagi di belakang ProdukFormScreen', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Mie Sedap'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2500),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    const item = CartItem(
      productId: 'p1',
      productUnitId: 'u1',
      productName: 'Mie Sedap',
      unitName: 'pcs',
      qty: 10,
      price: 2500,
      originalPrice: 2500,
      costPrice: 2000,
    );
    SharedPreferences.setMockInitialValues({
      'cart_v1_main': jsonEncode([item.toJson()]),
    });

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

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: container.read(routerProvider),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Buka sheet keranjang lewat swipe-atas pada cart bar (satu-satunya cara
    // buka di UI — bukan tombol tap biasa).
    final dragArea = find.byWidgetPredicate(
        (w) => w is GestureDetector && w.onVerticalDragEnd != null);
    expect(dragArea, findsOneWidget);
    await tester.fling(dragArea, const Offset(0, -400), 2000);
    await tester.pumpAndSettle();

    // Tap item di keranjang → sheet keranjang tertutup, modal ItemEntrySheet
    // (edit item) terbuka. Pakai .last: cart bar di belakang sheet juga bisa
    // menampilkan preview nama item terakhir ("Mie Sedap") di posisi .first.
    await tester.tap(find.text('Mie Sedap').last);
    await tester.pumpAndSettle();

    // Tombol edit produk (pojok kanan atas modal) → navigasi ke
    // ProdukFormScreen (owner selalu bisa lihat tombol ini).
    await tester.tap(find.byTooltip('Edit produk'));
    await tester.pumpAndSettle();

    // KONSUMSI overflow layout PRE-EXISTING (cart bar kasir_screen.dart &
    // Row "Satuan & Harga" produk_form_screen.dart:695 pada surface sempit
    // 430px) — tidak terkait bug yang diuji di sini, sama seperti pola di
    // kasir_switch_held_test.dart.
    for (var ex = tester.takeException(); ex != null;) {
      final s = ex.toString();
      expect(s.contains('overflowed') || s.contains('Multiple exceptions'),
          isTrue,
          reason: 'hanya overflow layout pre-existing yang boleh: $s');
      ex = tester.takeException();
    }

    // Harus sudah landing di ProdukFormScreen...
    expect(find.text('Harga Jual (Rp)'), findsOneWidget,
        reason: 'harus sudah pindah ke ProdukFormScreen');
    // ...DAN cart sheet TIDAK BOLEH terbuka lagi di belakangnya (ini gejala
    // yang bisa diamati dari bug: reopen-otomatis cart sheet yang salah
    // ketika ItemEntrySheet ditutup karena navigasi, bukan edit selesai).
    expect(find.byType(CartSheet, skipOffstage: false), findsNothing,
        reason:
            'cart sheet tidak boleh dibuka ulang otomatis saat ItemEntrySheet '
            'ditutup karena navigasi ke ProdukFormScreen (tombol Edit produk)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
