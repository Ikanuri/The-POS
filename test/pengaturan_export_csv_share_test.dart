import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: "Buat ekspor csv produk bisa share juga (sama seperti
/// file backup)" — dites di sini: tap "Export Produk CSV" di Pengaturan
/// memunculkan dialog pilihan "Simpan CSV" dengan opsi "Bagikan" (share
/// sheet, tanpa disimpan lokal dulu) DAN "Simpan ke Perangkat" (alur lama
/// via FilePicker), alih-alih langsung memanggil FilePicker.saveFile diam-diam.
///
/// TIDAK menekan sampai tuntas ke "Bagikan"/"Simpan" — keduanya memanggil
/// plugin native (share_plus/file_picker) yang tak ada mock method
/// channel-nya di codebase ini (lihat `backup_share_option_test.dart`).
/// Cukup buktikan dialog pilihan muncul dgn kedua opsi & tombol Batal
/// berfungsi.
void main() {
  testWidgets(
      'PengaturanScreen: tap Export Produk CSV memunculkan dialog "Simpan '
      'CSV" dgn opsi Bagikan & Simpan ke Perangkat', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());

    await tester.scrollUntilVisible(
      find.text('Export Produk CSV'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Export Produk CSV'));
    // BUKAN pumpAndSettle: query produk berjalan async sebelum dialog
    // "Simpan CSV" muncul — pump manual spt di backup_share_option_test.dart.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Simpan CSV'), findsOneWidget);
    expect(find.text('Bagikan'), findsOneWidget);
    expect(find.text('Simpan ke Perangkat'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Simpan CSV'), findsNothing,
        reason: 'Batal harus menutup dialog tanpa memanggil plugin apa pun');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
