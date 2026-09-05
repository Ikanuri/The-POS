import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';
import 'package:the_pos/features/laporan/tabs/transaksi_tab.dart';

/// Item 63 (permintaan user) — nota void kini TETAP terlihat di Laporan ->
/// Transaksi (dulu difilter hilang total oleh `watchTransactions`), dan tap
/// nota (void ATAU tidak) membuka `ReceiptScreen` (struk asli lengkap),
/// bukan sheet ringkasan tipis lama.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/laporan',
      routes: [
        GoRoute(
          path: '/laporan',
          builder: (_, __) => Scaffold(
            body: TransaksiTab(
              range: DateTimeRange(
                start: DateTime.now().subtract(const Duration(days: 1)),
                end: DateTime.now().add(const Duration(days: 1)),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/kasir/struk/:txId',
          builder: (_, state) =>
              ReceiptScreen(transactionId: state.pathParameters['txId']!),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider
            .overrideWith((ref) => DeviceNotifier()..state = const DeviceIdentity(
                  storeUuid: 's',
                  storeKey: 'k',
                  storeName: 'Toko Uji',
                  deviceName: 'Kasir Uji',
                  deviceCode: 'K1',
                  deviceRole: 'owner',
                )),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> seedVoidedTx() async {
    final now = DateTime.now();
    await db.saveTransaction(
      tx: TransactionsCompanion.insert(
        id: 'tx1',
        localId: 'K1-VOID-1',
        status: 'lunas',
        total: 15000,
        paid: 15000,
        changeAmount: 0,
        paymentMethod: 'tunai',
        createdAt: Value(now),
      ),
      items: [
        TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 15000,
          originalPrice: 15000,
          subtotal: 15000,
        ),
      ],
      payments: [
        TransactionPaymentsCompanion.insert(
          id: 'p1',
          transactionId: 'tx1',
          amount: 15000,
          method: 'tunai',
          paidAt: Value(now),
        ),
      ],
      stockItems: const [],
      now: now,
    );
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Minyak Goreng 1L'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.voidTransaction('tx1', 'K1', reason: 'Salah scan barang');
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'nota void tampil di daftar dgn badge VOID + total dicoret '
      '(dulu difilter hilang total)', (tester) async {
    await seedVoidedTx();

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('VOID'), findsOneWidget,
        reason: 'watchTransactions(includeVoid: true) harus mengikutsertakan '
            'nota void, badge VOID yang sudah ada di _TxTile kini terpicu');

    final totalText =
        tester.widget<Text>(find.text(formatRupiah(15000)).first);
    expect(totalText.style?.decoration, TextDecoration.lineThrough,
        reason: 'total nota void dicoret');

    await drain(tester);
  });

  testWidgets(
      'tap nota void membuka ReceiptScreen (bukan sheet ringkasan lama) & '
      'menampilkan item asli', (tester) async {
    await seedVoidedTx();

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('K1-VOID-1'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(ReceiptScreen), findsOneWidget,
        reason: 'tap nota harus navigasi ke ReceiptScreen (bukan sheet '
            'ringkasan lama)');
    expect(
        find.textContaining('Minyak Goreng 1L', findRichText: true),
        findsOneWidget,
        reason: 'struk asli menampilkan item nota, bukan sheet ringkasan '
            'tipis lama yang cuma Total/Dibayar/Metode');
    expect(find.textContaining('dibatalkan'), findsOneWidget,
        reason: 'ReceiptScreen menampilkan banner isVoid');
    expect(find.textContaining('Salah scan barang'), findsOneWidget,
        reason: 'alasan void tersimpan & tampil di struk');
    expect(find.textContaining('Dibatalkan oleh: K1'), findsOneWidget,
        reason: 'siapa yang membatalkan (voidedBy) tampil di struk');

    await drain(tester);
  });
}
