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

/// Item 52 susulan (permintaan user, screenshot device asli): barang
/// titip/ketinggalan dari NOTA YANG SAMA harus dikumpulkan jadi SATU
/// "frame" (Card), bukan baris rata terpisah — dan tiap baris menampilkan
/// qty + satuan produknya.

/// Cari `TextSpan` dgn teks PERSIS [text] di dalam pohon span (rekursif) —
/// dipakai utk verifikasi bold parsial di `Text.rich`, krn `Text.rich(span)`
/// SELALU membungkus [span] jadi child TextSpan luar (gaya default tema),
/// jadi style span kita ada di kedalaman >=2, bukan di `RichText.text` langsung.
TextSpan? _findSpanWithText(InlineSpan span, String text) {
  if (span is TextSpan) {
    if (span.text == text) return span;
    if (span.children != null) {
      for (final child in span.children!) {
        final found = _findSpanWithText(child, text);
        if (found != null) return found;
      }
    }
  }
  return null;
}

TextSpan? findBoldableSpan(WidgetTester tester, String text, {Finder? of}) {
  final scope = of == null
      ? find.byType(RichText)
      : find.descendant(of: of, matching: find.byType(RichText));
  for (final rt in tester.widgetList<RichText>(scope)) {
    final found = _findSpanWithText(rt.text, text);
    if (found != null) return found;
  }
  return null;
}

/// Jumlah baris entri di dalam [of] — redesain kartu (nama pelanggan jadi
/// header, barang+qty turun ke baris ke-2, timestamp baris ke-3) membuat
/// `ListTile` tidak lagi dipakai; peran "satu baris entri" sekarang dipegang
/// `_EntryRow`. Pola pencocokan lewat `runtimeType.toString()` sama dgn
/// `_MetaTabDivider`/`_VariantRow` di test lain.
Finder findEntryRows({Finder? of}) {
  final matcher = find
      .byWidgetPredicate((w) => w.runtimeType.toString() == '_EntryRow');
  return of == null ? matcher : find.descendant(of: of, matching: matcher);
}

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

  Future<void> seedTransaction(String id) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
  }

  testWidgets(
      '2 barang dari NOTA SAMA dikumpulkan jadi 1 Card (frame); nota lain '
      'jadi Card terpisah', (tester) async {
    await seedTransaction('tx1');
    await seedTransaction('tx2');
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 2,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 10000));
    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Galon Aqua',
        jenis: 'titip',
        transactionItemId: 'i1');
    await db.addLeftBehindItem(
        id: 'l2', transactionId: 'tx1', itemName: 'Payung', jenis: 'ketinggalan');
    await db.addLeftBehindItem(
        id: 'l3', transactionId: 'tx2', itemName: 'Topi', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(Card), findsNWidgets(2),
        reason: '2 nota berbeda -> 2 frame (Card), bukan 3 baris rata');

    // Card pertama (tx1) berisi 2 baris entri (Galon Aqua + Payung).
    final firstCard = find.byType(Card).first;
    expect(findEntryRows(of: firstCard), findsNWidgets(2),
        reason: '2 barang dari nota yg SAMA harus 1 frame berisi 2 baris');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'barang yang tertaut transactionItemId menampilkan qty+satuan; yang '
      'tidak tertaut (entri lama) tidak menampilkan apa pun tambahan',
      (tester) async {
    await seedTransaction('tx1');
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Galon Aqua Produk'));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(99), name: 'Pak'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1',
        productId: 'P1',
        isBaseUnit: const Value(true),
        unitTypeId: const Value(99)));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 3,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 15000));

    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Galon Aqua',
        jenis: 'titip',
        transactionItemId: 'i1');
    await db.addLeftBehindItem(
        id: 'l2',
        transactionId: 'tx1',
        itemName: 'Payung Lama',
        jenis: 'ketinggalan');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Galon Aqua ·'), findsOneWidget,
        reason: 'barang tertaut transactionItemId harus tampilkan qty+satuan');
    expect(find.text('Payung Lama'), findsOneWidget,
        reason: 'entri lama tanpa tautan tetap tampil apa adanya, tanpa qty');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'susulan (permintaan user): qty SEBAGIAN (stepper) tampil, BUKAN qty '
      'penuh baris nota', (tester) async {
    await seedTransaction('tx1');
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Galon Aqua Produk'));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(99), name: 'Pak'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1',
        productId: 'P1',
        isBaseUnit: const Value(true),
        unitTypeId: const Value(99)));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 3, // beli 3, yang ketinggalan cuma 2 (SEBAGIAN)
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 15000));

    await db.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Galon Aqua',
        jenis: 'ketinggalan',
        transactionItemId: 'i1',
        qty: 2);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Galon Aqua · 2 Pak'), findsOneWidget,
        reason: 'qty SEBAGIAN (2) yg ditampilkan, bukan qty penuh baris '
            'nota (3)');
    expect(find.textContaining('3 Pak'), findsNothing,
        reason: 'qty penuh baris nota TIDAK boleh muncul menggantikan qty '
            'sebagian');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('tombol "Ambil" (redesain minimalis) menandai barang diambil',
      (tester) async {
    await seedTransaction('tx1');
    await db.addLeftBehindItem(
        id: 'l1', transactionId: 'tx1', itemName: 'Galon Aqua', jenis: 'titip');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Sudah Diambil'), findsNothing,
        reason: 'label lama dihapus, redesain minimalis');
    expect(find.text('Ambil'), findsOneWidget);

    await tester.tap(find.text('Ambil'));
    await tester.pumpAndSettle();

    expect(find.text('Galon Aqua'), findsNothing,
        reason: 'setelah diambil, baris hilang dari daftar yg menggantung');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  group('Pre-order (permintaan user putaran terbaru)', () {
    Future<void> tapPreorderTab(WidgetTester tester) async {
      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        '2 produk pre-order dari NOTA SAMA jadi 1 Card, header nama '
        'pelanggan (bold), tiap baris "[qty] [produk] - [jaminan]"',
        (tester) async {
      await seedTransaction('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Galon Aqua'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.into(db.products)
          .insert(ProductsCompanion.insert(id: 'P2', name: 'Tabung Gas'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U2', productId: 'P2', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Artia',
          qtyOrdered: 2,
          transactionId: 'tx1');
      await db.addPreorderEntry(
          id: 'p2',
          productId: 'P2',
          productUnitId: 'U2',
          customerName: 'Bu Artia',
          qtyOrdered: 1,
          depositQty: 1,
          transactionId: 'tx1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPreorderTab(tester);

      expect(find.byType(Card), findsOneWidget,
          reason: '2 produk pre-order NOTA SAMA -> 1 frame, tidak kocar-kacir');
      expect(find.text('Bu Artia'), findsOneWidget,
          reason: 'header nama pelanggan tampil SEKALI per grup');
      // Redesain (permintaan user): nama pelanggan naik jadi baris ke-1 "H1"
      // — sengaja LEBIH tebal & lebih besar dari baris barang di bawahnya
      // (dulu sama-sama w700), jadi assersi lama sudah tidak berlaku.
      final header = tester.widget<Text>(find.text('Bu Artia'));
      expect(header.style?.fontWeight, FontWeight.w800,
          reason: 'header nama pelanggan = H1, lebih tebal dari baris barang');
      expect(header.style?.fontSize, greaterThan(13.5),
          reason: 'H1 harus lebih besar dari baris barang (13.5)');
      expect(
          find.textContaining('2 Galon Aqua', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('1 Tabung Gas - 1 jaminan', findRichText: true),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'qty & nama produk di baris rincian item BOLD, sisa baris (jaminan, '
        'status bayar) TIDAK bold (permintaan user)', (tester) async {
      await seedTransaction('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Galon Aqua'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Artia',
          qtyOrdered: 2,
          depositQty: 1,
          transactionId: 'tx1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPreorderTab(tester);

      final boldSpan = findBoldableSpan(tester, '2 Galon Aqua');
      expect(boldSpan, isNotNull, reason: 'span "2 Galon Aqua" harus ada');
      expect(boldSpan!.style?.fontWeight, FontWeight.w700,
          reason: 'qty & nama produk harus bold');

      final restSpan = findBoldableSpan(tester, ' - 1 jaminan');
      expect(restSpan, isNotNull);
      expect(restSpan!.style?.fontWeight, isNot(FontWeight.w700),
          reason: 'keterangan jaminan/status bayar TIDAK ikut bold');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'BUG NYATA dilaporkan user: pre-order dgn jaminan WADAH (depositQty>0, '
        'auto-terisi saat unit requiresDeposit) TAPI DP RUPIAH belum dibayar '
        '(paid=false) -> harus TETAP "Tempo", bukan "Lunas"', (tester) async {
      await seedTransaction('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Warung Sari',
          qtyOrdered: 5,
          depositQty: 5, // wadah kosong dititip, BUKAN uang DP.
          transactionId: 'tx1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPreorderTab(tester);

      expect(
          find.textContaining('5 Gas LPG 3kg - 5 jaminan Tempo',
              findRichText: true),
          findsOneWidget,
          reason: 'depositQty (jaminan wadah) TIDAK boleh disalahartikan '
              'sbg DP sudah dibayar');
      expect(find.textContaining('Lunas', findRichText: true), findsNothing);

      final span = findBoldableSpan(tester, ' Tempo');
      expect(span, isNotNull);
      expect(span!.style?.fontWeight, FontWeight.w800);
      expect(span.style?.color, AppTheme.debtFg(false),
          reason: 'merah — pola warna sama dgn debtFg di seluruh app');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'TANPA jaminan wadah sama sekali & belum bayar -> "Tempo" menempel '
        'setelah nama produk (tidak ada kata "jaminan" utk ditempeli)',
        (tester) async {
      await seedTransaction('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Warung Sari',
          qtyOrdered: 5,
          transactionId: 'tx1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPreorderTab(tester);

      expect(find.textContaining('5 Gas LPG 3kg Tempo', findRichText: true),
          findsOneWidget,
          reason: '"Tempo" menempel langsung setelah nama produk');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'DP RUPIAH sudah dibayar (paid=true) -> "Lunas" hijau bold, menempel '
        'PERSIS setelah kata "jaminan" kalau ada jaminan wadah', (tester) async {
      await seedTransaction('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'p1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Warung Sari',
          qtyOrdered: 5,
          depositQty: 2,
          paid: true,
          transactionId: 'tx1');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPreorderTab(tester);

      expect(
          find.textContaining('5 Gas LPG 3kg - 2 jaminan Lunas',
              findRichText: true),
          findsOneWidget,
          reason: '"Lunas" menempel langsung setelah kata "jaminan"');
      expect(find.textContaining('sudah bayar', findRichText: true),
          findsNothing,
          reason: 'keterangan lama "sudah bayar" sudah dihapus');

      final span = findBoldableSpan(tester, ' Lunas');
      expect(span, isNotNull);
      expect(span!.style?.fontWeight, FontWeight.w800);
      expect(span.style?.color, AppTheme.changeFg(false),
          reason: 'hijau — pola warna sama dgn changeFg di seluruh app');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('Pre-order: pencarian & statistik (permintaan user)', () {
    Future<void> seedPreorders() async {
      await seedTransaction('tx1');
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Tabung Gas'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P2', name: 'Galon Aqua'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U2', productId: 'P2', isBaseUnit: const Value(true)));
      await db.addPreorderEntry(
          id: 'po1',
          productId: 'P1',
          productUnitId: 'U1',
          customerName: 'Bu Artia',
          qtyOrdered: 2,
          depositQty: 2,
          transactionId: 'tx1');
      await db.addPreorderEntry(
          id: 'po2',
          productId: 'P2',
          productUnitId: 'U2',
          customerName: 'Pak Budi',
          qtyOrdered: 3,
          depositQty: 1,
          transactionId: 'tx1');
    }

    Future<void> openPreorderTab(WidgetTester tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pre-order'));
      await tester.pumpAndSettle();
    }

    testWidgets('statistik memisahkan total produk vs total jaminan',
        (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      expect(find.text('Total produk'), findsOneWidget);
      expect(find.text('Total jaminan'), findsOneWidget);
      // qty 2 + 3 = 5 produk; jaminan 2 + 1 = 3 jaminan — SENGAJA dua angka
      // terpisah, bukan dijumlahkan jadi satu.
      expect(find.text('5'), findsOneWidget, reason: 'total produk dipesan');
      expect(find.text('3'), findsOneWidget, reason: 'total jaminan dititip');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
        'rincian jaminan per produk (mis. "Tabung Gas: 2 jaminan") muncul di '
        'bawah Total jaminan, bukan cuma satu angka gabungan',
        (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      expect(
          find.text('Tabung Gas: 2 jaminan', findRichText: true),
          findsOneWidget,
          reason: 'jaminan Tabung Gas (P1) 2, terpisah dari Galon Aqua');
      expect(
          find.text('Galon Aqua: 1 jaminan', findRichText: true),
          findsOneWidget,
          reason: 'jaminan Galon Aqua (P2) 1, terpisah dari Tabung Gas');

      // Permintaan user: nama produk & qty di rincian jaminan BOLD, ": "
      // dan " jaminan" TIDAK bold. Pencarian span DIBATASI ke kartu
      // statistik: chip filter produk (fitur kuota pre-order) juga memuat
      // nama produk apa adanya, dan span-nya memang tidak bold.
      final stats = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_PreorderStats');
      final nameSpan = findBoldableSpan(tester, 'Tabung Gas', of: stats);
      expect(nameSpan, isNotNull);
      expect(nameSpan!.style?.fontWeight, FontWeight.w700,
          reason: 'nama produk di rincian jaminan harus bold');
      final qtySpan = findBoldableSpan(tester, '2', of: stats);
      expect(qtySpan, isNotNull);
      expect(qtySpan!.style?.fontWeight, FontWeight.w700,
          reason: 'qty di rincian jaminan harus bold');
      final connectorSpan = findBoldableSpan(tester, ' jaminan', of: stats);
      expect(connectorSpan, isNotNull);
      expect(connectorSpan!.style?.fontWeight, isNot(FontWeight.w700),
          reason: 'kata "jaminan" TIDAK ikut bold');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('cari by NAMA PELANGGAN menyaring daftar & statistik',
        (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      await tester.enterText(find.byType(TextField), 'Budi');
      await tester.pumpAndSettle();

      expect(find.text('Pak Budi'), findsOneWidget);
      expect(find.text('Bu Artia'), findsNothing);
      // Statistik ikut tersaring: sisa 3 produk & 1 jaminan.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('cari by NAMA PRODUK juga bisa', (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      await tester.enterText(find.byType(TextField), 'galon');
      await tester.pumpAndSettle();

      expect(find.text('Pak Budi'), findsOneWidget,
          reason: 'Galon Aqua dipesan Pak Budi');
      expect(find.text('Bu Artia'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('kata kunci tanpa hasil -> pesan kosong, bukan daftar penuh',
        (tester) async {
      await seedPreorders();
      await openPreorderTab(tester);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.textContaining('Tidak ada yang cocok'), findsOneWidget);
      expect(find.text('Bu Artia'), findsNothing);
      expect(find.text('Pak Budi'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });

  group('Pinjaman (permintaan user putaran terbaru — group by pelanggan)', () {
    Future<void> tapPinjamanTab(WidgetTester tester) async {
      await tester.tap(find.text('Pinjaman'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'pinjaman dari 2 NOTA BERBEDA tapi pelanggan SAMA dikumpulkan jadi '
        '1 Card; tiap baris tetap tertaut ke transactionId-nya sendiri',
        (tester) async {
      await seedTransaction('tx1');
      await seedTransaction('tx2');
      await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'c1', name: 'Pak Budi'));
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: 'tx1',
          itemName: 'Galon Aqua',
          qty: 2,
          customerId: 'c1',
          customerNameText: 'Pak Budi');
      await db.addBorrowedItem(
          id: 'b2',
          transactionId: 'tx2',
          itemName: 'Tabung Gas',
          qty: 1,
          customerId: 'c1',
          customerNameText: 'Pak Budi');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPinjamanTab(tester);

      expect(find.byType(Card), findsOneWidget,
          reason: 'satu pelanggan, 2 nota berbeda -> tetap 1 grup');
      expect(find.text('Pak Budi'), findsOneWidget,
          reason: 'header nama pelanggan tampil SEKALI, bukan per baris');
      expect(findEntryRows(of: find.byType(Card)), findsNWidgets(2),
          reason: '2 baris barang (dari 2 nota berbeda) di dalam 1 grup');

      // Tap baris Galon Aqua -> redirect ke tx1 (BUKAN tx2), walau satu grup.
      // `textContaining`: baris pinjaman sekarang "<barang> · Sisa x dari y".
      await tester.tap(find.textContaining('Galon Aqua'));
      await tester.pumpAndSettle();
      expect(find.text('Layar Struk tx1'), findsOneWidget,
          reason: 'tiap baris redirect ke transactionId MILIKNYA sendiri');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('pelanggan BERBEDA -> Card terpisah', (tester) async {
      await seedTransaction('tx1');
      await db.addBorrowedItem(
          id: 'b1',
          transactionId: 'tx1',
          itemName: 'Galon A',
          qty: 1,
          customerNameText: 'Ani');
      await db.addBorrowedItem(
          id: 'b2',
          transactionId: 'tx1',
          itemName: 'Galon B',
          qty: 1,
          customerNameText: 'Budi');

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tapPinjamanTab(tester);

      expect(find.byType(Card), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
    });
  });
}
