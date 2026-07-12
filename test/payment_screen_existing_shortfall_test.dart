import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

import 'helpers/pump_app.dart';

/// Kalkulator bayar Tambah Belanjaan HANYA menampilkan harga item susulan
/// sebagai "Total" — tidak pernah mengecek apakah nota ITU SENDIRI masih
/// kurang bayar dari penambahan SEBELUMNYA (bisa terjadi kalau kembalian
/// yang sudah diambil dipakai lagi utk menutup sebagian item susulan,
/// hanya menutup SEBAGIAN — lihat net_remaining_owed_test.dart utk kasus
/// serupa). Ini bisa bikin kasir mengira "Total" kalkulator = semua yang
/// perlu ditagih, padahal ada sisa lama yang ikut belum tertutup. Fix:
/// info "+ Sisa tagihan sebelumnya" ditampilkan di kalkulator, murni
/// informasi (tidak diakumulasi ke `_total`/alokasi item, supaya harga
/// item susulan tidak ikut terdistorsi).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// Nota kurang_bayar 5.000 (setelah kembalian 5.000 dari pay1 — SUDAH
  /// diambil/changeTaken — dipakai lagi utk menutup SEBAGIAN item ke-2
  /// (10.000, cuma dibayar 5.000 via pay2) — persis skenario user.
  Future<void> seedTxWithExistingShortfall() async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'kurang_bayar',
          total: 60000,
          paid: 60000,
          changeAmount: 0,
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
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
          id: 'ti2',
          transactionId: 'tx1',
          productId: 'P2',
          productUnitId: 'U2',
          qty: 1,
          priceAtSale: 10000,
          originalPrice: 10000,
          subtotal: 10000,
        ));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay1',
            transactionId: 'tx1',
            amount: 55000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 10, 0)),
            changeGiven: const Value(5000),
            changeTaken: const Value(true)));
    await db.into(db.transactionPayments).insert(
        TransactionPaymentsCompanion.insert(
            id: 'pay2',
            transactionId: 'tx1',
            amount: 5000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 10, 5))));
  }

  Map<String, Object> prefsWithCartItem() => {
        'cart_v1_tx1': jsonEncode([
          const CartItem(
            productId: 'P3',
            productUnitId: 'U3',
            productName: '234 12',
            unitName: 'pak',
            qty: 1,
            price: 20000,
            originalPrice: 20000,
            costPrice: 15000,
          ).toJson(),
        ]),
      };

  testWidgets(
      'kalkulator bayar tambah belanjaan tampilkan info sisa tagihan '
      'sebelumnya, TANPA mengubah Total (harga item susulan saja)',
      (tester) async {
    await seedTxWithExistingShortfall();

    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: prefsWithCartItem(),
        child: const PaymentScreen(addToTxId: 'tx1'));

    await tester.tap(find.text('Bayar ${formatRupiah(20000)}'));
    await tester.pumpAndSettle();

    expect(find.text('+ Sisa tagihan sebelumnya'), findsOneWidget);
    expect(find.text(formatRupiah(5000)), findsOneWidget);
    // Total kalkulator (baris header, dipakai alokasi harga item) TETAP
    // harga item susulan saja (20.000) — tidak diakumulasi jadi 25.000
    // (biar alokasi harga/diskon item tidak rusak).
    expect(find.text(formatRupiah(20000)), findsWidgets);
    // TAPI kasir tidak perlu jumlah manual — angka gabungan sudah
    // dihitungkan & ditampilkan sebagai baris terpisah.
    expect(find.text('Total yang perlu ditagih'), findsOneWidget);
    expect(find.text(formatRupiah(25000)), findsOneWidget);
    // Tidak ada "Pakai kembalian" — pay2 (pembayaran terakhir) changeGiven
    // 0, tidak ada kembalian nganggur di baris itu.
    expect(find.text('Pakai kembalian'), findsNothing);
  });

  testWidgets(
      'info sisa tagihan sebelumnya TIDAK tampil kalau nota sudah lunas',
      (tester) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
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
            amount: 50000,
            method: 'tunai',
            paidAt: Value(DateTime(2026, 1, 1, 10, 0))));

    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: prefsWithCartItem(),
        child: const PaymentScreen(addToTxId: 'tx1'));

    await tester.tap(find.text('Bayar ${formatRupiah(20000)}'));
    await tester.pumpAndSettle();

    expect(find.text('+ Sisa tagihan sebelumnya'), findsNothing);
    expect(find.text('Total yang perlu ditagih'), findsNothing);
  });
}
