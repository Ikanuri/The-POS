import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/payment_methods_screen.dart';

import 'helpers/pump_app.dart';

/// Item 14 — edit metode (reuse sheet, prefill+update) & hapus via swipe
/// hanya bila metode sudah dinonaktifkan.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  Future<List<PaymentMethod>> methods() => db.select(db.paymentMethods).get();

  /// Unmount tree secara eksplisit lalu pump — memicu disposal
  /// StreamProvider (drift `markAsClosed` menjadwalkan timer 0ms saat
  /// cancel) SELAGI test masih jalan, lalu drain timer itu; kalau tidak,
  /// binding menemukan "Timer still pending" saat disposal di akhir test.
  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets('tap metode → sheet prefilled, Simpan meng-update namanya',
      (tester) async {
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-bca', type: 'bank', name: 'BCA', sortOrder: const Value(1)));

    await pumpWithFakeApp(tester,
        db: db, child: const PaymentMethodsScreen());

    await tester.tap(find.text('BCA'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Metode Pembayaran'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'BCA'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'BCA Baru');
    await tester.tap(find.widgetWithText(FilledButton, 'Simpan'));
    await tester.pumpAndSettle();

    final m = (await methods()).firstWhere((x) => x.id == 'pm-bca');
    expect(m.name, 'BCA Baru');
    await drain(tester);
  });

  testWidgets(
      'swipe metode AKTIF → ditolak (harus dinonaktifkan dulu), tetap ada',
      (tester) async {
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-ovo',
        type: 'ewallet',
        name: 'OVO',
        isActive: const Value(true),
        sortOrder: const Value(1)));

    await pumpWithFakeApp(tester,
        db: db, child: const PaymentMethodsScreen());

    await tester.drag(find.text('OVO'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Guard aktif: muncul snackbar penolakan, BUKAN dialog konfirmasi hapus.
    expect(find.text('Nonaktifkan metode ini dulu sebelum menghapus.'),
        findsOneWidget);
    expect(find.text('Hapus OVO?'), findsNothing);
    expect((await methods()).any((m) => m.id == 'pm-ovo'), isTrue);
    await drain(tester);
  });

  testWidgets('swipe metode NONAKTIF → konfirmasi → terhapus dari DB',
      (tester) async {
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-dana',
        type: 'ewallet',
        name: 'DANA',
        isActive: const Value(false),
        sortOrder: const Value(1)));

    await pumpWithFakeApp(tester,
        db: db, child: const PaymentMethodsScreen());

    await tester.drag(find.text('DANA'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Hapus DANA?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();

    expect((await methods()).any((m) => m.id == 'pm-dana'), isFalse);
    await drain(tester);
  });

  testWidgets('metode Tunai tidak bisa di-swipe hapus (tetap ada)',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const PaymentMethodsScreen());

    await tester.drag(find.text('Tunai'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect((await methods()).any((m) => m.type == 'tunai'), isTrue);
    await drain(tester);
  });
}
