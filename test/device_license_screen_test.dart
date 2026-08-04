import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/pengaturan/device_license_screen.dart';

/// Regresi: layar ini sempat memakai `DateFormat('d MMMM yyyy', 'id_ID')`.
/// App ini TIDAK PERNAH memanggil `initializeDateFormatting` (lihat catatan
/// di `expenses_screen.dart`), jadi konstruktor `DateFormat` ber-locale itu
/// throw `LocaleDataException` saat build — SELURUH layar gagal render
/// (layar merah), bukan cuma tanggalnya yang salah format. Nama bulan
/// sekarang dibentuk manual.
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
        home: const DeviceLicenseScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('render tanpa LocaleDataException, tanggal pakai bulan Indonesia',
      (tester) async {
    await _pump(
      tester,
      license: LicenseState(
        fingerprint: '9f3a1b2277ce804aa1f09c3e5b7d2e41',
        exp: DateTime(2026, 11, 2).toIso8601String(),
        activatedAt: DateTime(2026, 7, 12),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('12 Juli 2026'), findsOneWidget);
    expect(find.text('2 November 2026'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('nomor serial tampil berkelompok + QR-nya', (tester) async {
    await _pump(
      tester,
      license: const LicenseState(
        fingerprint: '9f3a1b2277ce804aa1f09c3e5b7d2e41',
        exp: 'selamanya',
      ),
    );

    expect(find.text('9F3A-1B22-77CE-804A-A1F0-9C3E-5B7D-2E41'), findsOneWidget);
    expect(find.text('Selamanya'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('nomor serial disamarkan (spoiler) sampai diketuk', (tester) async {
    await _pump(
      tester,
      license: const LicenseState(
        fingerprint: '9f3a1b2277ce804aa1f09c3e5b7d2e41',
        exp: 'selamanya',
      ),
    );

    expect(find.text('Ketuk untuk lihat nomor serial'), findsOneWidget);
    expect(find.text('Ketuk untuk sembunyikan lagi'), findsNothing);

    await tester.tap(find.byKey(const Key('serial-spoiler-tap')));
    await tester.pump();

    expect(find.text('Ketuk untuk sembunyikan lagi'), findsOneWidget);
    expect(find.text('Ketuk untuk lihat nomor serial'), findsNothing);

    await tester.tap(find.byKey(const Key('serial-spoiler-tap')));
    await tester.pump();
    expect(find.text('Ketuk untuk lihat nomor serial'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tidak ada lagi seksi "Segera Hadir" (dihapus atas permintaan user)',
      (tester) async {
    await _pump(
      tester,
      license: const LicenseState(
        fingerprint: '9f3a1b2277ce804aa1f09c3e5b7d2e41',
        exp: 'selamanya',
      ),
    );

    expect(find.textContaining('Segera Hadir'), findsNothing);
    expect(find.textContaining('Perpanjang via scan'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
