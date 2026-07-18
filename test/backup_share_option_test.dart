import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/pengaturan/alih_owner_screen.dart';
import 'package:the_pos/features/pengaturan/backup_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: "Untuk backup, alih-alih simpan ke storage, juga
/// berikan opsi share agar bisa langsung share ke cloud tanpa nangkring di
/// local. semua jenis backup, baik itu BPO2 atau lainnya" — dites di sini:
/// setelah password diisi, muncul dialog pilihan "Simpan Backup" dgn opsi
/// "Bagikan" (share sheet, tanpa disimpan lokal dulu) DAN "Simpan ke
/// Perangkat" (alur lama), utk KEDUA jenis file backup (BPOP2 di
/// BackupScreen, BPOT1 di AlihOwnerScreen).
///
/// TIDAK menekan sampai tuntas ke "Bagikan"/"Simpan" — keduanya memanggil
/// plugin native (share_plus/file_picker) yg tak ada mock method channel-nya
/// di codebase ini sama sekali (dicek: tak ada satupun test lain yg
/// menembus Share.shareXFiles/FilePicker.saveFile sungguhan). Cukup
/// buktikan dialog pilihan muncul dgn kedua opsi & tombol Batal berfungsi.
void main() {
  testWidgets(
      'BackupScreen: setelah password diisi, dialog "Simpan Backup" muncul '
      'dgn opsi Bagikan & Simpan ke Perangkat', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const BackupScreen());

    await tester.tap(find.text('Buat Backup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'password123');
    await tester.tap(find.text('Lanjutkan'));
    // BUKAN pumpAndSettle: begitu password dialog ditutup, _busy=true
    // menampilkan CircularProgressIndicator (animasi tak terbatas) SELAGI
    // proses export berjalan & dialog "Simpan Backup" ditunggu — pumpAndSettle
    // akan macet selamanya menunggu animasi itu berhenti.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Simpan Backup'), findsOneWidget);
    expect(find.text('Bagikan'), findsOneWidget);
    expect(find.text('Simpan ke Perangkat'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Simpan Backup'), findsNothing,
        reason: 'Batal harus menutup dialog tanpa memanggil plugin apa pun');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'AlihOwnerScreen (BPOT1): dialog "Simpan Backup" yg SAMA jg muncul '
      'setelah password diisi — opsi share berlaku utk semua jenis backup',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(
      tester,
      db: db,
      device: const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Owner',
          deviceCode: 'O1',
          deviceRole: 'owner'),
      child: const AlihOwnerScreen(),
    );

    await tester.tap(find.ancestor(
        of: find.text('Buat File Alihan'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'password123');
    await tester.tap(find.text('Lanjutkan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Simpan Backup'), findsOneWidget);
    expect(find.text('Bagikan'), findsOneWidget);
    expect(find.text('Simpan ke Perangkat'), findsOneWidget);

    await tester.tap(find.text('Batal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Simpan Backup'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
