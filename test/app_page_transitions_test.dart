import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/theme/app_page_transitions.dart';
import 'package:the_pos/core/theme/app_theme.dart';

/// Transisi halaman ala Telegram: sub-halaman = fade + geser 48 px dari kanan;
/// halaman akar/tab (path berawalan "/") = fade silang + sedikit skala.
void main() {
  GoRouter makeRouter() => GoRouter(
        initialLocation: '/a',
        routes: [
          GoRoute(
            path: '/a',
            builder: (_, __) => const Scaffold(body: Center(child: Text('A'))),
            routes: [
              GoRoute(
                path: 'c',
                builder: (_, __) =>
                    const Scaffold(body: Center(child: Text('C'))),
              ),
            ],
          ),
          GoRoute(
            path: '/b',
            builder: (_, __) => const Scaffold(body: Center(child: Text('B'))),
          ),
        ],
      );

  Future<GoRouter> pump(WidgetTester tester,
      {bool reduced = false, ThemeData? theme}) async {
    final router = makeRouter();
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      theme: theme ?? AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  double opacityOf(WidgetTester tester, String text) {
    final f = find.ancestor(
        of: find.text(text), matching: find.byType(FadeTransition));
    return tester.widget<FadeTransition>(f.first).opacity.value;
  }

  testWidgets('tema memasang builder kustom di Android, Cupertino di iOS',
      (tester) async {
    final b = AppTheme.light().pageTransitionsTheme.builders;
    expect(b[TargetPlatform.android], isA<AppPageTransitionsBuilder>());
    expect(b[TargetPlatform.iOS], isNot(isA<AppPageTransitionsBuilder>()));
    expect(AppTheme.dark().pageTransitionsTheme.builders[TargetPlatform.android],
        isA<AppPageTransitionsBuilder>());
  });

  testWidgets('push sub-halaman: memudar masuk + bergeser dari kanan, lalu '
      'mendarat di posisi akhir', (tester) async {
    final router = await pump(tester);
    final finalX = tester.getCenter(find.text('A')).dx;

    router.go('/a/c');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final op = opacityOf(tester, 'C');
    expect(op, greaterThan(0));
    expect(op, lessThan(1));
    final midX = tester.getCenter(find.text('C')).dx;
    expect(midX, greaterThan(finalX));
    expect(midX - finalX, lessThanOrEqualTo(AppPageTransitionsBuilder.slideDistance));

    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'C'), 1);
    expect(tester.getCenter(find.text('C')).dx, finalX);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pop: halaman yang ditinggalkan memudar + menjauh ke kanan',
      (tester) async {
    final router = await pump(tester);
    router.go('/a/c');
    await tester.pumpAndSettle();
    final finalX = tester.getCenter(find.text('C')).dx;

    router.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester, 'C'), lessThan(1));
    expect(tester.getCenter(find.text('C')).dx, greaterThan(finalX));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('pindah halaman akar/tab: fade + skala, TANPA geser',
      (tester) async {
    final router = await pump(tester);
    final finalX = tester.getCenter(find.text('A')).dx;

    router.go('/b');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester, 'B'), lessThan(1));
    expect(tester.getCenter(find.text('B')).dx, closeTo(finalX, 0.01));
    final scale = tester
        .widget<ScaleTransition>(find
            .ancestor(of: find.text('B'), matching: find.byType(ScaleTransition))
            .first)
        .scale
        .value;
    expect(scale, lessThan(1));
    expect(scale, greaterThanOrEqualTo(0.985));

    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'B'), 1);
  });

  testWidgets('animasi dimatikan di sistem: tidak ada fade/geser sama sekali',
      (tester) async {
    final router = await pump(tester, reduced: true);
    final finalX = tester.getCenter(find.text('A')).dx;
    router.go('/a/c');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.getCenter(find.text('C')).dx, finalX);
    final fades = find.ancestor(
        of: find.text('C'), matching: find.byType(FadeTransition));
    for (final w in tester.widgetList<FadeTransition>(fades)) {
      expect(w.opacity.value, 1);
    }
    await tester.pumpAndSettle();
  });
}
