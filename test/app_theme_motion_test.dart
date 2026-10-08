import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_motion.dart';
import 'package:the_pos/core/theme/app_theme.dart';

/// Tema (terang & gelap): riak sentuh lembut ala Telegram, animasi tombol
/// memakai token gerak, transisi halaman kustom.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final dark in [false, true]) {
    test('tema ${dark ? 'gelap' : 'terang'}: riak polos + token gerak', () {
      final t = dark ? AppTheme.dark() : AppTheme.light();
      expect(t.splashFactory, same(InkRipple.splashFactory));
      expect(t.splashColor.opacity, inInclusiveRange(0.05, 0.12));
      expect(t.highlightColor.opacity, lessThan(t.splashColor.opacity));

      // Style tombol memuat durasi animasi dari token.
      final filled = t.filledButtonTheme.style!.animationDuration;
      final outlined = t.outlinedButtonTheme.style!.animationDuration;
      expect(filled, AppMotion.fast);
      expect(outlined, AppMotion.fast);
      expect(t.pageTransitionsTheme.builders, isNotEmpty);
    });
  }
}
