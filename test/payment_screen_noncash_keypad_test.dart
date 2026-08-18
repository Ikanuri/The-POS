import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Item 62 — kalkulator (keypad) yang dulu HANYA dipakai tunai (non-tunai
/// selalu dipaksa lunas exact = _total, tanpa kalkulator sama sekali)
/// sekarang dipakai SAMA persis untuk metode non-tunai juga (bisa
/// dibayar kurang → kurang_bayar). Metadata (no. rekening/HP) metode
/// non-QRIS juga wajib tampil di layar checkout.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 1,
    price: 100000,
    originalPrice: 100000,
    costPrice: 60000,
  );

  Future<AppDatabase> makeDbWithBankMethod() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.paymentMethods).insert(
          PaymentMethodsCompanion.insert(
            id: 'pm-bri',
            type: 'bank',
            name: 'BRI',
            data: const Value('1234-5678-9012'),
            sortOrder: const Value(1),
          ),
        );
    return db;
  }

  Future<ProviderContainer> pumpPayment(WidgetTester tester, AppDatabase db,
      {String initialCartId = kMainCartId}) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(kMainCartId).notifier).addItem(item);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
      'pilih metode non-tunai (bank) → tampil metadata no. rekening di layar checkout',
      (tester) async {
    final db = await makeDbWithBankMethod();
    await pumpPayment(tester, db);

    await tester.tap(find.widgetWithText(ChoiceChip, 'BRI'));
    await tester.pumpAndSettle();

    expect(find.text('No. Rekening — BRI'), findsOneWidget);
    expect(find.text('1234-5678-9012'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'tombol salin di metadata non-tunai menyalin nomor ke clipboard & tampilkan snackbar',
      (tester) async {
    final db = await makeDbWithBankMethod();

    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await pumpPayment(tester, db);

    await tester.tap(find.widgetWithText(ChoiceChip, 'BRI'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.copy_outlined));
    await tester.pump();

    expect(copied, '1234-5678-9012');
    expect(find.text('Nomor disalin'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'tap Bayar dgn metode non-tunai membuka kalkulator yang sama (label kunci metode) dan mengizinkan nominal kurang',
      (tester) async {
    final db = await makeDbWithBankMethod();
    await pumpPayment(tester, db);

    await tester.tap(find.widgetWithText(ChoiceChip, 'BRI'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Bayar Rp'));
    await tester.pumpAndSettle();

    // Kalkulator terbuka (bukan langsung konfirmasi) + penanda metode terkunci.
    expect(find.text('Metode: BRI'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    // Ketik nominal KURANG dari total (100.000) → tombol harus berlabel
    // "Catat Hutang", bukan langsung "Bayar" (dulu non-tunai tidak pernah
    // bisa kurang sama sekali, karena tidak pernah dapat kalkulator).
    await tester.tap(find.text('5'));
    await tester.tap(find.text('0'));
    await tester.tap(find.text('0'));
    await tester.tap(find.text('0'));
    await tester.tap(find.text('0'));
    await tester.pump();

    expect(find.textContaining('Catat Hutang'), findsOneWidget);

    await tester.tap(find.textContaining('Catat Hutang'));
    await tester.pumpAndSettle();

    final tx = await (db.select(db.transactions)).getSingle();
    expect(tx.status, 'kurang_bayar');
    expect(tx.paid, 50000);
    expect(tx.paymentMethod, 'bank');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
