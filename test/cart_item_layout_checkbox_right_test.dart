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

/// Susulan (permintaan user), tata letak baris keranjang:
/// 1. Nominal subtotal taruh PERSIS di bawah baris satuan+harga
///    ("Karung · Rp 65.000") — BUKAN di bawah qty badge kiri (percobaan
///    pertama, ditolak user) atau di bawah stepper (percobaan kedua,
///    juga ditolak — keduanya membuat stepper harus dibungkus ulang).
/// 2. Checkbox verifikasi pindah dari kiri baris ke kanan, persis di kiri
///    tombol minus, dengan jarak DIRENGGANGKAN dari stepper.
/// 3. Desain stepper (`AddControl`) sendiri TIDAK diubah sama sekali.
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

  testWidgets(
      'jarak checkbox ke stepper direnggangkan (bukan mepet spt sebelumnya)',
      (tester) async {
    await pumpCart(tester);

    final checkboxRight = tester.getTopRight(find.byType(Checkbox)).dx;
    final stepperLeft = tester.getTopLeft(find.byType(AddControl)).dx;

    expect(stepperLeft - checkboxRight, greaterThanOrEqualTo(12),
        reason: 'jarak checkbox->stepper harus renggang (>=12px), bukan '
            'mepet 4px seperti sebelumnya');
  });

  testWidgets(
      'nominal subtotal PERSIS di bawah baris "Karung · Rp 65.000", bukan di '
      'bawah qty badge atau di blok kanan (stepper)', (tester) async {
    await pumpCart(tester);

    final meta = find.textContaining('Karung');
    final subtotal = find.text(formatRupiah(65000)).first;
    final stepper = find.byType(AddControl);

    // Di bawah baris satuan+harga (bukan sejajar/di atasnya).
    expect(tester.getCenter(subtotal).dy, greaterThan(tester.getCenter(meta).dy),
        reason: 'nominal harus di bawah baris "satuan · harga"');
    // Rata kiri sejajar nama/meta (blok kiri), BUKAN di blok kanan (stepper).
    expect(tester.getTopLeft(subtotal).dx,
        closeTo(tester.getTopLeft(meta).dx, 2),
        reason: 'nominal harus rata-kiri sejajar nama & meta, bukan pindah '
            'ke blok kanan (stepper)');
    expect(tester.getCenter(subtotal).dx, lessThan(tester.getCenter(stepper).dx),
        reason: 'nominal tidak boleh berada di blok kanan (stepper)');
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
        reason: 'stepper harus tetap di kotak yang sama persis');
  });
}
