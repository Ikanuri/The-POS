import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/features/setup/welcome_screen.dart';

/// Item 28 — tombol ke-3 "Pulihkan dari File" di welcome screen (selain
/// "Setup Toko Baru"/"Gabung Toko"), supaya restore langsung tanpa perlu
/// bikin toko dummy dulu.
void main() {
  testWidgets('tombol "Pulihkan dari File" tampil & navigasi ke /setup/pulihkan',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/setup', builder: (_, __) => const WelcomeScreen()),
      GoRoute(
        path: '/setup/pulihkan',
        builder: (_, __) => const Scaffold(body: Text('Halaman Pulihkan')),
      ),
    ], initialLocation: '/setup');

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('Pulihkan dari File'), findsOneWidget);
    await tester.tap(find.text('Pulihkan dari File'));
    await tester.pumpAndSettle();

    expect(find.text('Halaman Pulihkan'), findsOneWidget);
  });
}
