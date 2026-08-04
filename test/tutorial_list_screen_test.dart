import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/pengaturan/tutorial_list_screen.dart';

/// Item 28b — panduan/tutorial searchable, dgn Pro Tips (fitur "tersembunyi"
/// spt paste-pesanan-merge-ke-cart-aktif, bukan cuma satu contoh itu saja).
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: TutorialListScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('menampilkan beberapa bab panduan secara default', (tester) async {
    await pump(tester);
    expect(find.text('Keranjang & Tempel Pesanan'), findsOneWidget);
    expect(find.text('Laci Meja — Titip, Ketinggalan, Pinjaman, Pre-order'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('cari keyword menyaring bab yang tidak cocok', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'izin pegawai');
    await tester.pumpAndSettle();

    expect(find.text('Izin Pegawai/Asisten'), findsOneWidget);
    expect(find.text('Keranjang & Tempel Pesanan'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('bab yang di-expand menampilkan isi Pro Tip', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Keranjang & Tempel Pesanan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tempel Pesanan'), findsWidgets);
    expect(find.byIcon(Icons.lightbulb_outline), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
