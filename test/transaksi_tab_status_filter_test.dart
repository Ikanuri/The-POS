import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laporan/tabs/transaksi_tab.dart';

import 'helpers/pump_app.dart';

/// Permintaan user — Laporan > Transaksi kini punya filter kategori status
/// (Semua/Lunas/Kurang/Void) selain filter tanggal (yang sudah ada di
/// tingkat `LaporanScreen` lewat `dateRangeProvider`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> addTx({
    required String id,
    required String status,
    required int total,
    required int paid,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: status,
            total: total,
            paid: paid,
            changeAmount: 0,
            paymentMethod: 'tunai',
            createdAt: Value(DateTime.now()),
          ));

  Widget buildTab() => TransaksiTab(
        range: DateTimeRange(
          start: DateTime.now().subtract(const Duration(days: 1)),
          end: DateTime.now().add(const Duration(days: 1)),
        ),
      );

  testWidgets(
      'chip Lunas/Kurang/Void memfilter daftar transaksi sesuai kategori '
      'status', (tester) async {
    await addTx(id: 'K1-LUNAS', status: 'lunas', total: 10000, paid: 10000);
    await addTx(
        id: 'K1-KURANG', status: 'kurang_bayar', total: 20000, paid: 5000);
    await addTx(id: 'K1-VOID', status: 'void', total: 30000, paid: 30000);

    await pumpWithFakeApp(tester, db: db, child: buildTab());

    // Default "Semua" — ketiganya tampil.
    expect(find.text('K1-LUNAS'), findsOneWidget);
    expect(find.text('K1-KURANG'), findsOneWidget);
    expect(find.text('K1-VOID'), findsOneWidget);

    await tester.tap(find.text('Lunas'));
    await tester.pumpAndSettle();
    expect(find.text('K1-LUNAS'), findsOneWidget);
    expect(find.text('K1-KURANG'), findsNothing);
    expect(find.text('K1-VOID'), findsNothing);

    await tester.tap(find.text('Kurang'));
    await tester.pumpAndSettle();
    expect(find.text('K1-LUNAS'), findsNothing);
    expect(find.text('K1-KURANG'), findsOneWidget);
    expect(find.text('K1-VOID'), findsNothing);

    await tester.tap(find.text('Void'));
    await tester.pumpAndSettle();
    expect(find.text('K1-LUNAS'), findsNothing);
    expect(find.text('K1-KURANG'), findsNothing);
    expect(find.text('K1-VOID'), findsOneWidget);

    await tester.tap(find.text('Semua'));
    await tester.pumpAndSettle();
    expect(find.text('K1-LUNAS'), findsOneWidget);
    expect(find.text('K1-KURANG'), findsOneWidget);
    expect(find.text('K1-VOID'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'status "tempo" ikut masuk kategori Kurang (sama seperti badge KURANG/'
      'TEMPO di daftar)', (tester) async {
    await addTx(id: 'K1-TEMPO', status: 'tempo', total: 40000, paid: 0);

    await pumpWithFakeApp(tester, db: db, child: buildTab());

    await tester.tap(find.text('Kurang'));
    await tester.pumpAndSettle();
    expect(find.text('K1-TEMPO'), findsOneWidget);

    await tester.tap(find.text('Lunas'));
    await tester.pumpAndSettle();
    expect(find.text('K1-TEMPO'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
