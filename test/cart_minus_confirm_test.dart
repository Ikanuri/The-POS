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

  testWidgets(
      'toggle OFF (default): tap minus langsung kurangi qty tanpa dialog',
      (tester) async {
    await pumpCart(tester);

    await tester.tap(find.descendant(
        of: find.byType(AddControl), matching: find.byIcon(Icons.remove_rounded)));
    await tester.pumpAndSettle();

    expect(find.text('Kurangi Qty?'), findsNothing,
        reason: 'default OFF — tidak boleh ada dialog konfirmasi');
    expect(find.text('1×'), findsOneWidget,
        reason: 'qty harus langsung berkurang jadi 1 tanpa perlu konfirmasi');
  });

  testWidgets(
      'toggle ON: tap minus munculkan dialog konfirmasi, Batal TIDAK '
      'mengurangi qty', (tester) async {
    await pumpCart(tester, minusConfirmOn: true);

    await tester.tap(find.descendant(
        of: find.byType(AddControl), matching: find.byIcon(Icons.remove_rounded)));
    await tester.pumpAndSettle();

    expect(find.text('Kurangi Qty?'), findsOneWidget);
    expect(find.textContaining('Beras 5kg'), findsWidgets);

    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();

    // Qty tidak berubah — masih tampil "2" di badge kiri.
    expect(find.text('2×'), findsOneWidget);
  });

  testWidgets(
      'toggle ON: tap minus lalu konfirmasi "Kurangi" -> qty benar-benar '
      'berkurang', (tester) async {
    await pumpCart(tester, minusConfirmOn: true);

    await tester.tap(find.descendant(
        of: find.byType(AddControl), matching: find.byIcon(Icons.remove_rounded)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kurangi'));
    await tester.pumpAndSettle();

    expect(find.text('1×'), findsOneWidget);
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
