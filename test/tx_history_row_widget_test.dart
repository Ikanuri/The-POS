import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

import 'helpers/pump_app.dart';

/// Membuktikan perbaikan UX dari laporan pengguna: sisa hutang / kembalian
/// kini langsung terlihat di baris Riwayat Transaksi TANPA perlu buka struk
/// atau expand baris (sebelumnya harus buka struk dulu baru sadar nota
/// belum lunas penuh / ada kembalian menggantung).
///
/// formatRupiah() memakai non-breaking space (U+00A0) antara "Rp" dan angka
/// (agar keduanya tidak terpisah baris) — literal di sini memakai ' ',
/// BUKAN spasi biasa, supaya cocok dengan output sungguhan.
const _nbsp = ' ';

Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required String status,
    required int total,
    required int paid,
    int changeAmount = 0}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: status,
        total: total,
        paid: paid,
        changeAmount: changeAmount,
        paymentMethod: 'tunai',
      ));
}

void main() {
  testWidgets('nota kurang_bayar menampilkan "Sisa Rp X" di baris riwayat',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db,
        id: 'tx1',
        localId: 'K1-1',
        status: 'kurang_bayar',
        total: 50000,
        paid: 30000);

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    expect(find.text('Sisa Rp${_nbsp}20.000'), findsOneWidget,
        reason:
            'sisa hutang (50rb-30rb) harus langsung terlihat tanpa buka struk');

    await db.close();
  });

  testWidgets(
      'nota lunas dengan kembalian menampilkan "Kembali Rp X" di baris riwayat',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db,
        id: 'tx1',
        localId: 'K1-1',
        status: 'lunas',
        total: 50000,
        paid: 60000,
        changeAmount: 10000);

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    expect(find.text('Kembali Rp${_nbsp}10.000'), findsOneWidget);

    await db.close();
  });

  testWidgets('nota lunas uang pas TIDAK menampilkan sisa maupun kembalian',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db,
        id: 'tx1', localId: 'K1-1', status: 'lunas', total: 50000, paid: 50000);

    await pumpWithFakeApp(tester, db: db, child: const TxHistorySheet());

    expect(find.textContaining('Sisa'), findsNothing);
    expect(find.textContaining('Kembali'), findsNothing);

    await db.close();
  });
}
