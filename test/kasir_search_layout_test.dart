import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

import 'helpers/pump_app.dart';

/// Widget test — kolom cari collapsed TIDAK BOLEH menimpa tombol scan;
/// jaraknya harus persis sama dengan jarak antar tombol topbar lainnya
/// (mis. scan↔antrian), bukan ditaksir/hardcode. Regresi dari sesi
/// sebelumnya: lebar collapsed sempat di-hardcode 128px, lebih lebar dari
/// ruang yang sebenarnya tersedia sebelum baris tombol dimulai → menimpa
/// kotak scan walau field belum disentuh sama sekali.
void main() {
  testWidgets(
      'field cari collapsed berhenti tepat sebelum tombol scan, dengan '
      'jarak yang sama seperti antar-tombol lain (tidak overlap)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    final fieldBox =
        tester.renderObject<RenderBox>(find.byType(TextField).first);
    final fieldRight =
        fieldBox.localToGlobal(Offset(fieldBox.size.width, 0)).dx;

    final scanBox = tester.renderObject<RenderBox>(
        find.byIcon(Icons.qr_code_scanner_rounded).first);
    final scanLeft = scanBox.localToGlobal(Offset.zero).dx;

    // Ikon di dalam _TbBtn punya inset dari kotak 36px-nya sendiri (bukan
    // langsung di tepi kiri kotak) — bandingkan lewat kotak pembungkusnya
    // (parent Container 36x36), bukan langsung ikonnya, supaya presisi.
    final scanContainerBox = tester
        .element(find.byIcon(Icons.qr_code_scanner_rounded).first)
        .findAncestorRenderObjectOfType<RenderBox>();
    final scanContainerLeft =
        scanContainerBox?.localToGlobal(Offset.zero).dx ?? scanLeft;

    final gap = scanContainerLeft - fieldRight;
    expect(gap, greaterThanOrEqualTo(0),
        reason: 'field cari collapsed TIDAK BOLEH menimpa tombol scan '
            '(gap negatif = overlap). fieldRight=$fieldRight '
            'scanLeft=$scanContainerLeft');
    expect(gap, closeTo(4.0, 2.0),
        reason: 'jarak field↔scan harus sama seperti jarak antar tombol '
            'topbar lain (4px), bukan berjarak jauh/menimpa');

    await db.close();
  });

  testWidgets(
      'label tombol topbar (mis. "Antrian") punya jarak/napas ke divider di '
      'bawahnya, TIDAK menyentuh/berdesakan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    expect(tester.takeException(), isNull,
        reason: 'topbar tidak boleh melempar RenderFlex overflow apa pun '
            'akibat label tombol/field cari');

    final labelBox = tester.renderObject<RenderBox>(find.text('Antrian'));
    final labelBottom =
        labelBox.localToGlobal(Offset(0, labelBox.size.height)).dy;

    final dividerBox =
        tester.renderObject<RenderBox>(find.byType(Divider).first);
    final dividerTop = dividerBox.localToGlobal(Offset.zero).dy;

    final gap = dividerTop - labelBottom;
    expect(gap, greaterThanOrEqualTo(2.0),
        reason: 'label "Antrian" harus punya jarak napas ke divider di '
            'bawahnya (bukan menyentuh/terpotong). labelBottom=$labelBottom '
            'dividerTop=$dividerTop gap=$gap');

    await db.close();
  });
}
