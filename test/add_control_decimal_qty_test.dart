import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/kasir/widgets/add_control.dart';

/// Bug dilaporkan user: badge bulat `AddControl` (dipakai di kartu produk &
/// baris item keranjang) diberi qty desimal (mis. 0.25, produk timbang) tidak
/// tampil proper — label "0.25" (4 karakter) di lingkaran ber-diameter tetap
/// yang biasanya cuma menampung 1-2 digit. User pilih badge TETAP bulat
/// (bukan diganti pill), font-nya saja yang menyusut proporsional.
void main() {
  testWidgets(
      'qty desimal (0.25) tampil APA ADANYA (bukan dibulatkan) & tidak '
      'overflow — dibungkus FittedBox supaya font menyusut, tetap bulat',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: AddControl(qty: 0.25, onTap: () {}, onMinus: () {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('0.25'), findsOneWidget,
        reason: 'label harus persis "0.25", bukan dibulatkan ke "0"/"1"');
    expect(find.byType(FittedBox), findsOneWidget,
        reason: 'font harus bisa menyusut utk label >2 karakter, badge '
            'tetap lingkaran (bukan diganti bentuk pill)');
    expect(tester.takeException(), isNull,
        reason: 'tidak boleh ada overflow/exception render');
  });

  testWidgets('qty bulat (2) tetap tampil normal, tanpa overflow',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: AddControl(qty: 2, onTap: () {}, onMinus: () {})),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
