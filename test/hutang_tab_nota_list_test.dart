import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laporan/tabs/hutang_tab.dart';

import 'helpers/pump_app.dart';

/// Buku Hutang: modal detail pelanggan sekarang menampilkan daftar nota
/// individual yang belum lunas (nomor, tanggal, sisa) — bukan cuma total
/// agregat — supaya user bisa lihat "nota mana saja" yang belum lunas
/// tanpa perlu nyambung ke tab/layar lain.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> addTx({
    required String id,
    required int total,
    required int paid,
    required DateTime createdAt,
  }) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: 'kurang_bayar',
            total: total,
            paid: paid,
            changeAmount: 0,
            paymentMethod: 'tunai',
            customerId: const Value('c1'),
            createdAt: Value(createdAt),
          ));

  testWidgets(
      'tap pelanggan di Buku Hutang membuka daftar nota belum lunas '
      '(nomor + sisa masing-masing)', (tester) async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Budi'));
    final now = DateTime.now();
    await addTx(
        id: 'K1-old',
        total: 50000,
        paid: 30000,
        createdAt: now.subtract(const Duration(days: 10)));
    await addTx(
        id: 'K1-new',
        total: 20000,
        paid: 0,
        createdAt: now.subtract(const Duration(days: 1)));

    await pumpWithFakeApp(tester, db: db, child: const HutangTab());

    expect(find.text('Budi'), findsOneWidget);
    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();

    expect(find.text('Nota belum lunas'), findsOneWidget);
    expect(find.text('K1-old'), findsOneWidget);
    expect(find.text('K1-new'), findsOneWidget);
    // Sisa masing-masing nota: 50000-30000=20000, 20000-0=20000.
    expect(find.text(formatRupiah(20000)), findsWidgets);
  });
}
