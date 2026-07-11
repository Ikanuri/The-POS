import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/inline_banner.dart';

/// Warna teks label chip yang BENAR-BENAR ter-render (setelah resolusi
/// WidgetStateColor oleh RawChip), dibaca dari RichText final.
Color _chipLabelColor(WidgetTester tester) {
  final rt = tester.widget<RichText>(find.descendant(
    of: find.byType(ChoiceChip),
    matching: find.byType(RichText),
  ));
  return (rt.text as TextSpan).style!.color!;
}

void main() {
  // AppTheme.light()/dark() memanggil google_fonts yang butuh binding aktif —
  // jangan panggil di badan main() (fase collection). Bangun theme DI DALAM
  // tiap test setelah binding siap.
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final isDark in [false, true]) {
    final mode = isDark ? 'dark' : 'light';
    ThemeData theme() => isDark ? AppTheme.dark() : AppTheme.light();

    // ── Item 22 Bagian B — bug sistemik chip terpilih buram ──────────────
    testWidgets(
        'chip TERPILIH pakai onPrimaryContainer (kontras di atas '
        'primaryContainer), bukan warna muted — $mode', (tester) async {
      final t = theme();
      await tester.pumpWidget(MaterialApp(
        theme: t,
        home: Scaffold(
          body: ChoiceChip(
            label: const Text('Tunai'),
            selected: true,
            selectedColor: t.colorScheme.primaryContainer,
            onSelected: (_) {},
          ),
        ),
      ));
      expect(_chipLabelColor(tester), t.colorScheme.onPrimaryContainer);
    });

    testWidgets('chip TIDAK terpilih tetap warna muted (bukan '
        'onPrimaryContainer) — $mode', (tester) async {
      final t = theme();
      await tester.pumpWidget(MaterialApp(
        theme: t,
        home: Scaffold(
          body: ChoiceChip(
            label: const Text('Tunai'),
            selected: false,
            selectedColor: t.colorScheme.primaryContainer,
            onSelected: (_) {},
          ),
        ),
      ));
      expect(_chipLabelColor(tester),
          isNot(t.colorScheme.onPrimaryContainer));
    });

    // ── Item 22 Bagian A — banner sukses hijau / gagal merah ─────────────
    testWidgets('banner SUKSES pakai warna hijau semantik (changeFg) — $mode',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme(),
        home: Scaffold(
          body: InlineBanner(
            message: 'Tersimpan',
            type: InlineBannerType.success,
            onDismiss: () {},
          ),
        ),
      ));
      await tester.pump();
      final icon =
          tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded));
      expect(icon.color, AppTheme.changeFg(isDark));
      await tester.pump(const Duration(seconds: 5)); // drain auto-dismiss timer
    });

    testWidgets('banner GAGAL pakai warna merah semantik (debtFg) — $mode',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme(),
        home: Scaffold(
          body: InlineBanner(
            message: 'Gagal simpan',
            type: InlineBannerType.error,
            onDismiss: () {},
          ),
        ),
      ));
      await tester.pump();
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_rounded));
      expect(icon.color, AppTheme.debtFg(isDark));
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
