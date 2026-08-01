import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user), 2 perubahan tata letak baris keranjang:
/// 1. Nominal subtotal pindah ke BAWAH baris qty — dulu sebaris di kanan
///    stepper, sehingga lebar teks rupiah yang berubah tiap qty diketuk
///    ("Rp 65.000" -> "Rp 130.000") MENGGESER stepper di bawah jari.
/// 2. Checkbox verifikasi pindah dari kiri baris ke kanan, persis di kiri
///    tombol minus stepper.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  final prefs = {
    'cart_v1_main': jsonEncode([
      const CartItem(
        productId: 'P1',
        productUnitId: 'U1',
        productName: 'Beras 5kg',
        unitName: 'Karung',
        qty: 1,
        price: 65000,
        originalPrice: 65000,
        costPrice: 55000,
      ).toJson(),
    ]),
  };

  Future<void> pumpCart(WidgetTester tester) => pumpWithFakeApp(tester,
      db: db,
      initialPrefs: prefs,
      surfaceSize: const Size(360, 800),
      child: const CartSheet());

  testWidgets('checkbox berada di KANAN (setelah nama produk) & KIRI stepper',
      (tester) async {
    await pumpCart(tester);

    final checkbox = tester.getCenter(find.byType(Checkbox));
    final name = tester.getCenter(find.text('Beras 5kg'));
    final stepperLeft = tester.getTopLeft(find.byType(AddControl)).dx;

    expect(checkbox.dx, greaterThan(name.dx),
        reason: 'checkbox tidak lagi di kiri baris — pindah ke sisi kanan');
    expect(checkbox.dx, lessThan(stepperLeft),
        reason: 'checkbox harus persis di KIRI stepper (tombol minus)');
  });

  testWidgets('nominal subtotal berada DI BAWAH baris stepper, bukan sebaris',
      (tester) async {
    await pumpCart(tester);

    // Subtotal baris item (qty 1 x 65.000). Nominal yang sama juga muncul di
    // ringkasan Total cart bar, jadi diambil yang paling atas (baris item).
    final subtotal = find.text(formatRupiah(65000)).first;
    final stepper = find.byType(AddControl);

    expect(tester.getCenter(subtotal).dy,
        greaterThan(tester.getBottomLeft(stepper).dy - 1),
        reason: 'nominal harus di bawah baris qty, bukan sejajar di sampingnya');
    expect(tester.getCenter(subtotal).dx,
        closeTo(tester.getCenter(stepper).dx, 60),
        reason: 'tetap di blok kanan yang sama (rata kanan), bukan pindah '
            'jauh ke kiri baris');
  });

  testWidgets(
      'stepper TIDAK bergeser saat qty ditambah walau lebar nominal berubah '
      '(Rp 65.000 -> Rp 130.000)', (tester) async {
    await pumpCart(tester);

    final before = tester.getRect(find.byType(AddControl));
    await tester.tap(find.descendant(
        of: find.byType(AddControl), matching: find.text('1')));
    await tester.pumpAndSettle();

    // Prasyarat: nominalnya memang berubah jadi lebih lebar.
    expect(find.text(formatRupiah(130000)), findsWidgets,
        reason: 'prasyarat: qty benar-benar naik jadi 2 (nominal 2x lipat)');
    expect(tester.getRect(find.byType(AddControl)), before,
        reason: 'stepper harus tetap di kotak yang sama persis — inilah '
            'alasan nominal dipindah ke baris bawah');
  });
}
