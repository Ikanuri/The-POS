import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/aktivasi/aktivasi_screen.dart';

/// AktivasiScreen dipakai SEBELUM device/DB tersedia (gerbang pra-setup) —
/// tidak butuh `pumpWithFakeApp` (yang fokus fake databaseProvider/
/// deviceProvider), cukup override licenseProvider langsung dgn state tetap.
Future<void> _pump(WidgetTester tester, {String fingerprint = 'aabbccdd11223344aabbccdd11223344'}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        licenseProvider.overrideWith(
          (ref) => LicenseNotifier()..state = LicenseState(fingerprint: fingerprint),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const AktivasiScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menampilkan sidik jari yang diformat berkelompok', (tester) async {
    await _pump(tester, fingerprint: 'aabbccdd11223344aabbccdd11223344');
    expect(find.text('AABB-CCDD-1122-3344-AABB-CCDD-1122-3344'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('kode aktivasi tidak valid menampilkan pesan error, bukan crash',
      (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'kode-ngasal-tidak-valid');
    await tester.tap(find.widgetWithText(FilledButton, 'Aktifkan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kode tidak dikenali'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('mengetik ulang di field kode menghapus pesan error lama',
      (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'kode-ngasal-tidak-valid');
    await tester.tap(find.widgetWithText(FilledButton, 'Aktifkan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kode tidak dikenali'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ketik ulang lagi');
    await tester.pump();
    expect(find.textContaining('Kode tidak dikenali'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
