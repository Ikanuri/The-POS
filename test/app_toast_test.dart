import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_overlays.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/app_toast.dart';

/// Toast gaya baru: kartu di ATAS layar, dirender [AppToastHost].
void main() {
  Future<void> pumpApp(WidgetTester tester,
      {bool host = true,
      bool reduced = false,
      double textScale = 1,
      Widget? body}) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      builder: (c, child) {
        // Meniru main.dart: MediaQuery di luar, host di dalamnya.
        return MediaQuery(
          data: MediaQuery.of(c).copyWith(
            disableAnimations: reduced,
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 30),
          ),
          child: host ? AppToastHost(child: child!) : child!,
        );
      },
      home: Scaffold(
        body: body ??
            Builder(
              builder: (c) => Center(
                child: ElevatedButton(
                  onPressed: () => ScaffoldMessenger.of(c).showAppSnackBar(
                      const SnackBar(content: Text('Dari snackbar'))),
                  child: const Text('tombol'),
                ),
              ),
            ),
      ),
    ));
  }

  // Satu frame agar ticker mulai, lalu lewati animasi masuk/keluar.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // Habiskan timer & animasi.
  Future<void> drain(WidgetTester tester) async {
    AppToast.hide();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('toast muncul di ATAS (di bawah status bar) & memuat teks',
      (tester) async {
    await pumpApp(tester);
    AppToast.show(message: 'Tersimpan');
    await tester.pump();
    await settle(tester);
    expect(find.text('Tersimpan'), findsOneWidget);
    final r = tester.getRect(find.byKey(const Key('app_toast')));
    expect(r.top, greaterThanOrEqualTo(30)); // di bawah status bar
    expect(r.center.dy, lessThan(800 / 2));
    expect(r.width, lessThanOrEqualTo(360));
    await drain(tester);
  });

  testWidgets('warna ikon sesuai tone', (tester) async {
    await pumpApp(tester);
    final cases = {
      ToastTone.success: (Icons.check_circle_rounded, AppTheme.changeFg(false)),
      ToastTone.error: (Icons.error_rounded, AppTheme.debtFg(false)),
      ToastTone.info: (Icons.info_rounded, AppTheme.accent),
      ToastTone.sync: (Icons.sync_rounded, AppTheme.riwayatFg(false)),
    };
    for (final e in cases.entries) {
      AppToast.show(message: 'x ${e.key}', tone: e.key);
      await tester.pump();
      await settle(tester);
      final icon = tester.widget<Icon>(find.byIcon(e.value.$1));
      expect(icon.color, e.value.$2, reason: '${e.key}');
    }
    await drain(tester);
  });

  testWidgets('toast kedua menggantikan yang pertama', (tester) async {
    await pumpApp(tester);
    AppToast.show(message: 'Satu');
    await settle(tester);
    AppToast.show(message: 'Dua');
    await settle(tester);
    expect(find.text('Satu'), findsNothing);
    expect(find.text('Dua'), findsOneWidget);
    expect(find.byKey(const Key('app_toast')), findsOneWidget);
    await drain(tester);
  });

  testWidgets('auto-hilang setelah durasi (3 dtk; 5 dtk bila ada aksi)',
      (tester) async {
    await pumpApp(tester);
    AppToast.show(message: 'Sebentar');
    await settle(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Sebentar'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('Sebentar'), findsNothing);

    AppToast.show(message: 'Beraksi', actionLabel: 'Urungkan', onAction: () {});
    await settle(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Beraksi'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('Beraksi'), findsNothing);
    await drain(tester);
  });

  testWidgets('aksi memanggil callback dan menutup toast', (tester) async {
    await pumpApp(tester);
    var called = 0;
    AppToast.show(
        message: 'Dihapus', actionLabel: 'Urungkan', onAction: () => called++);
    await settle(tester);
    await tester.tap(find.text('Urungkan'));
    await tester.pump();
    await settle(tester);
    expect(called, 1);
    expect(find.text('Dihapus'), findsNothing);
    await drain(tester);
  });

  testWidgets('geser ke atas menutup toast', (tester) async {
    await pumpApp(tester);
    AppToast.show(message: 'Geser aku');
    await settle(tester);
    await tester.drag(find.text('Geser aku'), const Offset(0, -60));
    await tester.pump();
    await settle(tester);
    expect(find.text('Geser aku'), findsNothing);
    await drain(tester);
  });

  testWidgets('reduced motion: langsung di posisi akhir, tanpa animasi',
      (tester) async {
    await pumpApp(tester, reduced: true);
    AppToast.show(message: 'Instan');
    await tester.pump();
    await tester.pump();
    final fade = tester.widget<FadeTransition>(find
        .ancestor(
            of: find.byKey(const Key('app_toast')),
            matching: find.byType(FadeTransition))
        .first);
    expect(fade.opacity.value, 1.0);
    await drain(tester);
  });

  testWidgets('animasi normal: awalnya di atas posisi akhir lalu mendarat',
      (tester) async {
    await pumpApp(tester);
    AppToast.show(message: 'Turun');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final yEarly = tester.getTopLeft(find.byKey(const Key('app_toast'))).dy;
    await settle(tester);
    final yFinal = tester.getTopLeft(find.byKey(const Key('app_toast'))).dy;
    expect(yEarly, lessThan(yFinal));
    await drain(tester);
  });

  testWidgets('TANPA host -> jatuh ke SnackBar bawaan', (tester) async {
    await pumpApp(tester, host: false);
    expect(AppToast.hostMounted, isFalse);
    await tester.tap(find.text('tombol'));
    await tester.pump();
    await settle(tester);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Dari snackbar'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('showAppSnackBar dgn host -> toast di host, bukan SnackBar',
      (tester) async {
    await pumpApp(tester);
    expect(AppToast.hostMounted, isTrue);
    await tester.tap(find.text('tombol'));
    await tester.pump();
    await settle(tester);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('app_toast')), findsOneWidget);
    expect(find.text('Dari snackbar'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('app_toast'))).dy,
        lessThan(400));
    await drain(tester);
  });

  testWidgets('terjemahan SnackBar: error + aksi + Row berisi Text',
      (tester) async {
    late BuildContext ctx;
    var undone = 0;
    await pumpApp(tester,
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }));
    ScaffoldMessenger.of(ctx).showAppSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.info),
        Expanded(child: Text('Gagal menyimpan')),
      ]),
      backgroundColor: Theme.of(ctx).colorScheme.error,
      action: SnackBarAction(label: 'Coba lagi', onPressed: () => undone++),
    ));
    await tester.pump();
    await settle(tester);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Gagal menyimpan'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_rounded));
    expect(icon.color, AppTheme.debtFg(false));
    await tester.tap(find.text('Coba lagi'));
    await tester.pump();
    expect(undone, 1);
    await drain(tester);
  });

  testWidgets('360dp + font besar + teks panjang: maks 3 baris, tanpa overflow',
      (tester) async {
    await pumpApp(tester, textScale: 2);
    AppToast.show(
        message: List.filled(40, 'kalimat panjang sekali').join(' '),
        actionLabel: 'Urungkan');
    await settle(tester);
    expect(tester.takeException(), isNull);
    final t = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('app_toast')),
        matching: find.byType(Text)).first);
    expect(t.maxLines, 3);
    expect(tester.getRect(find.byKey(const Key('app_toast'))).right,
        lessThanOrEqualTo(360));
    await drain(tester);
  });
}
