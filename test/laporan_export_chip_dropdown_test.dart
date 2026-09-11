import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laporan/laporan_screen.dart';

import 'helpers/pump_app.dart';

/// `showMenu` menutup lewat animasi + `_export`/`_share` lanjut proses async
/// (build byte laporan lalu panggil plugin native) SETELAH menu ditutup —
/// bukan timer tunggal, jadi tidak cukup 1-2 `pump(duration)` besar; WAJIB
/// beberapa pump kecil berurutan spy setiap tahap async (microtask/frame)
/// benar² kebagian giliran (pola sama `backup_share_option_test.dart`).
Future<void> _pumpUntilSettled(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Permintaan user: dropdown ekspor PDF/Excel didesain ulang jadi custom
/// (bukan `PopupMenuButton` teks polos bawaan Flutter) — redesain KEDUA:
/// BUKAN chip berbungkus badge warna, teks biasa + ikon garis custom
/// (`assets/icons/export_pdf.png`/`export_excel.png`) di atas background
/// transparan, tiap baris py ikon format + ikon share TERPISAH — tekan
/// badan baris = unduh ke HP, tekan ikon share = bagikan langsung (tanpa
/// nangkring lokal).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'tekan ikon download membuka dropdown custom (bukan PopupMenuButton '
      'teks polos) dgn 2 chip PDF & Excel, masing2 py ikon format + ikon '
      'share terpisah', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const LaporanScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();

    // Menu LAMA (PopupMenuButton teks polos) punya item persis "Export PDF
    // — Ringkasan"/"Export Excel — Ringkasan" — sekarang harus TIDAK ada.
    expect(find.textContaining('Export PDF'), findsNothing);
    expect(find.textContaining('Export Excel'), findsNothing);

    // Desain baru: label teks biasa "PDF"/"Excel" (bukan chip badge) + ikon
    // garis custom (`Image.asset`) per format + ikon share.
    expect(find.text('PDF'), findsOneWidget);
    expect(find.text('Excel'), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/icons/export_pdf.png'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/icons/export_excel.png'),
        findsOneWidget);
    expect(find.byIcon(Icons.share), findsNWidgets(2),
        reason: 'tiap baris (PDF & Excel) py ikon share sendiri-sendiri');
    // Badge warna & subtitle "Unduh ke HP" dari desain LAMA sudah dihapus.
    expect(find.byIcon(Icons.picture_as_pdf_rounded), findsNothing);
    expect(find.byIcon(Icons.grid_on_rounded), findsNothing);
    expect(find.textContaining('Unduh ke HP'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tekan BADAN chip PDF -> jalur unduh (pesan "Gagal export", bukan '
      '"Gagal membagikan") — plugin native memang belum di-mock di test '
      'environment ini (FilePicker.saveFile Linux throw UnimplementedError '
      'sinkron, bukan hang), tapi cukup utk buktikan jalur kode BEDA dari '
      'tekan ikon share', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const LaporanScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF'));
    await _pumpUntilSettled(tester);

    expect(find.text('PDF'), findsNothing,
        reason: 'menu harus tertutup setelah tap badan chip');
    expect(find.textContaining('Gagal export'), findsOneWidget,
        reason: 'jalur unduh memanggil FilePicker.saveFile (tak diimplementasi '
            'di lingkungan test) — errornya WAJIB lewat pesan "Gagal export", '
            'BUKAN "Gagal membagikan"');
    expect(find.textContaining('Gagal membagikan'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tekan ikon SHARE chip PDF -> menutup menu & TIDAK memunculkan pesan '
      '"Gagal export" (jalur kode BEDA dari tekan badan chip, yg gagal cepat '
      'lewat FilePicker.saveFile) — Share.shareXFiles sungguhan yg dipanggil '
      'jalur ini tak pernah selesai dlm environment test (tak ada mock '
      'channel-nya, pola sama dok `backup_share_option_test.dart`), jadi '
      'TIDAK dites sampai tuntas ke pesan sukses/gagalnya', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const LaporanScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pumpAndSettle();
    // 2 ikon share (PDF & Excel) — ambil yang PERTAMA (chip PDF, urutan
    // deklarasi di `_ExportChipsPanel`).
    await tester.tap(find.byIcon(Icons.share).first);
    // Bounded (BUKAN _pumpUntilSettled/pumpAndSettle) — panggilan
    // Share.shareXFiles sungguhan di jalur ini tak pernah resolve di
    // environment test, jadi jangan tunggu lama-lama sia-sia.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.share), findsNothing,
        reason: 'menu harus tertutup setelah tap ikon share');
    // Pembeda utama dari test sebelumnya (tekan badan chip): jalur SHARE
    // TIDAK pernah menghasilkan pesan "Gagal export" (pesan spesifik jalur
    // FilePicker.saveFile) — membuktikan kedua tap-zone benar² memanggil
    // fungsi yang BERBEDA (`_share`/`shareReport`, bukan `_export`/
    // `exportReport`).
    expect(find.textContaining('Gagal export'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
