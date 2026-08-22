import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
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

  testWidgets(
      'logo QRIS: lebar hasil sesuai targetWidthDots yang diminta '
      '(kalau sudah kelipatan 8)', (tester) async {
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

  // Bug NYATA dilaporkan user: printer terhubung (lampu indikator nyala,
  // proses `connect()` berjalan) tapi kertas tidak pernah keluar sama
  // sekali. Akar masalah: `Generator._toRasterFormat` (esc_pos_utils_plus)
  // MELEDAK (`Unsupported operation: Cannot add to a fixed-length list`)
  // kalau lebar gambar BUKAN kelipatan 8 — dan lebar asli yg dihitung
  // `_buildBytes` (35% lebar kertas, sblmnya 55%: 384*0.35≈134 @58mm,
  // 576*0.35≈202 @80mm) TIDAK PERNAH kebetulan kelipatan 8, jadi SELALU
  // meledak begitu toggle "Tampilkan QR Pelunasan" aktif. Exception ini
  // terjadi DI DALAM `_buildBytes` (sebelum byte apa pun dikirim ke channel
  // native `write`), jadi printer tidak pernah menerima data struk sama
  // sekali.
  group('regresi: lebar logo HARUS kelipatan 8 (syarat Generator.imageRaster)',
      () {
    testWidgets(
        'lebar ganjil (mis. 134px, persis spt perhitungan 35% kertas 58mm) '
        'DIBULATKAN ke kelipatan 8 terdekat', (tester) async {
      final logo = await PrinterService.debugQrisLogo(134);
      expect(logo, isNotNull);
      expect(logo!.width % 8, 0,
          reason:
              'lebar HARUS kelipatan 8, kalau tidak Generator.imageRaster '
              'akan throw saat cetak sungguhan (lihat bug di bawah)');
    });

    // `test()` biasa, BUKAN `testWidgets` — `CapabilityProfile.load()`
    // (esc_pos_utils_plus, muat JSON profil printer via `rootBundle`)
    // TERBUKTI HANG TANPA BATAS kalau dipanggil dari dalam `testWidgets`
    // (terverifikasi manual: timeout 30 detik tercapai, padahal step
    // sebelum & sesudahnya sukses instan di `test()` biasa) — kombinasi
    // spesifik "sudah panggil `rootBundle.load` utk aset kita sendiri lalu
    // panggil `CapabilityProfile.load()` di dalam binding `testWidgets`"
    // yang bermasalah, bukan `rootBundle` itu sendiri (dipakai aman di tes
    // lain file ini). `rootBundle` KITA masih perlu binding asli, makanya
    // `TestWidgetsFlutterBinding.ensureInitialized()` tetap dipanggil di
    // atas (di luar testWidgets), cukup utk `test()` biasa.
    test(
        'logo hasil (lebar target sungguhan 58mm & 80mm) BISA dirasterisasi '
        'lewat Generator.imageRaster ASLI tanpa exception', () async {
      // Angka PERSIS sama dgn `_buildBytes`: paperDots * 0.35, dibulatkan.
      const width58 = 384 * 0.35; // ≈134 -> round -> 134
      const width80 = 576 * 0.35; // ≈202 -> round -> 202
      final logo58 = await PrinterService.debugQrisLogo(width58.round());
      final logo80 = await PrinterService.debugQrisLogo(width80.round());
      expect(logo58, isNotNull);
      expect(logo80, isNotNull);

      final profile = await CapabilityProfile.load();
      // Kalau bug-nya masih ada, baris2 di bawah ini akan throw
      // `Unsupported operation: Cannot add to a fixed-length list` --
      // itulah sebabnya test ini genuinely gagal saat fix di-revert
      // sementara (dibuktikan manual sebelum fix ini dikembalikan).
      expect(() => Generator(PaperSize.mm58, profile).imageRaster(logo58!),
          returnsNormally);
      expect(() => Generator(PaperSize.mm80, profile).imageRaster(logo80!),
          returnsNormally);
    });
  });
}
