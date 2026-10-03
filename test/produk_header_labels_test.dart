import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/widgets/labeled_tool_button.dart';
import 'package:the_pos/features/produk/cek_stok_screen.dart';
import 'package:the_pos/features/produk/produk_list_screen.dart';

import 'helpers/pump_app.dart';

/// Item 92 (usulan user) — tombol header tab Produk & sub-fiturnya diberi
/// label nama fungsi (pola toolbar Kasir), bukan cuma ikon + tooltip.
/// "Tambah Produk" tetap ikon "+". Diuji di lebar HP sempit (360).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  String labelOf(WidgetTester tester, String tooltip) => tester
      .widget<LabeledToolButton>(find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(LabeledToolButton)))
      .label!;

  testWidgets('tab Produk: 5 tombol berlabel, "+" tetap ikon, tanpa overflow '
      'di 360', (tester) async {
    await pumpWithFakeApp(tester,
        db: db,
        child: const ProdukListScreen(),
        surfaceSize: const Size(360, 800));
    await tester.pumpAndSettle();
    for (final name in [
      'Cek Stok',
      'Sinkron Harga',
      'Kelola Kategori',
      'Kategori Harga',
      'Katalog',
    ]) {
      expect(find.text(name), findsOneWidget,
          reason: 'label "$name" harus terlihat (bukan cuma tooltip)');
      expect(labelOf(tester, name), name);
    }
    expect(find.byTooltip('Tambah Produk'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.byTooltip('Tambah Produk'),
            matching: find.byType(LabeledToolButton)),
        findsNothing,
        reason: 'Tambah Produk tetap ikon "+" tanpa label');
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets('Cek Stok: tombol header berlabel', (tester) async {
    await pumpWithFakeApp(tester,
        db: db,
        child: const CekStokScreen(),
        surfaceSize: const Size(360, 800));
    await tester.pumpAndSettle();
    expect(find.text('Penerimaan Barang'), findsOneWidget);
    expect(find.text('Stock Opname'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await drain(tester);
  });
}
