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

  testWidgets(
      'regresi: tidak ada garis divider bawaan ExpansionTile saat expanded',
      (tester) async {
    await pump(tester);
    final tiles = tester.widgetList<ExpansionTile>(find.byType(ExpansionTile));
    for (final t in tiles) {
      expect(t.shape, isA<Border>().having((b) => b.top.width, 'top width', 0));
      expect(t.collapsedShape,
          isA<Border>().having((b) => b.top.width, 'top width', 0));
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('bab baru (printer, backup, loyalitas, retur, tutup, katalog) ada',
      (tester) async {
    await pump(tester);
    for (final title in [
      'Printer Bluetooth',
      'Backup & Restore, Alihkan Owner',
      'Poin Loyalitas Pelanggan',
      'Retur & Edit Transaksi Lunas',
      'Tutup Kasir vs Tutup Buku',
      'Katalog Pesanan (pelanggan pesan sendiri)',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'bab "$title" hilang');
    }

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
