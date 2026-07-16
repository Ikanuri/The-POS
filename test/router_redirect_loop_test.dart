import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/providers/license_provider.dart';
import 'package:the_pos/main.dart';

/// Bug dilaporkan user (testing device asli, "hapus data aplikasi/install
/// ulang"): `app_router.dart`'s `redirect()` bisa infinite loop
/// (`GoException: redirect loop detected /kasir => /aktivasi => /aktivasi
/// => /setup => /setup => /aktivasi`) kalau license LOCKED (belum aktivasi
/// lagi) DAN device belum configured SEKALIGUS — skenario realistis karena
/// keduanya sama-sama disimpan di SharedPreferences yang terhapus bareng.
///
/// Akar masalah: blok cek lisensi & blok cek device dieksekusi berurutan
/// tapi TIDAK saling eksklusif — begitu di-redirect ke /aktivasi krn
/// locked, blok device SETELAHNYA tetap sempat jalan & redirect lagi ke
/// /setup (device belum configured), lalu dari /setup balik lagi ke
/// /aktivasi krn masih locked — bolak-balik selamanya.
void main() {
  testWidgets(
      'license LOCKED + device belum configured SEKALIGUS → menetap di '
      'AktivasiScreen, TIDAK infinite redirect loop', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          licenseProvider.overrideWith(
            (ref) => LicenseNotifier()
              ..state = const LicenseState(fingerprint: 'fp-test'),
          ),
          deviceProvider.overrideWith((ref) => DeviceNotifier()),
        ],
        child: const ThePosApp(),
      ),
    );

    // Sebelum fix: pumpAndSettle akan melempar GoException (redirect loop)
    // atau timeout krn navigasi tidak pernah berhenti bolak-balik.
    await tester.pumpAndSettle();

    expect(find.text('Aktivasi Diperlukan'), findsOneWidget,
        reason: 'harus menetap di layar aktivasi, bukan Page Not Found');
    expect(find.textContaining('redirect loop'), findsNothing);
  });
}
