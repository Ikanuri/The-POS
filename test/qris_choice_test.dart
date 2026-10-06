import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/qris_choice.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';
import 'package:the_pos/features/kasir/widgets/payment_qris_view.dart';

/// Pilihan QRIS (struk + pratinjau, satu pilihan utk semua): default = QRIS
/// aktif pertama; chip pilihan hanya muncul bila >= 2 QRIS aktif.
void main() {
  const qrisA = '00020101021126610014COM.GO-JEK.WWW01189360091434648855360'
      '210G4648855360303UMI51440014ID.CO.QRIS.WWW0215ID102657224253903'
      '03UMI5204549953033605802ID5920Toko Berkah, BNY NYR6011PROBOLIN'
      'GGO61056727562070703A0163043165';
  const qrisB = 'QRIS-KEDUA-STATIS';

  Future<void> seed(AppDatabase db,
      {bool second = true, bool secondActive = true}) async {
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'qa',
        type: 'qris',
        name: 'QRIS BCA',
        qrValue: const Value(qrisA),
        sortOrder: const Value(1)));
    if (second) {
      await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
          id: 'qb',
          type: 'qris',
          name: 'QRIS Dana',
          qrValue: const Value(qrisB),
          isActive: Value(secondActive),
          sortOrder: const Value(2)));
    }
  }

  test('pickQrisMethod: tersimpan menang, id tak dikenal -> pertama', () async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seed(db);
    final list = await activeQrisMethods(db);
    expect(list.map((m) => m.id), ['qa', 'qb']);
    expect(pickQrisMethod(list, null)!.id, 'qa');
    expect(pickQrisMethod(list, 'qb')!.id, 'qb');
    expect(pickQrisMethod(list, 'hilang')!.id, 'qa');
    expect(pickQrisMethod(const [], 'qb'), isNull);
    expect((await resolveSharedQrisMethod(db))!.id, 'qa');
    SharedPreferences.setMockInitialValues({kShareQrisMethodKey: 'qb'});
    expect((await resolveSharedQrisMethod(db))!.id, 'qb');
  });

  test('QRIS nonaktif tidak masuk daftar -> pilihan tersimpan jatuh ke pertama',
      () async {
    SharedPreferences.setMockInitialValues({kShareQrisMethodKey: 'qb'});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seed(db, secondActive: false);
    expect((await activeQrisMethods(db)).map((m) => m.id), ['qa']);
    expect((await resolveSharedQrisMethod(db))!.id, 'qa');
  });

  Future<void> openPreview(WidgetTester tester, AppDatabase db) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'u',
          storeKey: 'k',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(const CartItem(
        productId: 'p1',
        productUnitId: 'u1',
        productName: 'Gula',
        unitName: 'Pcs',
        qty: 2,
        price: 15000,
        originalPrice: 15000,
        costPrice: 10000));
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => const CartSheet()),
              child: const Text('buka'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bagikan Pratinjau'));
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  String shownQr(WidgetTester tester) =>
      tester.widget<QrisQrBox>(find.byType(QrisQrBox)).data;

  testWidgets(
      '2 QRIS aktif: chip muncul saat QR nyala, pilih -> QR berganti & '
      'diingat', (tester) async {
    SharedPreferences.setMockInitialValues({'cart_preview_show_qr': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seed(db);
    await openPreview(tester, db);

    expect(find.byKey(const ValueKey('qris-choice-qa')), findsOneWidget);
    expect(find.byKey(const ValueKey('qris-choice-qb')), findsOneWidget);
    expect(shownQr(tester), isNot('QRIS-KEDUA-STATIS'),
        reason: 'default = QRIS pertama');

    await tester.tap(find.byKey(const ValueKey('qris-choice-qb')));
    await tester.pumpAndSettle();
    expect(shownQr(tester), 'QRIS-KEDUA-STATIS');
    expect(
        (await SharedPreferences.getInstance()).getString(kShareQrisMethodKey),
        'qb');
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets('1 QRIS aktif: tidak ada baris pilihan (tampilan tak berubah)',
      (tester) async {
    SharedPreferences.setMockInitialValues({'cart_preview_show_qr': true});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await seed(db, second: false);
    await openPreview(tester, db);
    expect(find.byType(QrisChoiceRow), findsNothing);
    expect(find.byType(QrisQrBox), findsOneWidget);
    await drain(tester);
  });
}
