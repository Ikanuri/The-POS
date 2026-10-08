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
    // Tag rilis resmi hanya lewat jalur production.
    expect(wf, isNot(contains('flutter build apk --release --target-platform')));
  });
}
