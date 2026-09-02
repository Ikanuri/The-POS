import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/laci_meja/product_picker_dropdown.dart';

/// Susulan (permintaan user, screenshot layout sempit) — `ProductPickerDropdown`
/// diekstrak jadi widget reusable (dipakai ULANG di pemilih jaminan &
/// filter produk, dashboard maupun Riwayat). Widget test MURNI, terpisah
/// dari layar penggunanya.
void main() {
  Widget buildHarness({
    required Map<String, ({String name, String? badge})> entries,
    required String? selectedId,
    required ValueChanged<String?> onSelected,
    String? allLabel,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ProductPickerDropdown(
          entries: entries,
          selectedId: selectedId,
          onSelected: onSelected,
          allLabel: allLabel,
        ),
      ),
    );
  }

  testWidgets('entries kosong -> tidak render apa pun', (tester) async {
    await tester.pumpWidget(buildHarness(
      entries: const {},
      selectedId: null,
      onSelected: (_) {},
    ));
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets(
      'cuma 1 entry TANPA allLabel -> chip tampilan saja, TIDAK ada '
      'PopupMenuButton (tidak ada apa pun utk dipilih)', (tester) async {
    await tester.pumpWidget(buildHarness(
      entries: const {'p1': (name: 'LPG', badge: '5 jaminan')},
      selectedId: 'p1',
      onSelected: (_) {},
    ));

    expect(find.text('LPG'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets(
      'cuma 1 entry TAPI allLabel diisi -> TETAP jadi dropdown (opsi '
      '"Semua" membuatnya layak dipilih)', (tester) async {
    await tester.pumpWidget(buildHarness(
      entries: const {'p1': (name: 'LPG', badge: null)},
      selectedId: null,
      onSelected: (_) {},
      allLabel: 'Semua Produk',
    ));

    expect(find.text('Semua Produk'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });

  testWidgets(
      '>1 entry: chip tampilkan nama yg SEDANG dipilih, tap -> menu buka '
      'menampilkan semua pilihan + badge-nya', (tester) async {
    await tester.pumpWidget(buildHarness(
      entries: const {
        'p1': (name: 'LPG', badge: '5 jaminan'),
        'p2': (name: 'Galon', badge: '2 jaminan'),
      },
      selectedId: 'p1',
      onSelected: (_) {},
    ));

    expect(find.text('LPG'), findsOneWidget,
        reason: 'chip menampilkan produk yg sedang dipilih');

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Galon'), findsOneWidget,
        reason: 'produk LAIN tetap muncul di menu utk dipilih');
    expect(find.text('2 jaminan'), findsOneWidget,
        reason: 'badge per baris menu (desain sendiri, bukan ListTile)');
  });

  testWidgets('pilih entry lain di menu -> onSelected terpanggil dgn id-nya',
      (tester) async {
    String? selected;
    await tester.pumpWidget(buildHarness(
      entries: const {
        'p1': (name: 'LPG', badge: null),
        'p2': (name: 'Galon', badge: null),
      },
      selectedId: 'p1',
      onSelected: (id) => selected = id,
    ));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Galon'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(selected, 'p2');
  });

  testWidgets(
      'allLabel diisi & pilih opsi "Semua" -> onSelected terpanggil dgn '
      'null', (tester) async {
    String? lastValue = 'p1';
    var called = false;
    await tester.pumpWidget(buildHarness(
      entries: const {
        'p1': (name: 'LPG', badge: null),
        'p2': (name: 'Galon', badge: null),
      },
      selectedId: 'p1',
      onSelected: (id) {
        called = true;
        lastValue = id;
      },
      allLabel: 'Semua Produk',
    ));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Semua Produk').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(called, isTrue);
    expect(lastValue, isNull,
        reason: 'opsi "Semua" dipilih -> onSelected(null), BUKAN salah satu '
            'id produk');
  });
}
