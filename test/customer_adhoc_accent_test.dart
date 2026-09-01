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

/// Permintaan user: bedakan secara visual pelanggan TERDAFTAR dari nama
/// ad-hoc (yang cuma diketik saat itu, tanpa record `Customers`). Sinyalnya
/// `customerId`: terisi = terdaftar, null = ad-hoc.
///
/// Bedanya nyata saat menagih wadah/pre-order: yang ad-hoc tidak punya
/// riwayat/hutang yang bisa ditelusuri, dan tidak pernah tersinkron ke owner.
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
            builder: (_, __) => const LaciMejaDashboardScreen()),
        GoRoute(
            path: '/kasir/struk/:txId',
            builder: (_, state) =>
                Scaffold(body: Text('Struk ${state.pathParameters['txId']}'))),
      ],
    );
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> seedTx(String id) =>
      db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: id,
            status: 'lunas',
            total: 10000,
            paid: 10000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));

  testWidgets(
      'kartu Laci Meja: NAMA pelanggan terdaftar juga ikut aksen terracotta '
      '(bukan cuma ikonnya), ad-hoc pakai ikon garis + warna netral',
      (tester) async {
    await seedTx('tx1');
    await seedTx('tx2');
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'C1', name: 'Bu Ani Terdaftar'));
    await db.into(db.leftBehindItems).insert(LeftBehindItemsCompanion.insert(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Galon',
          jenis: 'titip',
          customerId: const Value('C1'),
          customerNameText: const Value('Bu Ani Terdaftar'),
          createdAt: Value(DateTime(2026, 1, 1)),
        ));
    await db.into(db.leftBehindItems).insert(LeftBehindItemsCompanion.insert(
          id: 'l2',
          transactionId: 'tx2',
          itemName: 'Payung',
          jenis: 'titip',
          customerNameText: const Value('Orang lewat'),
          createdAt: Value(DateTime(2026, 1, 2)),
        ));

    await tester.pumpWidget(buildApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final terisi = tester
        .widgetList<Icon>(find.byIcon(Icons.person))
        .where((i) => i.color == AppTheme.accent)
        .length;
    final garis = find.byIcon(Icons.person_outline).evaluate().length;
    // Nama pelanggan sendiri (header kartu, bukan ikonnya) — permintaan
    // user susulan: aksen jangan cuma di ikon kecil yang gampang terlewat.
    final namaTerdaftarBeraksen = tester
        .widgetList<Text>(find.text('Bu Ani Terdaftar'))
        .where((t) => t.style?.color == AppTheme.accent)
        .length;
    final namaAdhocBeraksen = tester
        .widgetList<Text>(find.text('Orang lewat'))
        .where((t) => t.style?.color == AppTheme.accent)
        .length;

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));

    expect(terisi, 1,
        reason: 'satu kartu pelanggan terdaftar -> ikon terisi + aksen');
    expect(garis, 1, reason: 'satu kartu nama ad-hoc -> ikon garis');
    expect(namaTerdaftarBeraksen, 1,
        reason: 'teks nama pelanggan terdaftar harus ikut warna aksen');
    expect(namaAdhocBeraksen, 0,
        reason: 'teks nama ad-hoc TIDAK boleh ikut aksen');
  });

  test('pre-order menyimpan customerId supaya bisa dibedakan juga', () async {
    await seedTx('tx1');
    await db.addPreorderEntry(
      id: 'po1',
      productId: 'P1',
      productUnitId: 'U1',
      customerName: 'Bu Ani',
      qtyOrdered: 1,
      transactionId: 'tx1',
      customerId: 'C1',
    );
    final row = await db.select(db.preorderEntries).getSingle();
    expect(row.customerId, 'C1',
        reason: 'sebelum ini pre-order HANYA menyimpan nama teks, sehingga '
            'pelanggan terdaftar & ad-hoc tidak bisa dibedakan sama sekali');
  });
}
