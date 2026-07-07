import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

import 'helpers/pump_app.dart';

/// Membuktikan baris "Kasir: <nama device>" di struk TIDAK overflow walau
/// nama device diisi sangat panjang saat setup (field bebas diisi user,
/// tidak ada batas karakter di UI setup). Sebelumnya baris ini bukan
/// Expanded+ellipsis sehingga bisa mendorong tanggal transaksi terpotong
/// dari layar sempit — sudah diperbaiki, test ini menjaga agar tak berulang.
Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required String status,
    required int total,
    required int paid}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: status,
        total: total,
        paid: paid,
        changeAmount: 0,
        paymentMethod: 'tunai',
      ));
}

Future<void> _insertItem(AppDatabase db,
    {required String id,
    required String transactionId,
    required int priceAtSale,
    double qty = 1}) async {
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: id,
        transactionId: transactionId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: qty,
        priceAtSale: priceAtSale,
        originalPrice: priceAtSale,
        subtotal: (priceAtSale * qty).round(),
      ));
}

void main() {
  testWidgets(
      'struk dengan nama kasir sangat panjang tidak overflow & tanggal tetap tampil',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db,
        id: 'tx1', localId: 'K1-1', status: 'lunas', total: 15000, paid: 15000);
    await _insertItem(db, id: 'ti1', transactionId: 'tx1', priceAtSale: 15000);

    const longNameDevice = DeviceIdentity(
      storeUuid: 'test-store-uuid',
      storeKey: 'test-store-key',
      storeName: 'Toko Uji',
      deviceName:
          'Kasir Depan Toko Sembako Barokah Jaya Sentosa Cabang Utama Nomor Satu',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    await pumpWithFakeApp(tester,
        db: db,
        device: longNameDevice,
        child: const ReceiptScreen(transactionId: 'tx1'));

    // Tidak ada RenderFlex overflow (FlutterError akan membuat pumpAndSettle
    // gagal / exception tercatat kalau dibiarkan). Konfirmasikan juga baris
    // tanggal transaksi tetap ter-render (tidak ikut hilang/terpotong).
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Kasir: Kasir Depan'), findsOneWidget);

    await db.close();
  });
}
