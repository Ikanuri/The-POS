import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Jaga jalur build production vs beta (CLAUDE.md "Jalur Build"): beta
/// berdampingan dgn produksi (ID beda) dan CI memilih flavor dgn benar.
void main() {
  final gradle = File('android/app/build.gradle').readAsStringSync();
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final wf = File('.github/workflows/build-apk.yml').readAsStringSync();

  test('flavor production memakai ID & nama asli, beta berakhiran .beta', () {
    expect(gradle, contains('applicationId = "com.thepos.the_pos"'));
    expect(gradle, contains('flavorDimensions = ["track"]'));
    final prod = RegExp(r'production \{[^}]*\}').firstMatch(gradle)!.group(0)!;
    expect(prod, isNot(contains('applicationIdSuffix')));
    expect(prod, contains('appName: "The POS"'));
    final beta = RegExp(r'beta \{[^}]*\}').firstMatch(gradle)!.group(0)!;
    expect(beta, contains('applicationIdSuffix = ".beta"'));
    expect(beta, contains('appName: "The POS Beta"'));
    expect(manifest, contains(r'android:label="${appName}"'));
  });

  test('CI: main/tag -> production, branch lain -> beta, build pakai --flavor',
      () {
    expect(wf, contains('refs/tags/*'));
    expect(wf, contains('"refs/heads/main"'));
    expect(wf, contains('CHOICE=production'));
    expect(wf, contains('CHOICE=beta'));
    expect(wf, contains('flutter build apk --release --flavor "\$FLAVOR"'));
    expect(wf, contains('app-\${FLAVOR}-release.apk'));
    expect(wf, contains('options: [auto, production, beta]'));
    // `main-beta` (branch beta tetap, tanpa awalan claude/) ikut memicu build.
    expect(wf, contains("branches: [main, main-beta, 'claude/**']"));
    // Tag rilis resmi hanya lewat jalur production.
    expect(wf, isNot(contains('flutter build apk --release --target-platform')));
  });

  test('ikon beta ada di semua densitas, berbeda dari ikon produksi', () {
    const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
    sizes.forEach((density, px) {
      final beta = File('android/app/src/beta/res/mipmap-$density/ic_launcher.png');
      final prod = File('android/app/src/main/res/mipmap-$density/ic_launcher.png');
      expect(beta.existsSync(), isTrue, reason: density);
      final b = beta.readAsBytesSync();
      // PNG: lebar & tinggi di header IHDR (byte 16..23).
      int be32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      expect(be32(16), px, reason: 'lebar $density');
      expect(be32(20), px, reason: 'tinggi $density');
      expect(b, isNot(equals(prod.readAsBytesSync())), reason: density);
    });
    // Ikon produksi tidak disentuh: tidak ada override di flavor production.
    expect(Directory('android/app/src/production').existsSync(), isFalse);
  });
}
