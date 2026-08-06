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
/// Desain AWAL fitur ini pakai dialog konfirmasi (AlertDialog "Kurangi
/// Qty?") — DIGANTI TOTAL atas permintaan user (jempol biasanya menutupi
/// tombol minus itu sendiri, jadi warning yang cuma di tombol/stepper tidak
/// kentara). Sekarang: tap PERTAMA membuat SELURUH baris bergetar (warning),
/// TANPA mengurangi qty — tap KEDUA yang jatuh dalam ~1.5 detik baru
/// benar-benar mengurangi qty. Lewat jendela itu tanpa tap kedua, kembali
/// netral (harus getar ulang).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final cartJson = jsonEncode([
    const CartItem(
      productId: 'P1',
      productUnitId: 'U1',
      productName: 'Beras 5kg',
      unitName: 'Karung',
      qty: 2,
      price: 65000,
      originalPrice: 65000,
      costPrice: 55000,
    ).toJson(),
  ]);

  Future<void> pumpCart(WidgetTester tester, {bool minusConfirmOn = false}) =>
      pumpWithFakeApp(tester,
          db: db,
          initialPrefs: {
            'cart_v1_main': cartJson,
            if (minusConfirmOn) 'cart_minus_confirm': true,
          },
          surfaceSize: const Size(360, 800),
          child: const CartSheet());

  Future<void> tapMinus(WidgetTester tester) => tester.tap(find.descendant(
      of: find.byType(AddControl), matching: find.byIcon(Icons.remove_rounded)));

  testWidgets('toggle OFF (default): tap minus langsung kurangi qty',
      (tester) async {
    await pumpCart(tester);

    await tapMinus(tester);
    await tester.pump();

    expect(find.text('1×'), findsOneWidget,
        reason: 'qty harus langsung berkurang tanpa perlu tap kedua');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'toggle ON: tap PERTAMA TIDAK mengurangi qty (cuma warning getar)',
      (tester) async {
    await pumpCart(tester, minusConfirmOn: true);

    await tapMinus(tester);
    await tester.pump();
    // Biarkan animasi getar berjalan sebagian, tapi belum tap kedua.
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('2×'), findsOneWidget,
        reason: 'tap pertama cuma warning, qty belum boleh berkurang');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'toggle ON: tap KEDUA yang cepat (dalam jendela waktu) baru benar-'
      'benar mengurangi qty', (tester) async {
    await pumpCart(tester, minusConfirmOn: true);

    await tapMinus(tester);
    await tester.pump(const Duration(milliseconds: 300));
    await tapMinus(tester);
    await tester.pump();

    expect(find.text('1×'), findsOneWidget,
        reason: 'tap kedua dalam jendela waktu harus benar-benar mengurangi qty');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'toggle ON: tap kedua SETELAH jendela waktu habis dianggap tap '
      'PERTAMA lagi (tidak mengurangi, harus getar ulang)', (tester) async {
    await pumpCart(tester, minusConfirmOn: true);

    await tapMinus(tester);
    // Lewati jendela ~1.5 detik tanpa tap kedua.
    await tester.pump(const Duration(seconds: 2));
    await tapMinus(tester);
    await tester.pump();

    expect(find.text('2×'), findsOneWidget,
        reason: 'tap setelah jendela habis dianggap tap PERTAMA lagi, '
            'bukan konfirmasi');

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
