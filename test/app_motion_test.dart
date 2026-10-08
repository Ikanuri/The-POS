import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/theme/app_motion.dart';

void main() {
  test('durasi berurutan & wajar (fast < base < medium < page <= 300ms)', () {
    expect(AppMotion.fast < AppMotion.base, isTrue);
    expect(AppMotion.base < AppMotion.medium, isTrue);
    expect(AppMotion.medium < AppMotion.page, isTrue);
    expect(AppMotion.page.inMilliseconds, lessThanOrEqualTo(300));
  });

  test('semua kurva: 0 -> 0, 1 -> 1; hanya easeOutBack yang melampaui 1', () {
    final curves = {
      'standard': AppMotion.standard,
      'easeOutQuint': AppMotion.easeOutQuint,
      'easeIn': AppMotion.easeIn,
      'easeOut': AppMotion.easeOut,
      'easeOutBack': AppMotion.easeOutBack,
    };
    curves.forEach((name, c) {
      expect(c.transform(0), closeTo(0, 1e-6), reason: name);
      expect(c.transform(1), closeTo(1, 1e-6), reason: name);
      var maxV = 0.0;
      for (var t = 0.0; t <= 1.0; t += 0.01) {
        maxV = maxV > c.transform(t) ? maxV : c.transform(t);
      }
      if (name == 'easeOutBack') {
        expect(maxV, greaterThan(1.05), reason: name);
      } else {
        expect(maxV, lessThanOrEqualTo(1.0 + 1e-6), reason: name);
      }
    });
    // easeOutQuint: sudah >80% di separuh waktu (mulai cepat, mendarat halus).
    expect(AppMotion.easeOutQuint.transform(0.5), greaterThan(0.8));
  });

  testWidgets('dur() menjadi nol saat animasi dimatikan di sistem',
      (tester) async {
    late Duration normal, off;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        normal = AppMotion.dur(c, AppMotion.base);
        return MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: Builder(builder: (c2) {
            off = AppMotion.dur(c2, AppMotion.base);
            return const SizedBox();
          }),
        );
      }),
    ));
    expect(normal, AppMotion.base);
    expect(off, Duration.zero);
    expect(tester.takeException(), isNull);
  });
}
