import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Bug nyata dilaporkan user: nota `A1-...` (dibuat device ASISTEN, kode
/// "A1") dilihat dari HP owner tertulis "Kasir: Owner". Versi lama selalu
/// menampilkan `device.deviceName` milik device yang SEDANG MELIHAT nota,
/// bukan pembuatnya. Sekarang: nama device sendiri HANYA kalau
/// `tx.kasirId` cocok dgn `deviceCode` device ini (atau kosong = nota
/// lama); kalau beda, tampilkan kode pembuatnya (`kasirLabel`).
void main() {
  late AppDatabase db;

  const owner = DeviceIdentity(
    storeUuid: 'test-store-uuid',
    storeKey: 'test-store-key',
    storeName: 'Toko Uji',
    deviceName: 'Owner',
    deviceCode: 'O1',
    deviceRole: 'owner',
  );

  Future<void> seedTx(String? kasirId) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: '${kasirId ?? 'X'}-20260902-0014',
          status: 'lunas',
          total: 15000,
          paid: 15000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          kasirId: Value(kasirId),
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 15000,
          originalPrice: 15000,
          subtotal: 15000,
        ));
  }

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'nota dibuat device LAIN (kasirId A1) dilihat dari owner -> "Kasir: A1", '
      'BUKAN nama device penampil', (tester) async {
    await seedTx('A1');
    await pumpWithFakeApp(tester,
        db: db, device: owner, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Kasir: A1'), findsOneWidget);
    expect(find.text('Kasir: Owner'), findsNothing,
        reason: 'nama device penampil tidak boleh mengaku sbg pembuat nota');

    await drain(tester);
  });

  testWidgets('nota dibuat device SENDIRI (kasirId = deviceCode) -> nama device',
      (tester) async {
    await seedTx('O1');
    await pumpWithFakeApp(tester,
        db: db, device: owner, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Kasir: Owner'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('nota lama tanpa kasirId -> tetap nama device (perilaku lama)',
      (tester) async {
    await seedTx(null);
    await pumpWithFakeApp(tester,
        db: db, device: owner, child: const ReceiptScreen(transactionId: 'tx1'));

    expect(find.text('Kasir: Owner'), findsOneWidget);

    await drain(tester);
  });
}
