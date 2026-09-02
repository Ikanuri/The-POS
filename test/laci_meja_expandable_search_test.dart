import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/laci_meja/laci_meja_expandable_search.dart';

/// Susulan (permintaan user, screenshot layout sempit dashboard/riwayat
/// Laci Meja) — widget test MURNI utk `LaciMejaExpandableSearch`, terpisah
/// dari layar penggunanya (dashboard/riwayat) supaya perilaku expand/
/// collapse-nya bisa dites tanpa perlu setup DB/router sama sekali.
void main() {
  Widget buildHarness({
    required bool expanded,
    required ValueChanged<bool> onExpandedChanged,
    required ValueChanged<String> onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LaciMejaExpandableSearch(
          hintText: 'Cari sesuatu…',
          expanded: expanded,
          onExpandedChanged: onExpandedChanged,
          onChanged: onChanged,
        ),
      ),
    );
  }

  testWidgets('collapsed: tampil ikon "Cari", TIDAK ada TextField',
      (tester) async {
    await tester.pumpWidget(buildHarness(
      expanded: false,
      onExpandedChanged: (_) {},
      onChanged: (_) {},
    ));

    expect(find.byTooltip('Cari'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
      'tap ikon collapsed -> onExpandedChanged(true) terpanggil (pemanggil '
      'yg memutuskan status expanded, bukan widget ini sendiri)',
      (tester) async {
    var expandedCalledWith = <bool>[];
    await tester.pumpWidget(buildHarness(
      expanded: false,
      onExpandedChanged: expandedCalledWith.add,
      onChanged: (_) {},
    ));

    await tester.tap(find.byTooltip('Cari'));
    await tester.pump();

    expect(expandedCalledWith, [true]);
  });

  testWidgets(
      'expanded: TextField tampil dgn hintText yg benar, TIDAK ada ikon '
      'collapsed', (tester) async {
    await tester.pumpWidget(buildHarness(
      expanded: true,
      onExpandedChanged: (_) {},
      onChanged: (_) {},
    ));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Cari'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, 'Cari sesuatu…');
  });

  testWidgets('ketik di field expanded -> onChanged terpanggil dgn teksnya',
      (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(buildHarness(
      expanded: true,
      onExpandedChanged: (_) {},
      onChanged: changes.add,
    ));

    await tester.enterText(find.byType(TextField), 'Budi');
    await tester.pump();

    expect(changes, ['Budi']);
  });

  testWidgets(
      'kehilangan fokus (tap di luar) -> onExpandedChanged(false), TANPA '
      'menghapus teks yg sudah diketik (onChanged TIDAK dipanggil ulang '
      'dgn string kosong)', (tester) async {
    final changes = <String>[];
    final expandedChanges = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            LaciMejaExpandableSearch(
              hintText: 'Cari sesuatu…',
              expanded: true,
              onExpandedChanged: expandedChanges.add,
              onChanged: changes.add,
            ),
            const Text('area luar'),
          ],
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Budi');
    await tester.pump();
    changes.clear();

    await tester.tap(find.text('area luar'));
    await tester.pump();

    expect(expandedChanges, [false],
        reason: 'blur (tap di luar) harus meminta pemanggil mengecilkan '
            'field, terlepas dari isi teksnya');
    expect(changes, isEmpty,
        reason: 'teks yg sudah diketik TIDAK ikut dihapus saat mengecil — '
            'hanya lebar visual yang berubah, bukan isi field');
  });

  testWidgets(
      'tombol x saat field KOSONG -> minta mengecil (onExpandedChanged '
      'false)', (tester) async {
    final expandedChanges = <bool>[];
    await tester.pumpWidget(buildHarness(
      expanded: true,
      onExpandedChanged: expandedChanges.add,
      onChanged: (_) {},
    ));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(expandedChanges, [false]);
  });

  testWidgets(
      'tombol x saat field ADA ISINYA -> menghapus teks (onChanged("")), '
      'TETAP expanded (onExpandedChanged TIDAK dipanggil)', (tester) async {
    final changes = <String>[];
    final expandedChanges = <bool>[];
    await tester.pumpWidget(buildHarness(
      expanded: true,
      onExpandedChanged: expandedChanges.add,
      onChanged: changes.add,
    ));

    await tester.enterText(find.byType(TextField), 'Budi');
    await tester.pump();
    changes.clear();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(changes, [''],
        reason: 'tombol x saat ada isi menghapus teks (bukan mengecilkan '
            'field)');
    expect(expandedChanges, isEmpty,
        reason: 'field TETAP expanded selama masih ada isi yg dihapus, '
            'bukan langsung mengecil');
    expect(find.byType(TextField), findsOneWidget,
        reason: 'field masih dalam status expanded setelah teks dihapus');
  });
}
