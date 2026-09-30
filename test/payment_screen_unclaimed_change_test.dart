import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

import 'helpers/pump_app.dart';

/// Poin 1 — Tambah Belanjaan: kalkulator bayar menampilkan info "kembalian
/// terakhir" (murni informasi + centang, TIDAK mengubah nominal yang diinput
/// kasir — kasir tetap input manual, sesuai simulasi fisik: kembalian sudah
/// diberikan, pelanggan bayar lagi pakai uang itu). Centang di sini menulis
/// langsung ke baris pembayaran sumbernya (aksi sama seperti centang di
/// Ringkasan struk). Item 89: kini HANYA state lokal; nominalnya ditulis ke
/// `change_reused` baris pembayaran baru saat konfirmasi.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedTxWithUnclaimedChange() async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 55000,
          changeAmount: 5000,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti1',
          transactionId: 'tx1',
          productId: 'P1',
          productUnitId: 'U1',
          qty: 1,
          priceAtSale: 50000,
          originalPrice: 50000,
          subtotal: 50000,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 55000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 10, 0)),
            changeGiven: const Value(5000)));
  }

  Map<String, Object> prefsWithCartItem() => {
        'cart_v1_tx1': jsonEncode([
          const CartItem(
            productId: 'P2',
            productUnitId: 'U2',
            productName: 'Barang Tambahan',
            unitName: 'pcs',
            qty: 1,
            price: 3000,
            originalPrice: 3000,
            costPrice: 2000,
          ).toJson(),
        ]),
      };

  testWidgets(
      'kalkulator bayar tambah belanjaan tampilkan info kembalian terakhir '
      'yang belum diambil', (tester) async {
    await seedTxWithUnclaimedChange();

    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: prefsWithCartItem(),
        child: const PaymentScreen(addToTxId: 'tx1'));

    await tester.tap(find.text('Bayar ${formatRupiah(3000)}'));
    await tester.pumpAndSettle();

    expect(find.text('Pakai kembalian'), findsOneWidget);
    expect(find.text(formatRupiah(5000)), findsOneWidget);
  });

  testWidgets(
      'info kembalian terakhir TIDAK tampil bila kembalian sebelumnya sudah '
      'dicentang diambil', (tester) async {
    await seedTxWithUnclaimedChange();
    await (db.update(db.transactionPayments)
          ..where((t) => t.id.equals('pay1')))
        .write(const TransactionPaymentsCompanion(changeTaken: Value(true)));

    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: prefsWithCartItem(),
        child: const PaymentScreen(addToTxId: 'tx1'));

    await tester.tap(find.text('Bayar ${formatRupiah(3000)}'));
    await tester.pumpAndSettle();

    expect(find.text('Pakai kembalian'), findsNothing);
  });

  testWidgets(
      'centang "Pakai kembalian" HANYA state lokal (Item 89: TIDAK menulis '
      'changeTaken ke DB — dulu bocor kalau layar dibatalkan) & checkbox-nya '
      'sendiri tampil tercentang (bukan tampilan beku)', (tester) async {
    await seedTxWithUnclaimedChange();

    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: prefsWithCartItem(),
        child: const PaymentScreen(addToTxId: 'tx1'));

    await tester.tap(find.text('Bayar ${formatRupiah(3000)}'));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.text('Pakai kembalian'));
    await tester.pumpAndSettle();

    // Sheet keypad dibuka via showModalBottomSheet — builder-nya cuma
    // dievaluasi sekali saat dibuka, jadi kalau Checkbox baca langsung
    // dari widget parent (bukan state lokal sheet), tampilannya akan BEKU
    // di false walau tulis-DB di bawah ini sukses. Assert visual INI yang
    // membuktikan bug "centang tidak bisa" tidak terulang.
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    final pay1 = await (db.select(db.transactionPayments)
          ..where((t) => t.id.equals('pay1')))
        .getSingle();
    expect(pay1.changeTaken, isFalse,
        reason: 'Item 89: centang "pakai" tidak boleh menulis DB sebelum '
            'pembayaran disimpan (membatalkan layar = tanpa jejak)');

    // Toggle balik juga harus tampil (bukan cuma arah true).
    await tester.tap(find.text('Pakai kembalian'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets(
      'Item 89: centang "Pakai kembalian" + konfirmasi menulis '
      'change_reused ke baris pembayaran BARU (bukan mengubah changeTaken '
      'baris lama)', (tester) async {
    await seedTxWithUnclaimedChange();

    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: prefsWithCartItem(),
        child: const PaymentScreen(addToTxId: 'tx1'));

    await tester.tap(find.text('Bayar ${formatRupiah(3000)}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pakai kembalian'));
    await tester.pumpAndSettle();
    for (final k in ['3', '0', '00']) {
      await tester.tap(find.text(k).last);
      await tester.pump();
    }
    await tester.tap(find.text('Bayar').last);
    await tester.pumpAndSettle();

    final pays = await db.getPaymentsForTx('tx1');
    expect(pays.length, 2, reason: 'pembayaran tambah belanjaan tersimpan');
    expect(pays.first.changeTaken, isFalse,
        reason: 'baris lama tidak disentuh (bukan makna "pakai")');
    expect(pays.last.amount, 3000);
    expect(pays.last.changeReused, 3000,
        reason: 'min(kembalian 5.000, Diterima 3.000)');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
