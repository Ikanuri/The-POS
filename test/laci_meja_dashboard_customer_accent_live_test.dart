import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';

/// Item 82 — bug dilaporkan user: pre-order (atau titip/pinjaman) yang
/// dibuat SAAT nota rujukannya masih pakai pembeli ad-hoc, LALU notanya
/// diubah ke pelanggan terdaftar (fitur "Ganti Pelanggan",
/// `changeTransactionCustomer`) -- nama sudah benar ikut ter-koreksi
/// (sesi sebelumnya, `getCustomerNamesForTransactions`), TAPI ikon/aksen
/// "pelanggan tetap vs ad-hoc" tetap tampil ad-hoc SELAMANYA krn
/// `customerId` di baris Laci Meja itu sendiri adalah salinan BEKU yang
/// tidak pernah ikut di-update.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/laci-meja',
      routes: [
        GoRoute(
          path: '/laci-meja',
          builder: (_, __) => const LaciMejaDashboardScreen(),
        ),
        GoRoute(
          path: '/kasir/struk/:txId',
          builder: (_, state) => Scaffold(
              body: Text('Layar Struk ${state.pathParameters['txId']}')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()
          ..state = const DeviceIdentity(
            storeUuid: 'test-store-uuid',
            storeKey: 'test-store-key',
            storeName: 'Toko Uji',
            deviceName: 'HP Owner',
            deviceCode: 'K1',
            deviceRole: 'owner',
          )),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  testWidgets(
      'nota diubah ke pelanggan terdaftar (changeTransactionCustomer) SETELAH '
      'entri Laci Meja dicatat -> ikon/aksen kartu ikut jadi "terdaftar", '
      'BUKAN tetap ad-hoc selamanya', (tester) async {
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Bu Sri',
          address: const Value('Jl. Melati 12'),
        ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          // Ad-hoc SAAT nota dibuat -- belum ditautkan ke pelanggan terdaftar.
          customerName: const Value('Sri'),
        ));
    // Entri Laci Meja dicatat SAAT nota masih ad-hoc -> customerId beku null.
    await db.addLeftBehindItem(
        id: 'l1', transactionId: 'tx1', itemName: 'Galon Aqua', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person_outline), findsOneWidget,
        reason: 'prakondisi: saat nota masih ad-hoc, kartu tampil ad-hoc');
    expect(find.byIcon(Icons.person), findsNothing);

    // Owner memakai "Ganti Pelanggan" -- menautkan nota ke pelanggan
    // terdaftar. Entri Laci Meja `customerId`-nya SENDIRI TIDAK disentuh
    // sama sekali (persis root cause bug ini).
    await db.changeTransactionCustomer(
        txId: 'tx1', newCustomerId: 'c1', newCustomerName: null);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.person), findsOneWidget,
        reason: 'tanpa fix, ikon tetap ad-hoc (person_outline) selamanya '
            'walau nota SEKARANG sudah tertaut pelanggan terdaftar');
    expect(find.byIcon(Icons.person_outline), findsNothing);
    expect(find.text('Jl. Melati 12'), findsOneWidget,
        reason: 'alamat pelanggan terdaftar yg BARU ditautkan juga harus '
            'ikut tampil, bukan cuma ikon');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
