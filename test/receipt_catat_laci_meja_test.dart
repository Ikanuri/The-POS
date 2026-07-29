import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Item 52 ("Laci Meja") — tombol "+ Catat" di app bar Struk: satu ikon
/// gabungan (BUKAN dua ikon terpisah, app bar sudah padat), pilihan jenis
/// (Titip/Ketinggalan atau Pinjaman Barang) muncul di bottom sheet. Kedua
/// kategori SELALU menumpang transaksi yang sedang dibuka (transactionId),
/// bukan bikin nota terpisah.
///
/// Titip/Ketinggalan (koreksi user): WAJIB ditaut ke produk NYATA yang ada
/// di nota ini — UX-nya toggle centang barang mana yang titip/ketinggalan
/// (bisa lebih dari satu), BUKAN mengetik nama bebas.
void main() {
  late AppDatabase db;
  const txId = 'tx1';

  // Nama produk yg sama JUGA tampil di baris nota di BELAKANG dialog (bukan
  // hilang saat dialog dibuka) — cari HANYA di dalam AlertDialog spy tak
  // ambigu dgn Text.rich baris nota.
  Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog), matching: find.text(text));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P0', name: 'Payung Lipat'));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Topi'));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P0',
        productUnitId: 'U0',
        qty: 1,
        priceAtSale: 10000,
        originalPrice: 10000,
        subtotal: 10000));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 2,
        priceAtSale: 5000,
        originalPrice: 5000,
        subtotal: 10000));
    // Produk timbang, qty DESIMAL — permintaan user: "bagaimana jika barang
    // yang ketinggalan itu bentuk desimal? Misal Filma 4.5kg?".
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'P2', name: 'Filma'));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i2',
        transactionId: txId,
        productId: 'P2',
        productUnitId: 'U2',
        qty: 4.5,
        priceAtSale: 20000,
        originalPrice: 20000,
        subtotal: 90000));
  });
  tearDown(() async => db.close());

  testWidgets(
      'catat Titip/Ketinggalan dari struk -> toggle centang produk yang '
      'ada di nota (bukan ketik bebas), tersimpan dgn transactionId nota '
      'yang sedang dibuka, locallyModified=false (device owner)',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    expect(find.text('Titip/Ketinggalan'), findsOneWidget);
    expect(find.text('Pinjaman Barang'), findsOneWidget);

    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    // Dua produk nota ini tampil sbg pilihan centang, bukan field teks.
    expect(inDialog('Payung Lipat'), findsOneWidget);
    expect(inDialog('Topi'), findsOneWidget);

    await tester.tap(inDialog('Payung Lipat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.transactionId, txId);
    expect(rows.single.itemName, 'Payung Lipat',
        reason: 'nama produk diambil dari nota, bukan diketik bebas');
    expect(rows.single.jenis, 'titip');
    expect(rows.single.qty, 1,
        reason: 'default qty PENUH (sama dgn qty baris nota) saat dicentang');
    expect(rows.single.locallyModified, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'susulan (permintaan user): stepper qty membolehkan catat SEBAGIAN '
      'dari qty baris nota (mis. beli 2, ketinggalan cuma 1)', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    // Centang "Topi" (qty baris nota = 2), lalu kurangi steppernya ke 1.
    await tester.tap(inDialog('Topi'));
    await tester.pumpAndSettle();
    expect(inDialog('2'), findsOneWidget,
        reason: 'default stepper qty PENUH (2, sama dgn qty baris nota)');

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();
    expect(inDialog('1'), findsOneWidget,
        reason: 'stepper turun ke 1 setelah tombol kurang ditekan');

    // Tombol tambah harus berhenti di batas qty baris nota (tidak bisa lebih
    // dari yg dibeli).
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(inDialog('2'), findsOneWidget);
    final tambahLagi = tester.widget<IconButton>(find.ancestor(
        of: find.byIcon(Icons.add_circle_outline),
        matching: find.byType(IconButton)).first);
    expect(tambahLagi.onPressed, isNull,
        reason: 'tidak boleh melebihi qty baris nota (2)');

    // Turunkan lagi ke 1 sebelum simpan.
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Topi');
    expect(rows.single.qty, 1,
        reason: 'qty SEBAGIAN (1 dari 2) tersimpan, bukan qty penuh nota');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'susulan (permintaan user): qty DESIMAL (mis. Filma 4.5kg) bisa '
      'diketik langsung — stepper +/-1 SENDIRIAN tidak bisa mencapai '
      'nilai desimal sembarang', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    // Centang "Filma" (qty baris nota = 4.5) — default qty PENUH desimal.
    await tester.tap(inDialog('Filma'));
    await tester.pumpAndSettle();
    expect(inDialog('4.5'), findsOneWidget,
        reason: 'default qty penuh 4.5 (desimal), bukan dibulatkan');

    // Ketik langsung angka desimal SEMBARANG (2.5) — mustahil dicapai lewat
    // stepper +/-1 murni dari 4.5 (loncat 3.5, 2.5, 1.5... TIDAK PERNAH
    // mendarat di, mis., "2" bulat, tapi 2.5 kebetulan salah satu titiknya —
    // makanya di sini kita uji angka yg TIDAK bisa dicapai stepper: 3).
    final filmaTile = find.ancestor(
        of: inDialog('Filma'), matching: find.byType(ListTile));
    await tester.enterText(
        find.descendant(of: filmaTile, matching: find.byType(TextField)),
        '3');
    await tester.pumpAndSettle();

    // Tombol tambah harus tetap menghormati batas 4.5 (bukan +1 polos jadi
    // 4 lalu tombol berikutnya melebihi jadi 5).
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(inDialog('4'), findsOneWidget,
        reason: 'stepper +1 dari 3 -> 4 (masih valid, blm sampai batas)');
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(inDialog('4.5'), findsOneWidget,
        reason: 'putaran berikutnya HARUS mendarat PAS di batas 4.5, bukan '
            'melebihi jadi 5 — tombol tambah wajib mengklem ke qty persis');

    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Filma');
    expect(rows.single.qty, 4.5);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'toggle lebih dari satu produk -> masing-masing jadi baris '
      'LeftBehindItem terpisah', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    await tester.tap(inDialog('Payung Lipat'));
    await tester.tap(inDialog('Topi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.itemName).toSet(), {'Payung Lipat', 'Topi'});

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'nama pelanggan DIWARISI dari nota (pra-isi & tersimpan), tidak perlu '
      'diketik ulang — supaya kartu dashboard Laci Meja menampilkan namanya',
      (tester) async {
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Bu Sari'));
    await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
        .write(const TransactionsCompanion(
            customerId: Value('c1'), customerName: Value('Bu Sari')));

    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    // Field pelanggan sudah PRA-ISI dari nota, staf tidak mengetik apa pun.
    expect(find.widgetWithText(TextField, 'Bu Sari'), findsOneWidget);

    await tester.tap(inDialog('Payung Lipat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.customerNameText, 'Bu Sari');
    expect(rows.single.customerId, 'c1',
        reason: 'ditaut ke pelanggan terdaftar dari nota, bukan cuma teks');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'catat Pinjaman Barang dari struk -> input nama BEBAS KETIK (bukan '
      'checklist barang nota), tersimpan dgn qty benar', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pinjaman Barang'));
    await tester.pumpAndSettle();

    // Permintaan user: kembali plain text. Yang dipinjamkan biasanya WADAH
    // (galon/tabung kosong) yang justru BUKAN baris di nota — checklist
    // barang nota bikin barang yg sebenarnya dipinjam tidak bisa dicatat.
    expect(inDialog('Payung Lipat'), findsNothing,
        reason: 'checklist barang nota TIDAK dipakai lagi di Pinjaman');

    await tester.enterText(
        find.widgetWithText(TextField, 'Nama barang'), 'Galon kosong');
    await tester.enterText(find.widgetWithText(TextField, 'Jumlah'), '3');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.borrowedItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Galon kosong',
        reason: 'nama bebas ketik, boleh barang yg tidak ada di nota');
    expect(rows.single.qty, 3);
    expect(rows.single.transactionId, txId);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'susulan (permintaan user): toggle Titip/Ketinggalan ditaruh DI ATAS '
      'daftar produk, tidak perlu scroll lewati banyak produk dulu',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    final toggleY =
        tester.getTopLeft(find.byType(SegmentedButton<String>)).dy;
    final listHeadingY =
        tester.getTopLeft(inDialog('Pilih barang di nota ini')).dy;
    expect(toggleY, lessThan(listHeadingY),
        reason: 'toggle jenis harus di ATAS heading daftar produk');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'susulan (permintaan user): opsi "barang lain" diketik bebas — sama '
      'seperti Pinjaman — TANPA mencentang produk apa pun (produk yg tidak '
      'dibeli di toko ini tapi tertinggal/dititipkan)', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const ReceiptScreen(transactionId: txId));

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();

    // TIDAK centang produk apa pun — centang produk TETAP fitur utama,
    // ini cuma pelengkap utk barang yg BUKAN baris nota.
    await tester.enterText(
        find.widgetWithText(TextField, 'Nama barang'), 'Payung pelanggan');
    await tester.enterText(find.widgetWithText(TextField, 'Jml'), '2');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.itemName, 'Payung pelanggan');
    expect(rows.single.qty, 2);
    expect(rows.single.transactionItemId, isNull,
        reason: 'barang lain BUKAN baris nota, tidak boleh ditaut');
    expect(rows.single.jenis, 'titip');

    // Tampil sbg section terpisah di struk (pola sama "Pinjaman Barang").
    expect(find.text('Titip/Ketinggalan (di luar nota)'), findsOneWidget);
    expect(find.textContaining('Payung pelanggan'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'device NON-OWNER (kasir) mencatat -> locallyModified=true (menunggu '
      'approve owner, pola sama spt usulan produk Item 40)', (tester) async {
    await pumpWithFakeApp(
      tester,
      db: db,
      child: const ReceiptScreen(transactionId: txId),
      device: const DeviceIdentity(
        storeUuid: 'test-store-uuid',
        storeKey: 'test-store-key',
        storeName: 'Toko Uji',
        deviceName: 'Kasir Uji',
        deviceCode: 'K2',
        deviceRole: 'kasir',
      ),
    );

    await tester.tap(find.byTooltip('+ Catat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Titip/Ketinggalan'));
    await tester.pumpAndSettle();
    await tester.tap(inDialog('Payung Lipat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.leftBehindItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.locallyModified, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
