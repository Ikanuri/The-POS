import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/archive_service.dart';
import 'package:the_pos/features/pengaturan/arsip_screen.dart';

import 'helpers/pump_app.dart';

/// Fitur "Ekspor Arsip" (`arsip_screen.dart`) — tiap baris arsip dapat
/// tombol "Ekspor Arsip Ini" TERPISAH dari tombol "Lihat Ringkasan" yang
/// sudah ada, membuka dialog password (pola sama dgn `backup_screen.dart`),
/// lalu memanggil alur ekspor .posarsip (BPOA1). Test ini TIDAK menembus
/// sampai plugin native `file_picker`/`share_plus` sungguhan (sama seperti
/// `backup_share_option_test.dart` — tidak ada mock method channel utk itu
/// di codebase ini) — cukup buktikan tombol muncul & dialog password +
/// dialog "Simpan Backup" (dari `saveOrShareExport`) muncul dgn parameter
/// yang benar (tahun arsip yang tepat disebut di teks dialog), dan
/// `ArchiveService.open`/`exportArchive` benar2 terpanggil dgn arsip nyata.
///
/// CATATAN LINGKUNGAN (dikonfirmasi lewat reproduksi terisolasi, TIDAK
/// terkait fitur ini): `Directory.list()`/`File.copy()` (dart:io async
/// isolate-based I/O) HANG TANPA BATAS di dalam `testWidgets` sandbox CI di
/// sini — NativeDatabase (FFI sqlite3, sinkron) TIDAK kena masalah ini.
/// Makanya arsip di sini dibuat LANGSUNG via `NativeDatabase` (bukan lewat
/// `TutupBukuService.execute`, yang pakai `File.copy`), dan
/// `archiveListProvider` (nama diekspos khusus utk ini — lihat komentar di
/// `arsip_screen.dart`) di-override manual (bukan lewat
/// `ArchiveService.listArchives`, yang pakai `Directory.list`). Alur EKSPOR
/// sungguhan yg diuji (`ArchiveService.open`/`DbExportService.exportArchive`)
/// TIDAK memakai `Directory.list`/`File.copy` sama sekali — jalan normal.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);
  final String docsPath;
  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPlatform;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pos_arsip_export_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPlatform;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets(
      'ArsipScreen: tombol "Ekspor Arsip Ini" muncul per baris arsip & '
      'membuka dialog password yang menyebut tahun arsip yang benar',
      (tester) async {
    // Arsip 2024 dibuat LANGSUNG via NativeDatabase (FFI sinkron, aman di
    // testWidgets) — BUKAN lewat TutupBukuService.execute (pakai File.copy
    // async, lihat catatan lingkungan di atas).
    final archiveFile = File('${tempDir.path}/archive_2024.db');
    final archiveSetupDb = AppDatabase(NativeDatabase(archiveFile));
    await archiveSetupDb.into(archiveSetupDb.transactions).insert(
        TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-A',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await archiveSetupDb.close();
    final archiveSize = archiveFile.lengthSync();

    final dummyDb = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(
      tester,
      db: dummyDb,
      device: const DeviceIdentity(
        storeUuid: 'test-store-uuid',
        storeKey: 'test-store-key',
        storeName: 'Toko Uji',
        deviceName: 'Owner',
        deviceCode: 'O1',
        deviceRole: 'owner',
      ),
      // Bypass ArchiveService.listArchives (pakai Directory.list — hang di
      // sandbox ini) — arsip yang tampil cukup 1 baris tetap ("2024") sesuai
      // file yang sudah dibuat di atas, TANPA menyentuh dart:io async.
      extraOverrides: [
        archiveListProvider.overrideWith((ref, encryptionKey) async => [
              ArchiveInfo(
                year: 2024,
                path: archiveFile.path,
                sizeBytes: archiveSize,
                summaryCount: 0,
                txCount: 1,
              ),
            ]),
      ],
      child: const ArsipScreen(),
    );

    expect(find.text('Arsip 2024'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget,
        reason: 'Tombol ekspor arsip harus punya ikon berbeda dari tombol '
            'Lihat Ringkasan (Icons.bar_chart_outlined)');
    expect(find.byIcon(Icons.bar_chart_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();

    expect(find.text('Password Ekspor Arsip'), findsOneWidget);
    expect(
      find.textContaining('arsip tahun 2024'),
      findsOneWidget,
      reason: 'Dialog password harus menyebut tahun arsip yang benar',
    );

    // Batal harus menutup dialog tanpa memanggil apa pun.
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Password Ekspor Arsip'), findsNothing);

    // Password terlalu pendek ditolak (pola sama dgn backup_screen.dart).
    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pendek');
    await tester.tap(find.text('Lanjutkan'));
    await tester.pump();
    expect(find.text('Password minimal 8 karakter'), findsOneWidget);

    // Password valid → ArchiveService.open + DbExportService.exportArchive
    // benar2 dipanggil (arsip nyata dibaca via FFI, aman di sandbox ini),
    // lalu lanjut ke dialog pilihan simpan/bagikan (`saveOrShareExport`).
    await tester.enterText(find.byType(TextField), 'password123');
    await tester.tap(find.text('Lanjutkan'));
    // BUKAN pumpAndSettle — proses ekspor (_exporting=true) menampilkan
    // CircularProgressIndicator (animasi tak terbatas) selagi menunggu
    // dialog "Simpan Backup" berikutnya (lihat gotcha yang sama di
    // backup_share_option_test.dart).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Simpan Backup'), findsOneWidget,
        reason: 'Password valid harus lanjut ke dialog saveOrShareExport '
            'setelah ArchiveService.open/exportArchive sukses');
    expect(find.text('Bagikan'), findsOneWidget);
    expect(find.text('Simpan ke Perangkat'), findsOneWidget);

    // Dialog "Simpan Backup" (dari saveOrShareExport) masih menunggu user —
    // _exportArchive belum sampai ke `finally { ArchiveService.close() }`
    // (masih di dalam `await saveOrShareExport(...)`). Batal dulu, BARU
    // koneksi arsip ditutup — buktikan itu benar2 terjadi (bukan nyangkut
    // terbuka).
    await tester.tap(find.text('Batal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Simpan Backup'), findsNothing);
    expect(ArchiveService.openYear, isNull,
        reason: 'Koneksi arsip yang dibuka utk ekspor harus SUDAH ditutup '
            'lagi (finally { ArchiveService.close() }), tidak nyangkut '
            'terbuka setelah ekspor selesai/dibatalkan.');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await dummyDb.close();
  });
}
