import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

/// Bug dilaporkan user: transaksi TEMPO (tombol "Bayar Nanti") tidak pernah
/// dapat poin loyalitas sama sekali, walau totalnya melebihi threshold yang
/// ditentukan di Pengaturan — beda dari transaksi tunai yang dapat poin
/// normal. Akar masalah: syarat `!isTempo` di `_confirm()`
/// (`payment_screen.dart`) memaksa `pointsEarned = 0` utk SEMUA transaksi
/// tempo, tanpa syarat apapun soal besarnya total.
///
/// Keputusan (dikonfirmasi user): poin diberikan LANGSUNG saat transaksi
/// tempo dicatat (sama seperti tunai), BUKAN ditunda sampai lunas — karena
/// `voidTransaction` sudah generik membalikkan poin berdasarkan
/// `pointsEarned` tersimpan, tidak peduli payment method, jadi pembatalan
/// tempo otomatis aman tanpa kode tambahan (lihat
/// `transaction_lifecycle_test.dart` utk pembuktian revert saat void).
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Beras 5kg',
    unitName: 'Karung',
    qty: 1,
    price: 100000,
    originalPrice: 100000,
    costPrice: 80000,
  );

  Future<AppDatabase> pumpAndPayTempo(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.setSetting('loyalty_point_threshold', '10000');
    await db.setSetting('loyalty_points_per', '1');
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'cust1',
          name: 'Bu Siti',
        ));

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
    container
        .read(cartMetaProvider(kMainCartId).notifier)
        .setCustomer('cust1', 'Bu Siti');

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaymentScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Bayar Nanti'));
    await tester.pumpAndSettle();

    return db;
  }

  testWidgets(
      'transaksi tempo (Bayar Nanti) TETAP dapat poin loyalitas kalau total '
      'melebihi threshold — dulu selalu 0 apapun totalnya', (tester) async {
    final db = await pumpAndPayTempo(tester);
    addTearDown(() async => db.close());

    final tx = await db.select(db.transactions).getSingle();
    expect(tx.status, 'tempo');
    expect(tx.total, 100000);
    // threshold 10.000, total 100.000 → 10 kelipatan × 1 poin/kelipatan.
    expect(tx.pointsEarned, 10,
        reason: 'transaksi tempo harus tetap dapat poin sesuai total, '
            'bukan dipaksa 0 hanya krn belum dibayar');

    final cust = await (db.select(db.customers)
          ..where((t) => t.id.equals('cust1')))
        .getSingle();
    expect(cust.loyaltyPoints, 10);

    final ledger = await db.select(db.loyaltyPointLedger).get();
    expect(ledger, hasLength(1));
    expect(ledger.first.type, 'earn');
    expect(ledger.first.points, 10);
  });
}
