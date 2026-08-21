import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Fitur baru (permintaan user): toggle "Konfirmasi sebelum kurangi qty" di
/// dialog "Pengaturan Keranjang" — mencegah qty berkurang tanpa sengaja
/// (missclick) saat menekan tombol minus stepper baris keranjang. Default
/// OFF (opt-in) — tanpa diaktifkan, tap minus tetap langsung mengurangi qty
/// persis seperti sebelumnya (dibuktikan file test lain, mis.
/// `cart_checklist_test.dart`).
///
/// Desain fitur ini sudah 2x berubah:
/// 1. Dialog konfirmasi (AlertDialog "Kurangi Qty?") — DIGANTI krn jempol
///    biasanya menutupi tombol minus itu sendiri.
/// 2. Getar+tap-lagi dgn JENDELA WAKTU TETAP (1.5 detik) — DIGANTI LAGI krn
///    user kadang butuh menekan minus BERKALI-KALI beruntun (spt stepper
///    biasa) tanpa pindah jempol; jendela waktu tetap bikin tap yang
///    terlambat (tapi jempol MASIH di situ) dianggap tap pertama lagi.
///
/// Desain FINAL (diuji di sini): tap PERTAMA membuat baris bergetar
/// (warning, qty belum berkurang) & "bersenjata" SELAMA stepper baris ini
/// masih membesar (`AddControl.activeStepper` — mekanisme "pijakan jempol"
/// yang sudah ada, TIDAK diubah). Tap berikutnya SELAMA masih bersenjata
/// benar-benar mengurangi qty (BOLEH berkali-kali beruntun, tanpa perlu
/// getar ulang) — status ini HANYA lepas kalau stepper baris LAIN jadi
/// aktif (jempol pindah) atau scroll, TIDAK PERNAH krn lewat waktu.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final oneItemCart = jsonEncode([
    const CartItem(
      productId: 'P1',
      productUnitId: 'U1',
      productName: 'Beras 5kg',
      unitName: 'Karung',
      qty: 3,
      price: 65000,
      originalPrice: 65000,
      costPrice: 55000,
    ).toJson(),
  ]);

  final twoItemCart = jsonEncode([
    const CartItem(
      productId: 'P1',
      productUnitId: 'U1',
      productName: 'Beras 5kg',
      unitName: 'Karung',
      qty: 3,
      price: 65000,
      originalPrice: 65000,
      costPrice: 55000,
    ).toJson(),
    const CartItem(
      productId: 'P2',
      productUnitId: 'U2',
      productName: 'Minyak Goreng',
      unitName: 'Liter',
      qty: 2,
      price: 18000,
      originalPrice: 18000,
      costPrice: 15000,
    ).toJson(),
  ]);

  Future<void> pumpCart(WidgetTester tester,
          {bool minusConfirmOn = false, String? cartJson}) =>
      pumpWithFakeApp(tester,
          db: db,
          initialPrefs: {
            'cart_v1_main': cartJson ?? oneItemCart,
            if (minusConfirmOn) 'cart_minus_confirm': true,
          },
          surfaceSize: const Size(360, 800),
          child: const CartSheet());

  // Setiap `_CartItemTile` punya tepat SATU `InkWell` pembungkus baris —
  // dipakai sbg batas pencarian per-baris (bukan `find.ancestor` langsung
  // ke `AddControl`, krn nama produk & `AddControl` SEJAJAR/sibling di
  // dalam Row yang sama, bukan hubungan ancestor-descendant).
  Finder rowOf(String productName) => find.ancestor(
      of: find.text(productName), matching: find.byType(InkWell));

  Future<void> tapMinusOf(WidgetTester tester, String productName) =>
      tester.tap(find.descendant(
        of: find.descendant(
            of: rowOf(productName), matching: find.byType(AddControl)),
        matching: find.byIcon(Icons.remove_rounded),
      ));

  testWidgets('toggle OFF (default): tap minus langsung kurangi qty',
      (tester) async {
    await pumpCart(tester);

    await tapMinusOf(tester, 'Beras 5kg');
    await tester.pump();

    expect(find.text('2×'), findsOneWidget,
        reason: 'qty harus langsung berkurang tanpa perlu tap kedua');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'toggle ON: tap PERTAMA TIDAK mengurangi qty (cuma warning getar)',
      (tester) async {
    await pumpCart(tester, minusConfirmOn: true);

    await tapMinusOf(tester, 'Beras 5kg');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('3×'), findsOneWidget,
        reason: 'tap pertama cuma warning, qty belum boleh berkurang');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'toggle ON: tap KEDUA (walau jeda LAMA, tanpa pindah jempol) tetap '
      'benar-benar mengurangi qty — TIDAK ADA jendela waktu lagi',
      (tester) async {
    await pumpCart(tester, minusConfirmOn: true);

    await tapMinusOf(tester, 'Beras 5kg');
    await tester.pump();
    // Jeda JAUH lebih lama dari bekas jendela waktu 1.5 detik versi lama —
    // TIDAK boleh membatalkan status bersenjata krn tidak ada timer lagi.
    await tester.pump(const Duration(seconds: 5));
    await tapMinusOf(tester, 'Beras 5kg');
    await tester.pump();

    expect(find.text('2×'), findsOneWidget,
        reason: 'tap kedua harus tetap dianggap konfirmasi walau jeda lama, '
            'selama jempol tidak pindah ke stepper lain');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'toggle ON: setelah tap pertama, tap KEDUA/KETIGA/dst beruntun '
      'langsung mengurangi qty tiap kali (spt stepper biasa, tanpa getar '
      'ulang)', (tester) async {
    await pumpCart(tester, minusConfirmOn: true);

    await tapMinusOf(tester, 'Beras 5kg'); // arm — belum kurangi
    await tester.pump();
    await tapMinusOf(tester, 'Beras 5kg'); // 3 -> 2
    await tester.pump();
    await tapMinusOf(tester, 'Beras 5kg'); // 2 -> 1
    await tester.pump();

    expect(find.text('1×'), findsOneWidget,
        reason: 'dua tap beruntun setelah tap pertama harus mengurangi qty '
            'dua kali, bukan cuma sekali');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'toggle ON: pindah jempol ke stepper baris LAIN melepas status '
      'bersenjata — tap minus baris semula lagi dianggap tap PERTAMA lagi',
      (tester) async {
    await pumpCart(tester, minusConfirmOn: true, cartJson: twoItemCart);

    await tapMinusOf(tester, 'Beras 5kg'); // arm baris pertama
    await tester.pump();
    // Jempol pindah ke stepper baris LAIN — tap tombol minus baris kedua
    // (cukup utk mengaktifkan stepper-nya, biar `minusConfirm` ON juga
    // TIDAK ikut mengurangi qty baris kedua, tidak relevan utk test ini).
    await tapMinusOf(tester, 'Minyak Goreng');
    await tester.pump();

    // Balik ke baris pertama — tap minus sekali lagi HARUS dianggap tap
    // PERTAMA lagi (cuma getar, qty belum berkurang).
    await tapMinusOf(tester, 'Beras 5kg');
    await tester.pump();

    expect(find.text('3×'), findsOneWidget,
        reason: 'status bersenjata baris pertama harus sudah lepas krn '
            'jempol sempat pindah ke stepper baris lain');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'dialog "Pengaturan Keranjang" menampilkan toggle & tap mengubah state '
      'persisten', (tester) async {
    await pumpCart(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Konfirmasi sebelum kurangi qty'), findsOneWidget);
    final switchFinder = find.byType(Switch);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isTrue);
  });
}
