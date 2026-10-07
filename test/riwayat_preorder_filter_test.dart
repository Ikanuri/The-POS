import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/laci_meja/riwayat_laci_meja_screen.dart';

import 'helpers/pump_app.dart';

/// Riwayat Laci Meja > Pre-order: filter status (Semua/Terbuka/Pemenuhan/
/// Dibatalkan), ringkasan (berapa ditambahkan & dipenuhi, per pelanggan &
/// per produk), dan "siapa" (nama perangkat + role pencatat/pemenuh).
void main() {
  late AppDatabase db;

  Future<void> seed() async {
    for (final p in [('gas', 'Gas LPG'), ('beras', 'Beras')]) {
      await db
          .into(db.products)
          .insert(ProductsCompanion.insert(id: p.$1, name: p.$2));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '${p.$1}_u', productId: p.$1, isBaseUnit: const Value(true)));
    }
    Future<void> tx(String id, String kasir) =>
        db.into(db.transactions).insert(TransactionsCompanion.insert(
              id: id,
              localId: id,
              status: 'lunas',
              total: 1000,
              paid: 1000,
              changeAmount: 0,
              paymentMethod: 'tunai',
              kasirId: Value(kasir),
            ));
    await tx('t1', 'K1'); // perangkat ini (owner "Kasir Uji")
    await tx('t2', 'K2'); // perangkat lain, ada di registri
    await db.rememberKnownDevice(
        code: 'K2', name: 'Pegawai Budi', role: 'kasir');

    await db.addPreorderEntry(
        id: 'a',
        productId: 'gas',
        productUnitId: 'gas_u',
        customerName: 'Sari',
        qtyOrdered: 5,
        transactionId: 't1');
    await db.addPreorderEntry(
        id: 'b',
        productId: 'beras',
        productUnitId: 'beras_u',
        customerName: 'Budi',
        qtyOrdered: 10,
        transactionId: 't2');
    await db.addPreorderEntry(
        id: 'c',
        productId: 'beras',
        productUnitId: 'beras_u',
        customerName: 'Sari',
        qtyOrdered: 2,
        transactionId: 't1');
    // 'a' dipenuhi 2 oleh K2 lalu 3 oleh K1 (tuntas); 'c' dibatalkan.
    await db.fulfillPreorderQty('a', 2, deviceCode: 'K2', eventId: 'ev1');
    await db.fulfillPreorderQty('a', 3, deviceCode: 'K1', eventId: 'ev2');
    await db.cancelPreorderEntry('c', deviceCode: 'K1');
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<void> openPreorderTab(WidgetTester tester) async {
    await tester.runAsync(seed);
    await pumpWithFakeApp(tester,
        db: db,
        child: const RiwayatLaciMejaScreen(),
        surfaceSize: const Size(430, 2400));
    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();
  }

  Future<void> pickStatus(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey('po-status-$key')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('po-status-$key')));
    await tester.pumpAndSettle();
  }

  testWidgets('ringkasan: berapa ditambahkan & dipenuhi + per pelanggan/produk',
      (tester) async {
    await openPreorderTab(tester);
    expect(find.text('Ditambahkan: 3 pre-order · 17 qty'), findsOneWidget);
    expect(find.text('Dipenuhi: 2 pemenuhan · 5 qty'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('po-summary-Per pelanggan')));
    await tester.pumpAndSettle();
    // Sari: dipesan 5+2=7, dipenuhi 5; Budi: dipesan 10, dipenuhi 0.
    expect(find.text('Dipesan 7 · Dipenuhi 5'), findsOneWidget);
    expect(find.text('Dipesan 10 · Dipenuhi 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('po-summary-Per produk')));
    await tester.pumpAndSettle();
    expect(find.text('Dipesan 5 · Dipenuhi 5'), findsOneWidget); // Gas LPG
    await drain(tester);
  });

  testWidgets(
      'filter Terbuka: hanya yang belum selesai, + pencatat '
      '(nama perangkat + role)', (tester) async {
    await openPreorderTab(tester);
    await pickStatus(tester, 'terbuka');
    expect(find.byKey(const ValueKey('po-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('po-a')), findsNothing);
    expect(find.byKey(const ValueKey('po-c')), findsNothing);
    expect(find.text('Dicatat oleh Pegawai Budi (kasir)'), findsOneWidget);
    await drain(tester);
  });

  testWidgets(
      'filter Pemenuhan: daftar KEJADIAN dgn pemenuh (perangkat + '
      'role) & qty masing-masing', (tester) async {
    await openPreorderTab(tester);
    await pickStatus(tester, 'pemenuhan');
    expect(find.byKey(const ValueKey('po-ev-ev1')), findsOneWidget);
    expect(find.byKey(const ValueKey('po-ev-ev2')), findsOneWidget);
    expect(find.text('Dipenuhi 2'), findsOneWidget);
    expect(find.text('Dipenuhi 3'), findsOneWidget);
    expect(find.text('Oleh Pegawai Budi (kasir)'), findsOneWidget);
    expect(find.text('Oleh Kasir Uji (owner)'), findsOneWidget);
    expect(find.byKey(const ValueKey('po-b')), findsNothing);
    await drain(tester);
  });

  testWidgets('filter Dibatalkan: hanya yang dibatalkan', (tester) async {
    await openPreorderTab(tester);
    await pickStatus(tester, 'batal');
    expect(find.byKey(const ValueKey('po-c')), findsOneWidget);
    expect(find.byKey(const ValueKey('po-a')), findsNothing);
    expect(find.byKey(const ValueKey('po-b')), findsNothing);
    await drain(tester);
  });
}
