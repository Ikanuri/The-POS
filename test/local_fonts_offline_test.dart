import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Item 9 (batch 15 Juli) — user tanya "apakah font by device (bundled) atau
/// fetch runtime?" Jawaban lama: TIDAK dibundel, `google_fonts` fetch dari
/// CDN saat runtime (gagal-diam ke font sistem kalau device offline &
/// belum pernah cache font itu sebelumnya — tampilan device baru jadi tidak
/// konsisten offline-first). Fix: semua berat font yang benar2 dipakai app
/// di-bundle sbg asset lokal + `GoogleFonts.config.allowRuntimeFetching =
/// false` (lihat main.dart) supaya SELALU pakai asset lokal.
///
/// PENTING kenapa test ini TIDAK pakai `testWidgets` + render beneran:
/// `flutter test` menjalankan `flutter_tester` dengan flag
/// `--disable-asset-fonts --use-test-fonts` SELALU aktif (bukan opsional) —
/// artinya widget test TIDAK PERNAH benar2 menguji resolusi asset font asli,
/// widget test yang "lolos" bisa jadi lolos semu (dibuktikan manual: test
/// tetap hijau walau file font sengaja dihapus, sampai ditelusuri ke akar
/// masalah ini). Test paling andal & langsung: cek keberadaan file di disk
/// sesuai konvensi PERSIS yang dipakai `google_fonts` package utk mencocokkan
/// asset (`google_fonts_variant.dart`: "<FamilyInternal>-<NamaBerat>.ttf"),
/// utk SETIAP kombinasi (family, berat) yang benar2 dipakai app.
void main() {
  const fontsDir = 'assets/fonts';

  const weightNames = {
    100: 'Thin',
    200: 'ExtraLight',
    300: 'Light',
    400: 'Regular',
    500: 'Medium',
    600: 'SemiBold',
    700: 'Bold',
    800: 'ExtraBold',
    900: 'Black',
  };

  void expectWeightsExist(String family, List<int> weights) {
    for (final w in weights) {
      final path = '$fontsDir/$family-${weightNames[w]}.ttf';
      expect(File(path).existsSync(), isTrue,
          reason: '$path harus ada — dipakai GoogleFonts.$family via '
              'weight $w, kalau hilang app CRASH saat runtime karena '
              'allowRuntimeFetching=false (lihat main.dart)');
    }
  }

  test('Hanken Grotesk — semua berat 100-900 ter-bundle (dipakai '
      'hankenGroteskTextTheme utk SELURUH TextTheme default + override '
      'w500/w600/w700 eksplisit)', () {
    expectWeightsExist(
        'HankenGrotesk', [100, 200, 300, 400, 500, 600, 700, 800, 900]);
  });

  test('Newsreader — semua berat 200-800 ter-bundle (dipakai AppTheme.'
      'numStyle, weight default w600 + override w700)', () {
    expectWeightsExist('Newsreader', [200, 300, 400, 500, 600, 700, 800]);
  });

  test('Roboto Mono — semua berat 100-700 ter-bundle (dipakai struk teks '
      'monospace di receipt_screen.dart/merged_receipt_screen.dart)', () {
    expectWeightsExist('RobotoMono', [100, 200, 300, 400, 500, 600, 700]);
  });

  test('lisensi OFL.txt ikut dibundel (wajib — semua font di sini OFL)', () {
    expect(File('$fontsDir/OFL.txt').existsSync(), isTrue);
  });
}
