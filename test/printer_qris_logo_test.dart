import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/services/printer_service.dart';

/// Poin 3 (permintaan user): logo QRIS resmi ikut dicetak thermal, BUKAN
/// sekadar teks "QRIS" polos. Asetnya (`assets/qris/qris_logo.png`) latar
/// TRANSPARAN, wordmark hitam solid.
///
/// Bug nyata yang WAJIB dicegah: piksel latar transparan di file aslinya
/// kebetulan RGB (0,0,0) — SAMA PERSIS dgn RGB wordmark hitamnya sendiri.
/// `Generator._toRasterFormat` (dipanggil `imageRaster` sblm cetak) HANYA
/// membaca kanal RGB via `grayscale()`+`invert()`, TIDAK PERNAH melihat
/// alpha — jadi tanpa komposit ke kanvas putih solid dulu, printer akan
/// mencetak satu blok padat (logo & background sama-sama "hitam" secara
/// RGB), bukan bentuk logo yang sebenarnya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PrinterService.debugClearQrisLogoCache();
  });

  testWidgets(
      'logo QRIS: setelah dikomposit ke putih, latar & wordmark PUNYA '
      'kontras nyata (bukan satu blok padat)', (tester) async {
    // Widget test (bukan test murni) krn perlu `rootBundle` asli utk
    // memuat aset PNG sungguhan dari disk.
    final logo = await PrinterService.debugQrisLogo(384);
    expect(logo, isNotNull);

    // Titik yang dikonfirmasi manual dari file asetnya: (5,5) di pojok
    // (latar, alpha 0 di file asli) vs (190,190) tengah (wordmark, alpha
    // 255) -- skala proporsional thd lebar target 384 dari lebar asli 1350.
    final bg = logo!.getPixel(1, 1);
    final fg = logo.getPixel(114, 73); // ~(400,256) di skala 1350 lebar asli

    expect(bg.r, greaterThan(200),
        reason: 'latar HARUS jadi putih terang setelah komposit');
    expect(fg.r, lessThan(50),
        reason: 'wordmark HARUS tetap hitam pekat setelah komposit');
    expect((bg.r - fg.r).abs(), greaterThan(150),
        reason: 'kontras nyata -- kalau gagal komposit, keduanya bernilai '
            'RGB nyaris sama (sama-sama dari kanal RGB=0 di file asli)');
  });

  testWidgets('logo QRIS: lebar hasil sesuai targetWidthDots yang diminta',
      (tester) async {
    final logo = await PrinterService.debugQrisLogo(200);
    expect(logo, isNotNull);
    expect(logo!.width, 200);
  });

  testWidgets(
      'aset qris_logo.png terdaftar & bisa dimuat root bundle (pubspec '
      'assets)', (tester) async {
    final data = await rootBundle.load('assets/qris/qris_logo.png');
    expect(data.lengthInBytes, greaterThan(0));
  });
}
