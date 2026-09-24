import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/kasir/receipt_screen.dart';

/// Audit sync & Pra-Bayar susulan (permintaan user, toko dgn >1 device):
/// `transaction_payments.changeTaken` ("kembalian sudah diambil/dipakai")
/// SEKARANG berbobot sungguhan (`e27bf8a`) — dipakai `latestChangeGiven`
/// utk menentukan baris "Kembali" mana yang masih harus dicetak/dibagikan.
/// SEBELUM fix di file ini, centang itu TIDAK PERNAH ikut sync (murni
/// per-device) — device yang sudah lebih dulu menerima baris pembayaran
/// itu TIDAK PERNAH tahu kalau device lain sudah menandainya selesai,
/// sehingga kembalian yang sudah beres bisa tercetak/tampil lagi seolah
/// masih aktif di device lain.
///
/// Ini bug KEDUA dari kelas yang sama dgn `e27bf8a` (yang membetulkan
/// kasus SATU device) — di sini yang dibetulkan adalah propagasinya
/// LINTAS device.
void main() {
  late AppDatabase a;
  late AppDatabase b;
  setUp(() {
    a = AppDatabase(NativeDatabase.memory());
    b = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<void> syncAToB(DateTime since) async {
    final dump = await a.dumpSince(since);
    final touched = <String>{};
    for (final entry in dump.entries) {
      if (!LanSyncService.clientMergeableTables.contains(entry.key)) continue;
      await b.mergeRows(entry.key, entry.value,
          LanSyncService.appendOnlyTables.contains(entry.key));
      for (final r in entry.value) {
        final txId = entry.key == 'transactions' ? r['id'] : r['transaction_id'];
        if (txId is String) touched.add(txId);
      }
    }
    await b.reconcileTransactionsByIds(touched);
  }

  Future<void> syncBToA(DateTime since) async {
    final dump = await b.dumpSince(since, includeMasterData: false);
    final touched = <String>{};
    for (final entry in dump.entries) {
      if (!LanSyncService.appendOnlyTables.contains(entry.key)) continue;
      await a.mergeRows(entry.key, entry.value, true);
      for (final r in entry.value) {
        final txId = entry.key == 'transactions' ? r['id'] : r['transaction_id'];
        if (txId is String) touched.add(txId);
      }
    }
    await a.reconcileTransactionsByIds(touched);
  }

  Future<void> seed(AppDatabase db) async {
    await db.into(db.products).insert(ProductsCompanion.insert(id: 'P1', name: 'Gula'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-1',
          status: 'lunas',
          total: 73750,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: 'tx1',
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 73750,
        originalPrice: 73750,
        subtotal: 73750));
  }

  test(
      'centang "sudah diambil" di device A -> ikut sync ke device B yang '
      'sudah lebih dulu punya salinan baris itu', () async {
    await seed(a);
    await a.addPaymentToTransaction(
        txId: 'tx1', amount: 80000, method: 'tunai', kasirId: 'K1');
    await syncAToB(DateTime(2000));

    final bPayBefore = (await b.getPaymentsForTx('tx1')).single;
    expect(bPayBefore.changeTaken, isFalse, reason: 'prakondisi');

    final watermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    final aPay = (await a.getPaymentsForTx('tx1')).single;
    await (a.update(a.transactionPayments)..where((t) => t.id.equals(aPay.id)))
        .write(TransactionPaymentsCompanion(
      changeTaken: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));

    await syncAToB(watermark);

    final bPayAfter = (await b.getPaymentsForTx('tx1')).single;
    expect(bPayAfter.changeTaken, isTrue,
        reason: 'tanpa fix: centang di A tidak pernah sampai ke B');
    expect(latestChangeGiven(await b.getPaymentsForTx('tx1')), 0,
        reason: 'B ikut menyembunyikan kembalian yg sudah selesai di A');
  });

  test(
      'centang "sudah diambil" di device KLIEN (B) -> ikut sync ke device '
      'HOST (A) yang sudah lebih dulu punya salinan baris itu', () async {
    await seed(a);
    await a.addPaymentToTransaction(
        txId: 'tx1', amount: 80000, method: 'tunai', kasirId: 'K1');
    await syncAToB(DateTime(2000));

    final watermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    final bPay = (await b.getPaymentsForTx('tx1')).single;
    await (b.update(b.transactionPayments)..where((t) => t.id.equals(bPay.id)))
        .write(TransactionPaymentsCompanion(
      changeTaken: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));

    await syncBToA(watermark);

    final aPayAfter = (await a.getPaymentsForTx('tx1')).single;
    expect(aPayAfter.changeTaken, isTrue,
        reason: 'tanpa fix: centang di klien tidak pernah sampai ke host');
  });

  test(
      'voidPayment di A SETELAH device B sempat menandai changeTaken lokal '
      '-> void TETAP tersampaikan ke B, TIDAK ter-revert balik jadi aktif',
      () async {
    await seed(a);
    await a.addPaymentToTransaction(
        txId: 'tx1', amount: 80000, method: 'tunai', kasirId: 'K1');
    await syncAToB(DateTime(2000));

    // B menandai changeTaken lokal (belum sempat sync balik ke A).
    final bPay = (await b.getPaymentsForTx('tx1')).single;
    await (b.update(b.transactionPayments)..where((t) => t.id.equals(bPay.id)))
        .write(TransactionPaymentsCompanion(
      changeTaken: const Value(true),
      updatedAt: Value(DateTime.now()),
    ));

    final watermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // A membatalkan pembayaran ini (voidPayment) TANPA tahu soal centang B.
    final aPay = (await a.getPaymentsForTx('tx1')).single;
    await a.voidPayment(aPay.id);
    expect((await a.getPaymentsForTx('tx1')).single.voided, isTrue,
        reason: 'sanity check');

    // Sync A -> B: pembatalan HARUS tersampaikan (bukan cuma changeTaken).
    await syncAToB(watermark);
    final bPayAfterVoidSync = (await b.getPaymentsForTx('tx1')).single;
    expect(bPayAfterVoidSync.voided, isTrue,
        reason: 'pembatalan dari A harus sampai ke B walau B juga barusan '
            'mengubah field lain (changeTaken) pada baris yang sama');

    // Sync B -> A (B kirim balik changeTaken-nya, dgn voided=false versi
    // LAMA yg B punya sebelum menerima update void barusan): A TIDAK boleh
    // ter-revert balik jadi voided=false gara-gara ini (bukti OR-merge,
    // bukan last-write-wins polos yg akan menimpa SELURUH baris B).
    final watermark2 = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    // B belum tahu soal void A saat menulis changeTaken-nya sendiri di atas
    // -- simulasikan dgn baris terpisah yg sengaja py voided=false + updated_at
    // BARU (kasus nyata: device offline, edit lokal, baru online lagi).
    await (b.update(b.transactionPayments)..where((t) => t.id.equals(bPay.id)))
        .write(TransactionPaymentsCompanion(
      changeTaken: const Value(true),
      voided: const Value(false),
      updatedAt: Value(DateTime.now()),
    ));
    await syncBToA(watermark2);

    final aPayFinal = (await a.getPaymentsForTx('tx1')).single;
    expect(aPayFinal.voided, isTrue,
        reason: 'tanpa OR-merge: last-write-wins by updated_at akan '
            'menimpa voided A balik ke false krn update B lebih baru -- '
            'pembayaran yg SUDAH dibatalkan hidup lagi diam-diam');
  });

  test(
      'undo lokal SEBELUM pernah sync (misclick) tetap berfungsi normal -- '
      'OR-merge cuma berlaku pasca-sync, bukan menghalangi koreksi lokal',
      () async {
    await seed(a);
    await a.addPaymentToTransaction(
        txId: 'tx1', amount: 80000, method: 'tunai', kasirId: 'K1');
    final pay = (await a.getPaymentsForTx('tx1')).single;

    await (a.update(a.transactionPayments)..where((t) => t.id.equals(pay.id)))
        .write(const TransactionPaymentsCompanion(changeTaken: Value(true)));
    expect((await a.getPaymentsForTx('tx1')).single.changeTaken, isTrue);

    // Undo (misclick) -- BELUM PERNAH sync ke device manapun.
    await (a.update(a.transactionPayments)..where((t) => t.id.equals(pay.id)))
        .write(const TransactionPaymentsCompanion(changeTaken: Value(false)));
    expect((await a.getPaymentsForTx('tx1')).single.changeTaken, isFalse,
        reason: 'koreksi lokal sebelum sync tidak boleh terhalang OR-merge '
            '-- itu murni tulis langsung, bukan lewat mergeRows');
  });
}
