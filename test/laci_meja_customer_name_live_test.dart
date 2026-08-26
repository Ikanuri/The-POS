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

/// Dilaporkan user: pre-order LPG dicatat saat nota masih memakai pembeli
/// ad-hoc, lalu notanya diubah ke pelanggan terdaftar — di Laci Meja namanya
/// TETAP yang lama. Berlaku utk ketiga kategori (titip/ketinggalan, pinjaman,
/// pre-order): ketiganya menyimpan nama pelanggan sbg SALINAN BEKU saat entri
/// dibuat, tidak pernah dicap ulang saat nota berubah.
///
/// Sekaligus menguji redesain kartu (permintaan user putaran yang sama):
/// baris ke-1 nama pelanggan (H1), ke-2 barang+qty, ke-3 timestamp dgn format
/// PERSIS spt kartu Riwayat Pembayaran (`dd/MM/yyyy HH:mm`).
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
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  /// Nota dgn pembeli ad-hoc (`customerName`), persis kondisi awal kasus user.
  Future<void> seedAdHocTx(String id, String adHocName) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerName: Value(adHocName),
        ));
  }

  /// Owner mengubah nota dari pembeli ad-hoc ke pelanggan TERDAFTAR.
  Future<void> switchTxToRegisteredCustomer(
      String txId, String customerId, String name) async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: customerId, name: name));
    await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
        .write(TransactionsCompanion(customerId: Value(customerId)));
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('AppDatabase.getCustomerNamesForTransactions (DB murni)', () {
    test('pelanggan TERDAFTAR menang atas kolom customerName nota', () async {
      await seedAdHocTx('tx1', 'Nama Ad-hoc Lama');
      await switchTxToRegisteredCustomer('tx1', 'c1', 'Warung Sari');

      final names = await db.getCustomerNamesForTransactions(['tx1']);
      expect(names['tx1'], 'Warung Sari',
          reason: 'customerId terisi -> customerName nota diabaikan');
    });

    test('nota ad-hoc (tanpa customerId) memakai customerName', () async {
      await seedAdHocTx('tx1', 'Bu Rina');
      final names = await db.getCustomerNamesForTransactions(['tx1']);
      expect(names['tx1'], 'Bu Rina');
    });

    test('nota tanpa nama apa pun TIDAK masuk hasil (biar pemanggil '
        'jatuh ke cadangannya sendiri)', () async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx1',
            localId: 'tx1',
            status: 'lunas',
            total: 1000,
            paid: 1000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));
      final names = await db.getCustomerNamesForTransactions(['tx1']);
      expect(names.containsKey('tx1'), isFalse);
    });

    test('daftar kosong -> map kosong, tidak query', () async {
      expect(await db.getCustomerNamesForTransactions([]), isEmpty);
    });
  });

  group('Dashboard menampilkan nama TERKINI dari nota (bug user)', () {
    testWidgets('Pre-order: nota diubah ad-hoc -> pelanggan terdaftar, '
        'kartu ikut berubah (bukan nama beku saat dicatat)', (tester) async {
      await seedAdHocTx('tx1', 'Pelanggan Umum');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      // Snapshot beku ikut nama LAMA — persis yang terjadi di lapangan.
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Pelanggan Umum',
          qtyOrdered: 5,
          transactionId: 'tx1');

      await switchTxToRegisteredCustomer('tx1', 'c1', 'Warung Sari');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapTab(tester, 'Pre-order');

      expect(find.text('Warung Sari'), findsOneWidget,
          reason: 'nama dibaca hidup dari nota rujukan');
      expect(find.text('Pelanggan Umum'), findsNothing,
          reason: 'salinan beku yang sudah basi tidak boleh tampil lagi');

      await drain(tester);
    });

    testWidgets('Titip/Ketinggalan: ikut nama terkini nota', (tester) async {
      await seedAdHocTx('tx1', 'Pelanggan Umum');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          customerNameText: 'Pelanggan Umum');

      await switchTxToRegisteredCustomer('tx1', 'c1', 'Bu Rina');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Bu Rina'), findsOneWidget);
      expect(find.text('Pelanggan Umum'), findsNothing);

      await drain(tester);
    });

    testWidgets('Pinjaman: ikut nama terkini nota', (tester) async {
      await seedAdHocTx('tx1', 'Pelanggan Umum');
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: 'tx1',
          itemName: 'Krat botol',
          qty: 4,
          customerNameText: 'Pelanggan Umum');

      await switchTxToRegisteredCustomer('tx1', 'c1', 'Pak Budi');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapTab(tester, 'Pinjaman');

      expect(find.text('Pak Budi'), findsOneWidget);
      expect(find.text('Pelanggan Umum'), findsNothing);

      await drain(tester);
    });

    testWidgets('nota TANPA nama sama sekali -> jatuh ke salinan beku lama, '
        'bukan jadi "Umum"', (tester) async {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: 'tx1',
            localId: 'tx1',
            status: 'lunas',
            total: 1000,
            paid: 1000,
            changeAmount: 0,
            paymentMethod: 'tunai',
          ));
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          customerNameText: 'Bu Ani');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Bu Ani'), findsOneWidget,
          reason: 'cadangan salinan beku tetap dipakai kalau nota tidak '
              'punya nama apa pun');

      await drain(tester);
    });
  });

  group('Redesain kartu: 3 tingkat (nama / barang+qty / timestamp)', () {
    testWidgets('timestamp tampil dgn format sama spt Riwayat Pembayaran '
        '(dd/MM/yyyy HH:mm)', (tester) async {
      await seedAdHocTx('tx1', 'Bu Rina');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          customerNameText: 'Bu Rina');

      final row = await (db.select(db.leftBehindItems)
            ..where((t) => t.id.equals('l1')))
          .getSingle();
      final at = row.createdAt;
      final expected = '${at.day.toString().padLeft(2, '0')}/'
          '${at.month.toString().padLeft(2, '0')}/'
          '${at.year} '
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}';

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.textContaining(expected, findRichText: true), findsOneWidget,
          reason: 'baris ke-3 memuat timestamp absolut, bukan cuma "N hari lalu"');
      // Umur relatif berwarna TETAP dipertahankan di baris yang sama.
      expect(find.textContaining('hari lalu', findRichText: true),
          findsOneWidget);

      await drain(tester);
    });

    testWidgets('nama pelanggan (H1) lebih besar & lebih tebal dari baris '
        'barang (H2)', (tester) async {
      await seedAdHocTx('tx1', 'Bu Rina');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          customerNameText: 'Bu Rina');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final h1 = tester.widget<Text>(find.text('Bu Rina'));
      final h2 = tester.widget<Text>(find.text('Payung'));
      expect(h1.style!.fontSize!, greaterThan(h2.style!.fontSize!),
          reason: 'nama pelanggan = H1, nama barang = H2');
      expect(h1.style!.fontWeight!.index, greaterThan(h2.style!.fontWeight!.index),
          reason: 'H1 lebih tebal dari H2');

      await drain(tester);
    });
  });
}
