import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/providers/theme_provider.dart';
import 'package:the_pos/features/setup/welcome_screen.dart';

/// Layar Welcome punya saklar tema ala GoPay di pojok kanan atas; mulai
/// pertama kali (belum ada pilihan tersimpan) = TERANG.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = GoRouter(routes: [
      GoRoute(path: '/setup', builder: (_, __) => const WelcomeScreen()),
    ], initialLocation: '/setup');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(brightness: Brightness.light),
          darkTheme: ThemeData(brightness: Brightness.dark),
          themeMode: ref.watch(themeModeProvider),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
      'default TERANG; saklar ada di pojok kanan atas & bisa ganti tema',
      (tester) async {
    final c = await pump(tester);
    expect(c.read(themeModeProvider), ThemeMode.light);

    final sw = find.byKey(const Key('welcome-theme'));
    expect(sw, findsOneWidget);
    final center = tester.getCenter(sw);
    expect(center.dx, greaterThan(360 * 0.8), reason: 'sisi kanan');
    expect(center.dy, lessThan(120), reason: 'sisi atas');
    expect(tester.takeException(), isNull, reason: 'tanpa overflow di 360 dp');

    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(c.read(themeModeProvider), ThemeMode.dark);
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(c.read(themeModeProvider), ThemeMode.light);
  });
}
