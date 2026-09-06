import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/cart_debt_settlement_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';
import 'package:the_pos/features/kasir/widgets/debt_settlement_picker.dart';

/// Fitur "Lunasi Hutang" (UI, `cart_sheet.dart`) — entry point (ikon footer)
/// muncul/hilang sesuai gerbang izin `terima_pembayaran` (sama persis
/// Pra-Bayar), ringkasan entri tampil LIVE di footer, hapus entri → hilang,
/// dan alur lengkap pilih pelanggan -> pilih nota -> nominal menghasilkan
/// entri dgn rencana FIFO yang benar.
void main() {
  const item = CartItem(
    productId: 'p1',
    productUnitId: 'u1',
    productName: 'Gula Pasir',
    unitName: 'Pcs',
    qty: 2,
    price: 15000,
    originalPrice: 15000,
    costPrice: 10000,
  );

  Future<
      ({
        AppDatabase db,
        ProviderContainer container,
      })> pumpCartSheetOpen(
    WidgetTester tester, {
    required String deviceRole,
    bool terimaPembayaran = false,
    String cartId = kMainCartId,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(KasirPermissionsCompanion(isEnabled: Value(terimaPembayaran)));
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'HP Kasir',
          deviceCode: 'K2',
          deviceRole: deviceRole,
        )),
    ]);
    addTearDown(container.dispose);
    container.read(cartProvider(cartId).notifier).addItem(item);

    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => CartSheet(cartId: cartId),
                ),
                child: const Text('buka keranjang'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('buka keranjang'));
    await tester.pumpAndSettle();
    return (db: db, container: container);
  }

  testWidgets('owner (bergerbang) melihat tombol Lunasi Hutang', (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());
    expect(find.byTooltip('Lunasi Hutang'), findsOneWidget);
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran TIDAK melihat tombol Lunasi Hutang',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir', terimaPembayaran: false);
    addTearDown(() async => r.db.close());
    expect(find.byTooltip('Lunasi Hutang'), findsNothing);
  });

  testWidgets('mode Katalog TIDAK menampilkan tombol Lunasi Hutang',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner', cartId: kCatalogCartId);
    addTearDown(() async => r.db.close());
    expect(find.byTooltip('Lunasi Hutang'), findsNothing);
  });

  testWidgets(
      'entri Lunasi Hutang (seed langsung) -> ringkasan footer tampil, tap '
      '-> daftar entri, hapus -> ringkasan hilang', (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    expect(find.textContaining('Turut lunasi hutang'), findsNothing);

    r.container.read(cartDebtSettlementProvider(kMainCartId).notifier).add(
          DebtSettlementEntry(
            id: 'e1',
            customerId: 'c1',
            customerName: 'Sari',
            amount: 50000,
            targetInvoices: const [
              DebtSettlementTarget(
                  invoiceId: 'old1', invoiceLocalId: 'A1-0007', amount: 50000),
            ],
            createdAt: DateTime.now(),
          ),
        );
    await tester.pumpAndSettle();

    expect(
        find.text('Turut lunasi hutang ${formatRupiah(50000)}'),
        findsOneWidget);

    await tester.tap(find.text('Turut lunasi hutang ${formatRupiah(50000)}'));
    await tester.pumpAndSettle();

    expect(find.text('Entri Lunasi Hutang'), findsOneWidget);
    expect(find.textContaining('Sari'), findsOneWidget);
    expect(find.textContaining('A1-0007'), findsOneWidget);

    await tester.tap(find.byTooltip('Hapus'));
    await tester.pumpAndSettle();
    expect(
        r.container.read(cartDebtSettlementProvider(kMainCartId)), isEmpty);

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Turut lunasi hutang'), findsNothing);
  });

  testWidgets(
      'alur lengkap: tap ikon -> pilih pelanggan -> pilih nota -> nominal '
      '-> entri baru dgn rencana FIFO benar', (tester) async {
    final r = await pumpCartSheetOpen(tester, deviceRole: 'owner');
    addTearDown(() async => r.db.close());

    await r.db.into(r.db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Sari'));
    await r.db.into(r.db.transactions).insert(TransactionsCompanion.insert(
          id: 'old1',
          localId: 'A1-0007',
          status: 'kurang_bayar',
          total: 50000,
          paid: 20000, // sisa 30000
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('c1'),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 3))),
        ));

    await tester.tap(find.byTooltip('Lunasi Hutang'));
    await tester.pumpAndSettle();

    // Step 1: pilih pelanggan.
    expect(find.text('Lunasi Hutang — Pilih Pelanggan'), findsOneWidget);
    expect(find.text('Sari'), findsOneWidget);
    await tester.tap(find.text('Sari'));
    await tester.pumpAndSettle();

    // Step 2: pilih nota (default semua dicentang) -> Lanjut.
    expect(find.text('Pilih Nota — Sari'), findsOneWidget);
    expect(find.text('A1-0007'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await tester.pumpAndSettle();

    // Step 3: kalkulator nominal (showDebtPaymentSheet), prefill = sisa
    // (30000) -> tap Bayar langsung.
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    final entries =
        r.container.read(cartDebtSettlementProvider(kMainCartId));
    expect(entries, hasLength(1));
    expect(entries.single.customerName, 'Sari');
    expect(entries.single.amount, 30000);
    expect(entries.single.targetInvoices, hasLength(1));
    expect(entries.single.targetInvoices.single.invoiceLocalId, 'A1-0007');
    expect(entries.single.targetInvoices.single.amount, 30000);

    expect(
        find.text('Turut lunasi hutang ${formatRupiah(30000)}'),
        findsOneWidget);
  });

  group('planFifoSettlement (pure)', () {
    test('cukup di nota pertama saja, nota kedua tidak tersentuh', () {
      final targets = planFifoSettlement([
        UnpaidTxEntry(
            id: 'a', localId: 'A', createdAt: DateTime(2026, 1, 1), sisa: 10000),
        UnpaidTxEntry(
            id: 'b', localId: 'B', createdAt: DateTime(2026, 1, 2), sisa: 20000),
      ], 10000);
      expect(targets, hasLength(1));
      expect(targets.single.invoiceId, 'a');
      expect(targets.single.amount, 10000);
    });

    test('meluber ke nota kedua (FIFO), nota kedua partial', () {
      final targets = planFifoSettlement([
        UnpaidTxEntry(
            id: 'a', localId: 'A', createdAt: DateTime(2026, 1, 1), sisa: 10000),
        UnpaidTxEntry(
            id: 'b', localId: 'B', createdAt: DateTime(2026, 1, 2), sisa: 20000),
      ], 25000);
      expect(targets, hasLength(2));
      expect(targets[0].amount, 10000);
      expect(targets[1].amount, 15000);
    });

    test(
        'TIDAK OVERPAY: amount melebihi total sisa SEMUA nota terpilih -> '
        'tiap nota dicap ke sisa-nya sendiri, kelebihan TIDAK dialokasikan '
        'kemana pun', () {
      final targets = planFifoSettlement([
        UnpaidTxEntry(
            id: 'a', localId: 'A', createdAt: DateTime(2026, 1, 1), sisa: 10000),
        UnpaidTxEntry(
            id: 'b', localId: 'B', createdAt: DateTime(2026, 1, 2), sisa: 20000),
      ], 999999);
      expect(targets, hasLength(2));
      expect(targets[0].amount, 10000);
      expect(targets[1].amount, 20000);
      final totalAllocated = targets.fold<int>(0, (s, t) => s + t.amount);
      expect(totalAllocated, 30000,
          reason: 'total teralokasi TIDAK PERNAH melebihi total sisa nota '
              'terpilih (30000), walau amount diminta jauh lebih besar');
    });
  });
}
