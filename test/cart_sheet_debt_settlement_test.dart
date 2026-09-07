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
import 'package:the_pos/features/kasir/cart_meta_provider.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_sheet.dart';

/// Fitur "Lunasi Hutang" — REDESAIN TOTAL (permintaan user): dulu ikon
/// terpisah di footer -> alur pilih pelanggan/nota/nominal manual (bisa
/// misclick pelanggan lain). SEKARANG: satu baris toggle DI DALAM daftar
/// item keranjang itu sendiri, otomatis terikat `CartMeta.customerId`
/// keranjang aktif — muncul HANYA bila pelanggan itu (BUKAN pelanggan lain)
/// punya hutang tertunggak, default pudar, tap -> solid + entri otomatis
/// SELURUH nominal hutang, tap lagi -> pudar + entri terhapus.
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
    String? customerId,
    String? customerName,
    Future<void> Function(AppDatabase db)? seed,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('terima_pembayaran')))
        .write(KasirPermissionsCompanion(isEnabled: Value(terimaPembayaran)));
    // WAJIB seed SEBELUM sheet dibuka & provider pertama kali di-watch —
    // `cartCustomerDebtProvider` (FutureProvider.autoDispose) TIDAK auto-
    // refetch begitu saja saat DB berubah belakangan (beda dari StreamProvider),
    // jadi data harus sudah ada di DB SAAT provider pertama kali dibaca.
    if (seed != null) await seed(db);
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
    if (customerId != null || customerName != null) {
      container
          .read(cartMetaProvider(cartId).notifier)
          .setCustomer(customerId, customerName);
    }

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

  Future<void> seedDebt(AppDatabase db,
      {required String customerId,
      required String customerName,
      required String invoiceId,
      required int total,
      required int paid}) async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: customerId, name: customerName));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: invoiceId,
          localId: invoiceId,
          status: 'kurang_bayar',
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: Value(customerId),
          createdAt: Value(DateTime.now().subtract(const Duration(days: 3))),
        ));
  }

  testWidgets(
      'pelanggan TANPA hutang -> baris toggle Lunasi Hutang TIDAK muncul',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari');
    addTearDown(() async => r.db.close());
    expect(find.textContaining('Lunasi hutang'), findsNothing);
  });

  testWidgets(
      'keranjang TANPA pelanggan terikat -> baris toggle TIDAK muncul walau '
      'ada pelanggan LAIN yang berhutang', (tester) async {
    final r = await pumpCartSheetOpen(
      tester,
      deviceRole: 'owner',
      terimaPembayaran: true,
      // Tidak set customer di cart meta sama sekali.
      seed: (db) => seedDebt(db,
          customerId: 'c1',
          customerName: 'Sari',
          invoiceId: 'A1-0007',
          total: 50000,
          paid: 20000),
    );
    addTearDown(() async => r.db.close());
    expect(find.textContaining('Lunasi hutang'), findsNothing);
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran -> baris toggle TIDAK muncul '
      'walau pelanggan terikat punya hutang', (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir',
        terimaPembayaran: false,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) => seedDebt(db,
            customerId: 'c1',
            customerName: 'Sari',
            invoiceId: 'A1-0007',
            total: 50000,
            paid: 20000));
    addTearDown(() async => r.db.close());
    expect(find.textContaining('Lunasi hutang'), findsNothing);
  });

  testWidgets(
      'pelanggan terikat punya hutang -> baris muncul pudar, tap -> solid + '
      'entri otomatis SELURUH nominal, tap lagi -> pudar + entri terhapus',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) => seedDebt(db,
            customerId: 'c1',
            customerName: 'Sari',
            invoiceId: 'A1-0007',
            total: 50000,
            paid: 20000)); // sisa 30000
    addTearDown(() async => r.db.close());

    final rowFinder =
        find.text('Lunasi hutang ${formatRupiah(30000)} (1 nota)');
    expect(rowFinder, findsOneWidget);

    // Default pudar — cek Opacity leluhur bernilai 0.5 (belum aktif).
    Opacity opacityOf() => tester.widget<Opacity>(
        find.ancestor(of: rowFinder, matching: find.byType(Opacity)).first);
    expect(opacityOf().opacity, 0.5);
    expect(
        r.container.read(cartDebtSettlementProvider(kMainCartId)), isEmpty);

    await tester.tap(rowFinder);
    await tester.pumpAndSettle();

    expect(opacityOf().opacity, 1.0);
    final entries = r.container.read(cartDebtSettlementProvider(kMainCartId));
    expect(entries, hasLength(1));
    expect(entries.single.customerId, 'c1');
    expect(entries.single.amount, 30000);
    expect(entries.single.targetInvoices, hasLength(1));
    expect(entries.single.targetInvoices.single.invoiceLocalId, 'A1-0007');
    expect(entries.single.targetInvoices.single.amount, 30000);

    // Tap lagi -> batal, entri terhapus, kembali pudar.
    await tester.tap(rowFinder);
    await tester.pumpAndSettle();
    expect(opacityOf().opacity, 0.5);
    expect(
        r.container.read(cartDebtSettlementProvider(kMainCartId)), isEmpty);
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
