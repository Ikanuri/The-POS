import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

import 'helpers/pump_app.dart';

/// Fitur baru (permintaan user): tombol "Pengaturan Keranjang" di header
/// `CartSheet` (di samping ikon "Tempel Pesanan") membuka dialog dengan 4
/// opsi letak checkbox verifikasi baris keranjang — tersimpan persisten
/// lewat `cartCheckboxPositionProvider` (SharedPreferences key
/// `cart_checkbox_position`, pola sama dgn `fontScaleProvider`). Test ini
/// membuktikan tiap opsi benar-benar mengubah posisi render checkbox
/// (bukan cuma tersimpan tanpa efek visual).
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
      qty: 1,
      price: 65000,
      originalPrice: 65000,
      costPrice: 55000,
    ).toJson(),
  ]);

  Future<void> pumpCartWithPosition(
      WidgetTester tester, String? positionName) async {
    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: {
          'cart_v1_main': cartJson,
          if (positionName != null) 'cart_checkbox_position': positionName,
        },
        surfaceSize: const Size(360, 800),
        child: const CartSheet());
  }

  testWidgets(
      'default (belum diatur): checkbox tetap di paling KIRI baris (depan qty)',
      (tester) async {
    await pumpCartWithPosition(tester, null);

    final checkbox = tester.getCenter(find.byType(Checkbox));
    final name = tester.getCenter(find.text('Beras 5kg'));
    final stepperLeft = tester.getTopLeft(find.byType(AddControl)).dx;

    expect(checkbox.dx, lessThan(name.dx));
    expect(checkbox.dx, lessThan(stepperLeft));
  });

  testWidgets(
      'opsi "belakangStepper": checkbox di KANAN stepper, paling kanan baris',
      (tester) async {
    await pumpCartWithPosition(tester, 'belakangStepper');

    final checkbox = tester.getCenter(find.byType(Checkbox));
    final stepperRight = tester.getTopRight(find.byType(AddControl)).dx;
    final name = tester.getCenter(find.text('Beras 5kg'));

    expect(checkbox.dx, greaterThan(stepperRight),
        reason: 'checkbox harus di kanan stepper');
    expect(checkbox.dx, greaterThan(name.dx));
  });

  testWidgets('opsi "kiriStepper": checkbox tepat di KIRI stepper (blok kanan)',
      (tester) async {
    await pumpCartWithPosition(tester, 'kiriStepper');

    final checkbox = tester.getCenter(find.byType(Checkbox));
    final stepperLeft = tester.getTopLeft(find.byType(AddControl)).dx;
    final name = tester.getCenter(find.text('Beras 5kg'));

    expect(checkbox.dx, lessThan(stepperLeft),
        reason: 'checkbox harus di kiri stepper');
    expect(checkbox.dx, greaterThan(name.dx),
        reason: 'tapi tetap di blok KANAN (kanan nama), bukan di kiri baris');
  });

  testWidgets(
      'opsi "kananNama": checkbox menempel PAS setelah nama, BUKAN terdorong '
      'ke ujung kanan baris (nama pendek)', (tester) async {
    await pumpCartWithPosition(tester, 'kananNama');

    final checkboxLeft = tester.getTopLeft(find.byType(Checkbox)).dx;
    final nameRight = tester.getTopRight(find.text('Beras 5kg')).dx;
    final stepperLeft = tester.getTopLeft(find.byType(AddControl)).dx;

    expect(checkboxLeft, greaterThan(nameRight));
    // "Beras 5kg" pendek — checkbox harus nempel dekat, JAUH dari stepper
    // (bukti bukan ke-stretch/dipaksa ke ujung kanan baris).
    expect(checkboxLeft - nameRight, lessThan(40),
        reason: 'checkbox harus menempel dekat nama, bukan terdorong jauh '
            'ke kanan (menyesuaikan panjang nama)');
    expect(checkboxLeft, lessThan(stepperLeft));
  });
}
