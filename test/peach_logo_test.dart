import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/widgets/peach_logo.dart';

/// Logo persik di header Kasir = gambar yang sama dengan logo katalog HTML.
void main() {
  test('data jalur persik identik dengan #storeLogo di katalog HTML', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final html =
        (await OrderPageService.generateHtml(db: db, storeName: 'Budi Mart'))
            .html;
    await db.close();
    final a = html.indexOf('id="storeLogo"');
    final span = html.substring(a, html.indexOf('</span>', a));
    final ds = RegExp(r' d="([^"]+)"').allMatches(span).map((m) => m[1]!);
    expect(ds.toList(), kPeachPathData);
  });

  test('keempat jalur terparse jadi path tak kosong di ruang 512', () {
    for (final d in kPeachPathData) {
      final b = parsePeachPath(d).getBounds();
      expect(b.isEmpty, isFalse);
      expect(b.left, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(512));
      expect(b.bottom, lessThanOrEqualTo(512));
    }
  });

  testWidgets('badge: kotak aksen ukuran size, persik 72%', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Center(child: PeachLogoBadge(size: 34))));
    expect(tester.getSize(find.byType(PeachLogoBadge)), const Size(34, 34));
    expect(
        tester.getSize(find.byType(PeachLogo)).width, closeTo(34 * 0.72, 1e-6));
    final box = tester.widget<Container>(find.descendant(
        of: find.byType(PeachLogoBadge), matching: find.byType(Container)));
    expect((box.decoration as BoxDecoration).color, AppTheme.accent);
  });
}
