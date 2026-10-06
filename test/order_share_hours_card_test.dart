import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_access_service.dart';
import 'package:the_pos/features/pengaturan/order_share_screen.dart';

import 'helpers/pump_app.dart';

/// Layar Katalog Pesanan — kartu "Jam buka katalog": sakelar jadwal, jam
/// buka/tutup, tombol darurat "Tutup sekarang". Tanpa label zona waktu.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('sakelar jadwal menyimpan & menampilkan jam; tutup sekarang',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpWithFakeApp(tester,
        db: db,
        child: const OrderShareScreen(),
        surfaceSize: const Size(360, 1800));
    await tester.pumpAndSettle();

    // Awal: jadwal mati -> baris jam tersembunyi.
    expect(find.byKey(const ValueKey('hours-open')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('hours-enabled')));
    await tester.pumpAndSettle();
    expect((await CatalogAccessService.loadHours(db)).enabled, isTrue);
    expect(find.text('Buka 07:00'), findsOneWidget);
    expect(find.text('Tutup 21:00'), findsOneWidget);
    // Tanpa label zona waktu (keputusan user: tidak verbose).
    expect(find.textContaining('WIB'), findsNothing);
    expect(find.textContaining('Zona'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('hours-forced')));
    await tester.pumpAndSettle();
    expect((await CatalogAccessService.loadHours(db)).forcedClosed, isTrue);
    expect(tester.takeException(), isNull);
    await drain(tester);
  });
}
