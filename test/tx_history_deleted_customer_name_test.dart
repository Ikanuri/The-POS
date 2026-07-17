import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

import 'helpers/pump_app.dart';

/// Bug dilaporkan user (ketahuan saat review di device tujuan "Alihkan
/// Owner", tapi murni bug lama yang sudah ada sebelumnya): baris riwayat
/// transaksi milik pelanggan yang SUDAH DIHAPUS menampilkan label generik
/// "Pelanggan", bukan nama aslinya — meski `customerId` di transaksi masih
/// menunjuk ke pelanggan itu & `deactivateCustomer()` menjanjikan riwayat
/// historis tetap utuh.
void main() {
  testWidgets(
      'transaksi dgn customerId milik pelanggan yang SUDAH DIHAPUS tetap '
      'menampilkan nama asli (BUKAN fallback "Pelanggan")', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Bu Jamal'));
    await db.deactivateCustomer('c1');

    // customerName sengaja NULL (persis pola nyata saat pelanggan dipilih
    // dari daftar, bukan diketik manual — lihat receipt_screen.dart
    // _saveCustomer(id:, name: null)) — nama HARUS di-resolve via customerId.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'tunai',
          customerId: const Value('c1'),
          customerName: const Value.absent(),
        ));

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    expect(find.text('Bu Jamal'), findsOneWidget,
        reason: 'nama historis pelanggan yg sudah dihapus harus tetap tampil');
    expect(find.text('Pelanggan'), findsNothing,
        reason: 'tidak boleh jatuh ke fallback generik');

    await db.close();
  });
}
