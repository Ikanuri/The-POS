import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/providers/scan_frame_provider.dart';

void main() {
  test('kunci target: default mati (0), set() tersimpan, nilai liar -> 0',
      () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(scanLockMsProvider), 0);
    await c.read(scanLockMsProvider.notifier).set(600);
    expect(c.read(scanLockMsProvider), 600);
    expect((await SharedPreferences.getInstance()).getInt('scan_lock_ms'), 600);

    SharedPreferences.setMockInitialValues({'scan_lock_ms': 650});
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(scanLockMsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c2.read(scanLockMsProvider), 0);

    SharedPreferences.setMockInitialValues({'scan_lock_ms': 900});
    final c3 = ProviderContainer();
    addTearDown(c3.dispose);
    c3.read(scanLockMsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c3.read(scanLockMsProvider), 900);
  });
}
