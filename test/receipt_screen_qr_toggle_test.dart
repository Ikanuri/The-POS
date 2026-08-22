import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';
import 'package:the_pos/features/kasir/widgets/payment_qris_view.dart';

import 'helpers/pump_app.dart';

/// Item 62 susulan — QR pelunasan (dinamis/statis) di sheet "Bagikan
/// Struk", hanya utk nota tempo/kurang_bayar dgn metode QRIS aktif
/// terkonfigurasi. Nominal QR dinamis = SISA TAGIHAN (bukan total nota),
/// dikonfirmasi user. State toggle persisten (SharedPreferences, pola
/// sama dgn "Tampilkan Laba").
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  const staticQris = '00020101021126610014COM.GO-JEK.WWW01189360091434648855360'
      '210G4648855360303UMI51440014ID.CO.QRIS.WWW0215ID102657224253903'
      '03UMI5204549953033605802ID5920Toko Berkah, BNY NYR6011PROBOLIN'
      'GGO61056727562070703A0163043165';

  Future<String> seedTx({
    required String status,
    required int total,
    required int paid,
  }) async {
    const txId = 'tx1';
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: status,
          total: total,
          paid: paid,
          changeAmount: 0,
          paymentMethod: status == 'tempo' ? 'tempo' : 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i1',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: total.toDouble().round(),
        originalPrice: total,
        subtotal: total));
    if (paid > 0) {
      await db.into(db.transactionPayments).insert(
          TransactionPaymentsCompanion.insert(
              id: 'pay1', transactionId: txId, amount: paid, method: 'tunai'));
    }
    return txId;
  }

  Future<void> seedQris() =>
      db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
          id: 'pm-qris',
          type: 'qris',
          name: 'QRIS',
          qrValue: const Value(staticQris),
          sortOrder: const Value(1)));

  Future<void> openShareSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Bagikan Struk'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'nota tempo + QRIS terkonfigurasi → toggle "Tampilkan QR Pelunasan" '
      'muncul; nyalakan → QR & toggle Dinamis muncul, caption tampil',
      (tester) async {
    await seedQris();
    final txId = await seedTx(status: 'tempo', total: 50000, paid: 0);
    await pumpWithFakeApp(tester,
        db: db, child: ReceiptScreen(transactionId: txId));

    await openShareSheet(tester);
    expect(find.text('Tampilkan QR Pelunasan'), findsOneWidget);
    // Belum dinyalakan → QR/caption/toggle Dinamis belum tampil.
    expect(find.text('QR Dinamis'), findsNothing);
    expect(find.text('Mohon konfirmasi setelah membayar.'), findsNothing);

    await tester.tap(find.text('Tampilkan QR Pelunasan'));
    await tester.pumpAndSettle();

    expect(find.text('QR Dinamis'), findsOneWidget);
    expect(find.text('Mohon konfirmasi setelah membayar.'), findsOneWidget);

    // Susulan (permintaan user): logo QRIS di ATAS kode QR pada struk
    // gambar (share) -- bukan sekadar teks "QRIS" polos.
    final logoFinder = find.byWidgetPredicate((w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == 'assets/qris/qris_logo.png');
    expect(logoFinder, findsOneWidget,
        reason: 'logo QRIS harus tampil di atas QR saat toggle dinyalakan');
    expect(tester.getBottomLeft(logoFinder).dy,
        lessThan(tester.getTopLeft(find.byType(QrisQrBox)).dy),
        reason: 'logo harus di ATAS kode QR, bukan di bawah/tumpang tindih');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('nota LUNAS → toggle QR tidak ditawarkan sama sekali',
      (tester) async {
    await seedQris();
    final txId = await seedTx(status: 'lunas', total: 50000, paid: 50000);
    await pumpWithFakeApp(tester,
        db: db, child: ReceiptScreen(transactionId: txId));

    await openShareSheet(tester);
    expect(find.text('Tampilkan QR Pelunasan'), findsNothing,
        reason: 'nota lunas tidak punya sisa tagihan utk ditagih via QR');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'nota tempo TAPI belum ada metode QRIS terkonfigurasi → toggle tidak '
      'ditawarkan', (tester) async {
    final txId = await seedTx(status: 'tempo', total: 50000, paid: 0);
    await pumpWithFakeApp(tester,
        db: db, child: ReceiptScreen(transactionId: txId));

    await openShareSheet(tester);
    expect(find.text('Tampilkan QR Pelunasan'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'pilihan toggle TERSIMPAN persisten — buka lagi sheet, state '
      'bertahan', (tester) async {
    await seedQris();
    final txId =
        await seedTx(status: 'kurang_bayar', total: 50000, paid: 20000);
    await pumpWithFakeApp(tester,
        db: db, child: ReceiptScreen(transactionId: txId));

    await openShareSheet(tester);
    await tester.tap(find.text('Tampilkan QR Pelunasan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QR Dinamis')); // matikan (jadi statis)
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // tutup sheet (tap barrier)
    await tester.pumpAndSettle();

    await openShareSheet(tester);
    // Toggle "Tampilkan QR" harus sudah ON dari sesi sebelumnya, dan mode
    // Dinamis harus sudah OFF (statis) — keduanya persisten.
    expect(find.text('QR Dinamis'), findsOneWidget);
    final dynamicSwitch = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'QR Dinamis'));
    expect(dynamicSwitch.value, isFalse,
        reason: 'mode statis yg tadi dipilih harus bertahan');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'swipe turun BISA menutup sheet Bagikan Struk walau isi overflow/'
      'scrollable (mis. QR aktif di layar pendek)', (tester) async {
    await seedQris();
    final txId = await seedTx(status: 'tempo', total: 50000, paid: 0);
    await pumpWithFakeApp(tester,
        db: db,
        child: ReceiptScreen(transactionId: txId),
        surfaceSize: const Size(360, 500));

    await openShareSheet(tester);
    await tester.tap(find.text('Tampilkan QR Pelunasan'));
    await tester.pumpAndSettle();

    final scrollable = find.byType(SingleChildScrollView).first;
    await tester.drag(scrollable, const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(find.text('Tampilkan QR Pelunasan'), findsNothing,
        reason: 'sheet harus ter-pop oleh swipe turun');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
