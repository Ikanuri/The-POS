import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/pelanggan/pelanggan_list_screen.dart';

import 'helpers/pump_app.dart';

/// Redesain halaman Pelanggan (gaya landing): header jumlah + judul serif,
/// kartu per pelanggan dgn lencana poin & utang, empty state beraksi.
void main() {
  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets('daftar: jumlah di header, kartu, lencana poin & utang',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.customers).insert(CustomersCompanion.insert(
        id: 'c1',
        name: 'Budi Santoso',
        phone: const Value('0812345'),
        loyaltyPoints: const Value(12),
        outstandingDebt: const Value(50000)));
    await db
        .into(db.customers)
        .insert(CustomersCompanion.insert(id: 'c2', name: 'Citra'));
    await pumpWithFakeApp(tester,
        db: db,
        child: const PelangganListScreen(),
        surfaceSize: const Size(360, 800));
    await tester.pumpAndSettle();
    expect(find.text('2 pelanggan'), findsOneWidget);
    expect(find.text('Pelanggan'), findsOneWidget);
    expect(find.text('Budi Santoso'), findsOneWidget);
    expect(find.text('12 poin'), findsOneWidget);
    expect(find.text('Utang: ${formatRupiah(50000)}'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.byTooltip('Tambah Pelanggan'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await drain(tester);
    await db.close();
  });

  testWidgets('kosong: empty state dengan tombol Tambah Pelanggan',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester,
        db: db, child: const PelangganListScreen());
    await tester.pumpAndSettle();
    expect(find.text('Belum ada pelanggan'), findsOneWidget);
    expect(find.text('Tambah Pelanggan'), findsOneWidget);
    await drain(tester);
    await db.close();
  });
}
