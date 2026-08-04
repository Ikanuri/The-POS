import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/pengaturan/about_screen.dart';

/// Item 25c/28b susulan — "Info Lisensi & Serial" dipindah dari kartu
/// "Device Ini" (Pengaturan) ke sini (permintaan user), supaya info teknis
/// lisensi tidak numpuk di halaman utama Pengaturan.
Future<void> _pump(WidgetTester tester, {required LicenseState license}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        licenseProvider.overrideWith((ref) => LicenseNotifier()..state = license),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const AboutScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hero: wordmark "The POS", ikon besar, lalu tagline',
      (tester) async {
    await _pump(tester, license: const LicenseState(fingerprint: 'fp'));
    expect(find.text('The POS'), findsOneWidget);
    expect(find.textContaining('Aplikasi kasir offline-first'), findsOneWidget);

    // Ikon SENGAJA besar & dominan (mockup: 178px) — pernah salah dibuat
    // kecil (108px) sehingga wordmark yang mendominasi, bukan ikonnya.
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.width, 178);

    // Urutan mockup: wordmark DI ATAS ikon (bukan sebaliknya).
    expect(tester.getCenter(find.text('The POS')).dy,
        lessThan(tester.getCenter(find.byType(Image)).dy));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('footer: versi + kredit "made with ♥️ by Dre"', (tester) async {
    await _pump(tester, license: const LicenseState(fingerprint: 'fp'));
    expect(find.text('made with ♥️ by Dre'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('lisensi sudah aktif -> chip status lisensi tampil di kanan atas',
      (tester) async {
    await _pump(
      tester,
      license: LicenseState(
        fingerprint: 'fp',
        exp: DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      ),
    );
    expect(find.text('Lisensi'), findsOneWidget);
    expect(find.textContaining('hari lagi'), findsOneWidget);

    // Chip ada DI ATAS hero (posisi chip "ID device" di mockup).
    expect(tester.getCenter(find.text('Lisensi')).dy,
        lessThan(tester.getCenter(find.text('The POS')).dy));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('belum aktivasi -> chip lisensi TIDAK tampil', (tester) async {
    await _pump(tester, license: const LicenseState(fingerprint: 'fp'));
    expect(find.text('Lisensi'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
