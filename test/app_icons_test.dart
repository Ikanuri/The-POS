import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/widgets/app_icons.dart';

void main() {
  testWidgets('AppIcon: semua jenis tergambar (garis & duotone) tanpa galat',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Wrap(children: [
          for (final k in AppIconKind.values)
            for (final f in [false, true])
              AppIcon(k, color: Colors.brown, filled: f),
        ]),
      ),
    ));
    expect(find.byType(AppIcon), findsNWidgets(AppIconKind.values.length * 2));
    expect(tester.takeException(), isNull);
  });
}
