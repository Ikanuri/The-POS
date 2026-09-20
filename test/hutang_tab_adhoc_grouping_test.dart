import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laporan/tabs/hutang_tab.dart';

import 'helpers/pump_app.dart';

/// Item 83 — Buku Hutang WAJIB memisahkan pelanggan TERDAFTAR dari pembeli
/// AD-HOC jadi 2 section berlabel, dan pembeli ad-hoc WAJIB ikut muncul sama
/// sekali (sebelumnya hilang total krn `getDebtBook` INNER JOIN `customers`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> addRegisteredTx({
    required String id,
    required String customerId,
    required int total,
    required int paid,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: 'kurang_bayar',
            total: total,
            paid: paid,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerId: Value(customerId),
          ));

  Future<void> addAdhocTx({
    required String id,
    required String customerName,
    required int total,
    required int paid,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: 'kurang_bayar',
            total: total,
            paid: paid,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerName: Value(customerName),
          ));

  testWidgets(
      'pelanggan tetap & pembeli ad-hoc tampil di section TERPISAH, '
      'ad-hoc TIDAK LAGI hilang dari Buku Hutang', (tester) async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Andi (Tetap)'));
    await addRegisteredTx(
        id: 't-tetap', customerId: 'c1', total: 50000, paid: 20000);
    await addAdhocTx(
        id: 't-adhoc', customerName: 'Joko (Lewat)', total: 30000, paid: 0);

    await pumpWithFakeApp(tester, db: db, child: const HutangTab());

    expect(find.text('Pelanggan Tetap'), findsOneWidget);
    expect(find.text('Pembeli Umum (Ad-hoc)'), findsOneWidget);
    expect(find.text('Andi (Tetap)'), findsOneWidget);
    expect(find.text('Joko (Lewat)'), findsOneWidget,
        reason: 'tanpa fix, pembeli ad-hoc hilang total dari Buku Hutang '
            'walau di Riwayat Transaksi nota-nya belum lunas');

    // "Andi (Tetap)" harus muncul SEBELUM section "Pembeli Umum" di tree
    // (urutan render Column: section Tetap dulu, baru Ad-hoc).
    final tetapHeaderY =
        tester.getTopLeft(find.text('Pelanggan Tetap')).dy;
    final adhocHeaderY =
        tester.getTopLeft(find.text('Pembeli Umum (Ad-hoc)')).dy;
    expect(tetapHeaderY, lessThan(adhocHeaderY));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap pembeli ad-hoc -> detail & Lunasi memakai nota yang BENAR '
      '(dicocokkan per nama, bukan customerId)', (tester) async {
    await addAdhocTx(
        id: 't-adhoc1', customerName: 'Siti', total: 40000, paid: 15000);

    await pumpWithFakeApp(tester, db: db, child: const HutangTab());

    expect(find.text('Siti'), findsOneWidget);
    await tester.tap(find.text('Siti'));
    await tester.pumpAndSettle();

    expect(find.text('Nota belum lunas'), findsOneWidget);
    expect(find.text('t-adhoc1'), findsOneWidget);
    expect(find.text(formatRupiah(25000)), findsWidgets,
        reason: 'sisa nota ad-hoc (40000-15000) harus tampil di detail');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('hanya ad-hoc (tanpa pelanggan tetap sama sekali) -> section '
      '"Pelanggan Tetap" tidak dirender, cuma "Pembeli Umum"',
      (tester) async {
    await addAdhocTx(
        id: 't-solo', customerName: 'Solo Ad-hoc', total: 10000, paid: 0);

    await pumpWithFakeApp(tester, db: db, child: const HutangTab());

    expect(find.text('Pelanggan Tetap'), findsNothing);
    expect(find.text('Pembeli Umum (Ad-hoc)'), findsOneWidget);
    expect(find.text('Solo Ad-hoc'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
