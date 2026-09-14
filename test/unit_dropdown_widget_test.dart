import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/unit_dropdown.dart';

/// Bug dilaporkan user (3 screenshot): dropdown pilih satuan bawaan
/// Flutter (`DropdownButton`/`DropdownButtonFormField`/`PopupMenuButton`
/// TANPA `constraints`) menutupi hampir SELURUH layar begitu daftar
/// satuannya panjang (`unit_types` toko real bisa 15-25 entri) — menimpa
/// AppBar, tombol Simpan, & baris produk lain di bawahnya.
///
/// `UnitDropdown` (widget baru, dipakai di Cek Stok/Hitung Fisik Opname/
/// edit produk) HARUS membatasi tinggi menunya, apa pun jumlah entrinya.
void main() {
  Map<int, String> manyEntries() => {
        for (var i = 0; i < 25; i++) i: 'Satuan $i',
      };

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
      );

  testWidgets(
      'menu TIDAK PERNAH melebihi maxHeight yg dibatasi, walau entrinya '
      '25 (skenario nyata unit_types toko)', (tester) async {
    await pump(
      tester,
      UnitDropdown<int>(
        entries: manyEntries(),
        selectedKey: 0,
        onSelected: (_) {},
      ),
    );

    await tester.tap(find.byType(UnitDropdown<int>));
    await tester.pumpAndSettle();

    final menu = tester.widget<PopupMenuButton<int>>(
        find.byType(PopupMenuButton<int>));
    expect(menu.constraints?.maxHeight, isNotNull,
        reason: 'tanpa maxHeight, menu 25 entri akan tumbuh nyaris '
            'seluruh tinggi layar (screenshot user) -- HARUS dibatasi');
    expect(menu.constraints!.maxHeight, lessThan(600),
        reason: 'dibatasi jauh di bawah tinggi layar HP biasa (~800px), '
            'sisanya scroll internal, bukan menimpa AppBar/konten lain');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('memilih entry lewat menu memanggil onSelected dgn key yg benar',
      (tester) async {
    int? picked;
    await pump(
      tester,
      UnitDropdown<int>(
        entries: const {1: 'Pcs', 2: 'Dus'},
        selectedKey: 1,
        onSelected: (v) => picked = v,
      ),
    );

    await tester.tap(find.byType(UnitDropdown<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dus'));
    await tester.pumpAndSettle();

    expect(picked, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('gaya field (formLabel diisi) tampil sbg InputDecorator '
      'berlabel, BUKAN DropdownButtonFormField bawaan Flutter',
      (tester) async {
    await pump(
      tester,
      UnitDropdown<int>(
        entries: const {1: 'Pcs', 2: 'Dus'},
        selectedKey: 1,
        formLabel: 'Jenis Satuan',
        onSelected: (_) {},
      ),
    );

    expect(find.text('Jenis Satuan'), findsOneWidget);
    expect(find.byType(InputDecorator), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing,
        reason: 'permintaan user: bukan template dropdown bawaan Flutter');
    expect(find.byType(DropdownButton<int>), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('enabled=false -> tidak bisa dibuka sama sekali (mode readOnly)',
      (tester) async {
    var tapped = false;
    await pump(
      tester,
      UnitDropdown<int>(
        entries: const {1: 'Pcs'},
        selectedKey: 1,
        enabled: false,
        onSelected: (_) => tapped = true,
      ),
    );

    expect(find.byType(PopupMenuButton<int>), findsNothing,
        reason: 'saat disabled, tidak boleh ada PopupMenuButton yg bisa '
            'ditekan sama sekali');
    expect(find.text('Pcs'), findsOneWidget,
        reason: 'nilai terpilih tetap tampil apa adanya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    expect(tapped, isFalse);
  });

  testWidgets(
      'baris menu terpilih ditandai (radio terisi + tint aksen), bukan '
      'baris polos tanpa penanda', (tester) async {
    await pump(
      tester,
      UnitDropdown<int>(
        entries: const {1: 'Pcs', 2: 'Dus'},
        selectedKey: 2,
        onSelected: (_) {},
      ),
    );

    await tester.tap(find.byType(UnitDropdown<int>));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
