import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/app_empty_state.dart';

void main() {
  testWidgets('AppEmptyState: pesan + saran tampil di lebar 360, skala 2x',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: const Scaffold(
          body: AppEmptyState('Belum ada data', hint: 'Tambah dulu ya')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada data'), findsOneWidget);
    expect(find.text('Tambah dulu ya'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
