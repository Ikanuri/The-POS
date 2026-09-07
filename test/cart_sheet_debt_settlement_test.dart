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

/// Fitur "Lunasi Hutang" — REDESAIN KEDUA (permintaan user, gantikan toggle
/// boolean tunggal dari redesain PERTAMA `a254152`): entry point sekarang
/// chip pengingat hutang di dalam `CartSheet` (tap -> sheet "Pilih Nota
/// untuk Dilunasi", checklist SEMUA nota tempo/kurang_bayar pelanggan +
/// "Centang Semua"). SETIAP nota yang dicentang & "Terapkan" jadi SATU
/// entri TERPISAH di keranjang (bukan lagi satu entri agregat SELURUH
/// hutang) — bisa banyak sekaligus, partial per-nota (uncentang sebagian).
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

  Future<void> seedCustomer(AppDatabase db,
      {required String customerId, required String customerName}) async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: customerId, name: customerName));
  }

  Future<void> seedInvoice(AppDatabase db,
      {required String customerId,
      required String invoiceId,
      required int total,
      required int paid,
      DateTime? createdAt}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: invoiceId,
          localId: invoiceId,
          status: 'kurang_bayar',
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: Value(customerId),
          createdAt:
              Value(createdAt ?? DateTime.now().subtract(const Duration(days: 3))),
        ));
  }

  final chipFinder = find.textContaining('Hutang');

  testWidgets('pelanggan TANPA hutang -> chip pengingat TIDAK muncul',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari');
    addTearDown(() async => r.db.close());
    expect(chipFinder, findsNothing);
  });

  testWidgets(
      'keranjang TANPA pelanggan terikat -> chip TIDAK muncul walau ada '
      'pelanggan LAIN yang berhutang', (tester) async {
    final r = await pumpCartSheetOpen(
      tester,
      deviceRole: 'owner',
      terimaPembayaran: true,
      // Tidak set customer di cart meta sama sekali.
      seed: (db) async {
        await seedCustomer(db, customerId: 'c1', customerName: 'Sari');
        await seedInvoice(db,
            customerId: 'c1', invoiceId: 'A1-0007', total: 50000, paid: 20000);
      },
    );
    addTearDown(() async => r.db.close());
    expect(chipFinder, findsNothing);
  });

  testWidgets(
      'pegawai TANPA izin terima_pembayaran -> chip TIDAK muncul walau '
      'pelanggan terikat punya hutang', (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'kasir',
        terimaPembayaran: false,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) async {
          await seedCustomer(db, customerId: 'c1', customerName: 'Sari');
          await seedInvoice(db,
              customerId: 'c1',
              invoiceId: 'A1-0007',
              total: 50000,
              paid: 20000);
        });
    addTearDown(() async => r.db.close());
    expect(chipFinder, findsNothing);
  });

  testWidgets(
      'tap chip -> sheet pilih nota, Centang Semua -> Terapkan -> SETIAP '
      'nota jadi entri TERPISAH, Total keranjang naik', (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) async {
          await seedCustomer(db, customerId: 'c1', customerName: 'Sari');
          await seedInvoice(db,
              customerId: 'c1',
              invoiceId: 'A1-0007',
              total: 50000,
              paid: 20000, // sisa 30000
              createdAt: DateTime(2026, 1, 1));
          await seedInvoice(db,
              customerId: 'c1',
              invoiceId: 'A1-0009',
              total: 40000,
              paid: 0, // sisa 40000
              createdAt: DateTime(2026, 2, 1));
        });
    addTearDown(() async => r.db.close());

    expect(chipFinder, findsOneWidget);
    expect(
        r.container.read(cartDebtSettlementProvider(kMainCartId)), isEmpty);

    await tester.tap(chipFinder);
    await tester.pumpAndSettle();

    expect(find.text('Pilih Nota untuk Dilunasi'), findsOneWidget);
    expect(find.text('Nota A1-0007'), findsOneWidget);
    expect(find.text('Nota A1-0009'), findsOneWidget);

    await tester.tap(find.text('Centang Semua'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    final entries = r.container.read(cartDebtSettlementProvider(kMainCartId));
    expect(entries, hasLength(2));
    expect(entries.map((e) => e.invoiceLocalId).toSet(),
        {'A1-0007', 'A1-0009'});
    expect(entries.firstWhere((e) => e.invoiceLocalId == 'A1-0007').amount,
        30000);
    expect(entries.firstWhere((e) => e.invoiceLocalId == 'A1-0009').amount,
        40000);

    // Tiap nota tercentang jadi baris TERPISAH di keranjang (bukan
    // digabung 1 baris agregat).
    expect(find.text('Nota A1-0007'), findsOneWidget);
    expect(find.text('Nota A1-0009'), findsOneWidget);

    // Total naik = belanja (2 x 15000 = 30000) + 30000 + 40000 = 100000.
    expect(find.text(formatRupiah(100000)), findsOneWidget);
  });

  testWidgets(
      'partial selection: uncentang 1 dari 2 nota -> HANYA nota tercentang '
      'jadi entri', (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) async {
          await seedCustomer(db, customerId: 'c1', customerName: 'Sari');
          await seedInvoice(db,
              customerId: 'c1',
              invoiceId: 'A1-0007',
              total: 50000,
              paid: 20000,
              createdAt: DateTime(2026, 1, 1));
          await seedInvoice(db,
              customerId: 'c1',
              invoiceId: 'A1-0009',
              total: 40000,
              paid: 0,
              createdAt: DateTime(2026, 2, 1));
        });
    addTearDown(() async => r.db.close());

    await tester.tap(chipFinder);
    await tester.pumpAndSettle();

    // Centang HANYA nota A1-0007 (checkbox di baris nota itu).
    await tester.tap(find.ancestor(
        of: find.text('Nota A1-0007'), matching: find.byType(CheckboxListTile)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    final entries = r.container.read(cartDebtSettlementProvider(kMainCartId));
    expect(entries, hasLength(1));
    expect(entries.single.invoiceLocalId, 'A1-0007');
    expect(entries.single.amount, 30000);
  });

  testWidgets('tap baris entri di keranjang -> entri dihapus, Total turun',
      (tester) async {
    final r = await pumpCartSheetOpen(tester,
        deviceRole: 'owner',
        terimaPembayaran: true,
        customerId: 'c1',
        customerName: 'Sari',
        seed: (db) async {
          await seedCustomer(db, customerId: 'c1', customerName: 'Sari');
          await seedInvoice(db,
              customerId: 'c1',
              invoiceId: 'A1-0007',
              total: 50000,
              paid: 20000,
              createdAt: DateTime(2026, 1, 1));
        });
    addTearDown(() async => r.db.close());

    await tester.tap(chipFinder);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Centang Semua'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();

    expect(
        r.container.read(cartDebtSettlementProvider(kMainCartId)), hasLength(1));
    // Total = 30000 (belanja) + 30000 (hutang) = 60000.
    expect(find.text(formatRupiah(60000)), findsOneWidget);

    await tester.tap(find.text('Nota A1-0007'));
    await tester.pumpAndSettle();

    expect(
        r.container.read(cartDebtSettlementProvider(kMainCartId)), isEmpty);
    // Baris entri hutang & breakdown "+ Lunasi Hutang" ikut hilang —
    // "Rp 30.000" masih ada (subtotal item belanja, kebetulan sama nilainya
    // dgn hutang yg tadi dihapus), jadi verifikasi lewat ABSENnya breakdown/
    // baris nota, bukan hitung ulang match teks nominal (ambigu, > 1 match).
    expect(find.textContaining('Lunasi Hutang'), findsNothing);
    expect(find.text('Nota A1-0007'), findsNothing);
  });
}
