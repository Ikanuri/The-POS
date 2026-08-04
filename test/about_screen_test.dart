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
  testWidgets('menampilkan wordmark "The POS" dan ikon aplikasi',
      (tester) async {
    await _pump(tester, license: const LicenseState(fingerprint: 'fp'));
    expect(find.text('The POS'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'lisensi sudah aktif -> kartu "Info Lisensi & Serial" tampil',
      (tester) async {
    await _pump(
      tester,
      license: LicenseState(
        fingerprint: 'fp',
        exp: DateTime.now().add(const Duration(days: 10)).toIso8601String(),
      ),
    );
    expect(find.text('Info Lisensi & Serial'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'belum aktivasi -> kartu "Info Lisensi & Serial" TIDAK tampil',
      (tester) async {
    await _pump(tester, license: const LicenseState(fingerprint: 'fp'));
    expect(find.text('Info Lisensi & Serial'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
