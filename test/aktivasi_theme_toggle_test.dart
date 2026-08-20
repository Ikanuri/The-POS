import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/providers/theme_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/aktivasi/aktivasi_screen.dart';

/// Permintaan user: layar gerbang aktivasi (serial key) perlu toggle
/// terang/gelap sendiri — layar ini muncul SEBELUM `/setup` & sebelum DB
/// bisa dibuka, jadi layar Pengaturan (tempat mode gelap biasanya diatur)
/// belum bisa dijangkau sama sekali. `themeMode` disimpan di
/// SharedPreferences, bukan tabel settings DB, jadi aman dipakai di sini.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpAktivasi(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ref.watch(themeModeProvider),
            home: const AktivasiScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ada tombol toggle tema, ikonnya menyebut TUJUAN bukan keadaan',
      (tester) async {
    await pumpAktivasi(tester);

    // Awal terang -> ikon bulan (tujuan: gelap).
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();

    // Sudah gelap -> ikon berubah jadi matahari (tujuan: terang).
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_outlined), findsNothing);
  });

  testWidgets('tap toggle benar-benar mengubah tema layar jadi gelap',
      (tester) async {
    await pumpAktivasi(tester);
    final ctx = tester.element(find.byType(AktivasiScreen));
    expect(Theme.of(ctx).brightness, Brightness.light);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();

    final ctx2 = tester.element(find.byType(AktivasiScreen));
    expect(Theme.of(ctx2).brightness, Brightness.dark);
  });

  testWidgets(
      'ganti tema selagi QR fingerprint terlihat TIDAK melempar assert '
      'framework (bug qr_flutter, baru terjangkau sejak toggle ini ada)',
      (tester) async {
    await pumpAktivasi(tester);
    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: "QrImageView dicat dgn ukuran layout lama -> assert "
            "'debugSize == size'; dicegah dgn key yang ikut brightness");
  });

  testWidgets('pilihan mode TERSIMPAN di SharedPreferences', (tester) async {
    await pumpAktivasi(tester);
    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), ThemeMode.dark.name,
        reason: 'mode harus bertahan setelah app dibuka ulang');
  });
}
