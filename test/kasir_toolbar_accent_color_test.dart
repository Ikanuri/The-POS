import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

import 'helpers/pump_app.dart';

/// Item 33 — tombol toolbar kasir (scan/antrian/riwayat/tempel pesanan)
/// diberi aksen warna soft per-fungsi (Varian C dipilih user dari mockup);
/// toggle grid/list SENGAJA tetap netral (murni preferensi tampilan).
void main() {
  testWidgets(
      'ikon scan/antrian/riwayat berwarna sesuai AppTheme (Varian C), '
      'grid TETAP netral (onSurfaceVariant)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    Color iconColorOf(IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon).first).color!;

    expect(iconColorOf(Icons.qr_code_scanner_rounded),
        AppTheme.scanFg(false));
    expect(iconColorOf(Icons.pause_circle_outline_rounded),
        AppTheme.antrianFg(false));
    expect(iconColorOf(Icons.history_rounded), AppTheme.riwayatFg(false));

    // Toggle grid/list: ikonnya `grid_view_rounded` ATAU `view_list_rounded`
    // tergantung mode aktif saat ini — cari mana yang benar-benar dirender.
    final toggleIcon = find.byIcon(Icons.grid_view_rounded).evaluate().isNotEmpty
        ? Icons.grid_view_rounded
        : Icons.view_list_rounded;
    final ctx = tester.element(find.byIcon(toggleIcon).first);
    final scheme = Theme.of(ctx).colorScheme;
    expect(iconColorOf(toggleIcon), scheme.onSurfaceVariant,
        reason: 'toggle grid/list tetap netral, bukan diwarnai');

    await db.close();
  });
}
