import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/payment_screen.dart';

import 'helpers/pump_app.dart';

/// Bug ditemukan (laporan user, screenshot): kartu "Pra-Bayar" di layar Bayar
/// (`payment_screen.dart`) menampilkan "Sisa yang perlu dibayar" dari
/// `_total - _prabayarPool` (item keranjang saja), TIDAK ikut menjumlahkan
/// entri "Lunasi Hutang"/"Pelunasi Pre-order" yang sedang aktif — beda dari
/// nominal "Bayar Rp X" utama (`_grandTotal`) yang SUDAH benar. Gerbang
/// penerimaan uang sungguhan (keypad/QRIS) TETAP aman (mewajibkan
/// `_grandTotal`, lihat `_onBayarPressed`) — ini murni perbaikan tampilan
/// info supaya tidak menyesatkan kasir.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Map<String, Object> prefsWithCartAndSettlements() => {
        'cart_v1_main': jsonEncode([
          const CartItem(
            productId: 'p1',
            productUnitId: 'u1',
            productName: 'Sabun Shinzui',
            unitName: 'Biji',
            qty: 3,
            price: 4400,
            originalPrice: 4400,
            costPrice: 3000,
          ).toJson(),
        ]),
        'cartprabayar_v1_main': jsonEncode([
          {
            'id': 'pb1',
            'amount': 4250,
            'method': 'tunai',
            'methodName': null,
            'lockedAt': DateTime.now().millisecondsSinceEpoch,
          },
        ]),
        'cartdebtsettle_v1_main': jsonEncode([
          {
            'id': 'ds1',
            'invoiceId': 'tx_old',
            'invoiceLocalId': 'O1-20260918-0006',
            'invoiceDate': DateTime.now().millisecondsSinceEpoch,
            'customerId': 'c1',
            'customerName': 'Buk Artia',
            'amount': 29400,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'method': 'tunai',
            'methodName': null,
          },
        ]),
      };

  testWidgets(
      'kartu Pra-Bayar: "Sisa yang perlu dibayar" ikut menjumlahkan Lunasi '
      'Hutang aktif (_grandTotal), bukan cuma item keranjang (_total)',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db,
        initialPrefs: prefsWithCartAndSettlements(),
        child: const PaymentScreen());

    // Item 3x Rp4.400 = Rp13.200. Sisa BENAR = (13200 + 29400 hutang) -
    // 4250 pra-bayar = 38350 -- BUKAN 13200 - 4250 = 8950 (bug lama, persis
    // angka di screenshot laporan user).
    expect(find.text('Sisa yang perlu dibayar'), findsOneWidget);
    expect(find.text(formatRupiah(38350)), findsOneWidget,
        reason: 'kartu Pra-Bayar wajib pakai _grandTotal (item + hutang + '
            'pre-order), bukan _total polos');
    expect(find.text(formatRupiah(8950)), findsNothing,
        reason: 'nominal lama yang mengabaikan Lunasi Hutang tidak boleh '
            'muncul lagi');
  });
}
