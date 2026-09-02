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
import 'package:the_pos/features/laci_meja/riwayat_laci_meja_screen.dart';

/// PLAN.md Item 54 poin 1 & 5 (sisi UI):
///  • ambil/penuhi SEBAGIAN lewat dialog qty, sisa tetap menggantung;
///  • layar "Riwayat" gabungan ketiga kategori.
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
        GoRoute(
          path: '/kasir/laci-meja/riwayat',
          builder: (_, __) => const RiwayatLaciMejaScreen(),
        ),
      ],
    );
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> seedTx(String id, {String name = 'Bu Rina'}) =>
      db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerName: Value(name),
        ),
      );

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('Ambil sebagian (poin 1)', () {
    testWidgets('titip qty 5: tombol Ambil membuka dialog, ambil 3 -> entri '
        'TETAP di daftar dgn progres "Diambil 3 dari 5"', (tester) async {
      // Selebar HP asli — dialog dgn 2 tombol wajib muat (gotcha CLAUDE.md).
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Gas LPG 3kg',
          jenis: 'titip',
          qty: 5);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ambil'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sisa belum diambil: 5 dari 5'), findsOneWidget,
          reason: 'dialog menyebut sisa sbg konteks');

      await tester.enterText(find.byType(TextField), '3');
      await tester.tap(find.widgetWithText(FilledButton, 'Ambil'));
      await tester.pumpAndSettle();

      // Entri belum selesai -> masih tampil.
      expect(find.textContaining('Gas LPG 3kg'), findsOneWidget);
      expect(find.textContaining('Diambil 3 dari 5'), findsOneWidget);

      final row = await (db.select(db.leftBehindItems)
            ..where((t) => t.id.equals('l1')))
          .getSingle();
      expect(row.collectedAt, isNull);

      await drain(tester);
    });

    testWidgets('mengambil SISA terakhir menutup entri -> hilang dari daftar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Gas LPG 3kg',
          jenis: 'titip',
          qty: 5);
      await db.collectLeftBehindQty('l1', 3, total: 5, eventId: 'e1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(find.textContaining('Diambil 3 dari 5'), findsOneWidget);

      await tester.tap(find.text('Ambil'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Ambil'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Gas LPG 3kg'), findsNothing,
          reason: 'sudah diambil semua -> keluar dari daftar menggantung');

      await drain(tester);
    });

    testWidgets('qty 1: LANGSUNG diambil tanpa dialog (tidak ada yang bisa '
        'dipecah)', (tester) async {
      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          qty: 1);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambil'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing,
          reason: 'dialog cuma langkah ekstra sia-sia utk qty 1');
      expect(find.textContaining('Payung'), findsNothing);

      await drain(tester);
    });

    testWidgets('input melebihi sisa dipotong ke sisa, tidak jadi minus',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Gas LPG 3kg',
          jenis: 'titip',
          qty: 5);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ambil'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '99');
      await tester.tap(find.widgetWithText(FilledButton, 'Ambil'));
      await tester.pumpAndSettle();

      expect((await db.getLaciMejaTakenQty(['l1']))['l1'], 5,
          reason: 'dipotong ke sisa (5), bukan 99');

      await drain(tester);
    });
  });

  group('Layar Riwayat (poin 5, kini layar arsip terpisah)', () {
    testWidgets('ikon Riwayat membuka layar arsip Riwayat Laci Meja (rute '
        'terpisah, bukan toggle inline)', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.text('Riwayat Laci Meja'), findsOneWidget);
      // 3 tab kategori terpisah (permintaan user "pisahkan ketiga kategori").
      expect(find.text('Titip/Ketinggalan'), findsOneWidget);
      expect(find.text('Pinjaman'), findsOneWidget);
      expect(find.text('Pre-order'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('entri yang SUDAH SELESAI tetap tampil di riwayat (beda dari '
        'dashboard yang cuma tampilkan yang masih terbuka)', (tester) async {
      await seedTx('tx1');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          qty: 1);
      await db.collectLeftBehindQty('l1', 1, total: 1, eventId: 'e1');
      await db.markLeftBehindCollected('l1', sisaQty: 0, eventId: 'e1b');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Dashboard (tab default Titip/Ketinggalan) TIDAK menampilkannya lagi
      // -- sudah selesai.
      expect(find.textContaining('Payung'), findsNothing);

      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.textContaining('Payung'), findsOneWidget);
      expect(find.textContaining('Selesai'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('belum ada riwayat sama sekali -> pesan kosong per tab',
        (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.textContaining('Belum ada riwayat'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('pencarian menyaring baris sesuai nama pelanggan/nama barang',
        (tester) async {
      await seedTx('tx1');
      await seedTx('tx2', name: 'Pak Budi');
      await db.addLeftBehindItem(
          id: 'l1',
          transactionId: 'tx1',
          itemName: 'Payung',
          jenis: 'titip',
          qty: 1);
      await db.addLeftBehindItem(
          id: 'l2',
          transactionId: 'tx2',
          itemName: 'Topi',
          jenis: 'ketinggalan',
          qty: 1);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      expect(find.textContaining('Payung'), findsOneWidget);
      expect(find.textContaining('Topi'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Payung');
      await tester.pumpAndSettle();

      // 2 kemunculan "Payung": teks yg baru diketik di kotak pencarian itu
      // sendiri, + baris kartu yg lolos filter (Topi sudah tersaring habis).
      expect(find.textContaining('Payung'), findsNWidgets(2));
      expect(find.textContaining('Topi'), findsNothing);

      await drain(tester);
    });

    testWidgets('tab Pre-order: filter produk menyaring hanya entri produk '
        'terpilih', (tester) async {
      await seedTx('tx1');
      await db.into(db.products)
          .insert(ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
      await db.into(db.products)
          .insert(ProductsCompanion.insert(id: 'P2', name: 'Beras 25kg'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U2', productId: 'P2', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Rina',
          qtyOrdered: 4,
          transactionId: 'tx1');
      await db.addPreorderEntry(
          id: 'p2',
          productId: 'P2',
          productUnitId: 'U2',
          customerName: 'Bu Rina',
          qtyOrdered: 2,
          transactionId: 'tx1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.history));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();

      // Cek isi KARTU (bukan seluruh layar) — chip filter produk juga
      // menyebut nama produk yg sama, jadi textContaining biasa akan
      // ganda-hitung chip + kartu.
      Finder cardWith(String text) => find.ancestor(
          of: find.textContaining(text), matching: find.byType(Card));

      expect(cardWith('Gas LPG 3kg'), findsOneWidget);
      expect(cardWith('Beras 25kg'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Gas LPG 3kg'));
      await tester.pumpAndSettle();

      expect(cardWith('Gas LPG 3kg'), findsOneWidget);
      expect(cardWith('Beras 25kg'), findsNothing);

      await drain(tester);
    });
  });
}
