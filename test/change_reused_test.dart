import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/core/utils/change_display.dart';

/// Item 89 — `transaction_payments.change_reused`: kembalian ronde lama yang
/// DIPAKAI membayar ronde berikutnya, dipisah dari `change_taken` ("sudah
/// diserahkan", pengingat murni). Skenario contoh: total 100.000, bayar
/// 150.000 (kembalian 50.000), Tambah Belanjaan 60.000 (total 160.000).
///
/// Sebelum Item 89 satu kolom (`change_taken`) dipakai utk dua makna:
///  * mencentang "diserahkan" membuat struk jadi net (kembalian ronde lama
///    yang dicentang dianggap "dipakai");
///  * lupa mencentang "pakai" membuat tombol Gabungkan menawarkan uang yang
///    sebenarnya sudah terpakai.
void main() {
  late AppDatabase db;
  const txId = 'tx1';
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'P1', name: 'Gula'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: txId,
          localId: 'K1-1',
          status: 'lunas',
          total: 100000,
          paid: 0,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: 'i0',
        transactionId: txId,
        productId: 'P1',
        productUnitId: 'U1',
        qty: 1,
        priceAtSale: 100000,
        originalPrice: 100000,
        subtotal: 100000));
  });
  tearDown(() async => db.close());

  /// Ronde 1: bayar 150.000 utk 100.000 -> kembalian 50.000.
  Future<void> round1() => db.addPaymentToTransaction(
      txId: txId, amount: 150000, method: 'tunai', kasirId: 'K1');

  /// Ronde 2: tambah belanjaan [add] dibayar [pay], memakai [reused] dari
  /// kembalian ronde lama (persis yang dilakukan `_confirmAddItems`).
  Future<void> round2({int add = 60000, required int pay, int? reused = 0}) =>
      db.addItemsToTransaction(
        txId: txId,
        items: [
          TransactionItemsCompanion.insert(
              id: 'i${DateTime.now().microsecondsSinceEpoch}',
              transactionId: txId,
              productId: 'P1',
              productUnitId: 'U1',
              qty: 1,
              priceAtSale: add,
              originalPrice: add,
              subtotal: add),
        ],
        stockItems: const [],
        payment: TransactionPaymentsCompanion.insert(
          id: 'pay-r2-${DateTime.now().microsecondsSinceEpoch}',
          transactionId: txId,
          amount: pay,
          method: 'tunai',
          paidAt: Value(DateTime.now().add(const Duration(seconds: 1))),
          note: const Value('Tambah belanjaan'),
          changeReused: Value(reused),
        ),
        kasirId: 'K1',
      );

  Future<void> tickHanded(int index, bool v) async {
    final p = (await db.getPaymentsForTx(txId))[index];
    await (db.update(db.transactionPayments)..where((t) => t.id.equals(p.id)))
        .write(TransactionPaymentsCompanion(
            changeTaken: Value(v), updatedAt: Value(DateTime.now())));
  }

  Future<Transaction> tx() => (db.select(db.transactions)
        ..where((t) => t.id.equals(txId)))
      .getSingle();

  Future<int> shown() async =>
      lastStateChange(await tx(), await db.getPaymentsForTx(txId));

  test('kolom baru: baris baru dari app = 0, bukan null', () async {
    await round1();
    expect((await db.getPaymentsForTx(txId)).single.changeReused, 0);
  });

  test(
      'kembalian ronde 1 DIPAKAI penuh (Diterima 60.000): struk net, tanpa '
      'Kembali, tombol gabung tidak menawarkan apa pun', () async {
    await round1();
    await round2(pay: 60000, reused: 50000);
    expect((await tx()).status, 'lunas');
    expect(await shown(), 0);
    expect(unclaimedChangeTotal(await db.getPaymentsForTx(txId)), 0);
  });

  test(
      'kembalian ronde 1 TIDAK dipakai (uang baru 60.000): struk gross, '
      'Kembali 50.000 tetap tampil', () async {
    await round1();
    await round2(pay: 60000, reused: 0);
    expect(await shown(), 50000);
    expect(unclaimedChangeTotal(await db.getPaymentsForTx(txId)), 50000);
  });

  test(
      'mencentang "diserahkan" TIDAK mengubah angka struk (dulu jadi net)',
      () async {
    await round1();
    await round2(pay: 60000, reused: 0);
    await tickHanded(0, true);
    expect(await shown(), 50000,
        reason: 'tanpa Item 89: kembalian ronde lama yang dicentang dianggap '
            '"dipakai" -> struk net');
    expect(unclaimedChangeTotal(await db.getPaymentsForTx(txId)), 0,
        reason: 'sudah diserahkan -> tombol gabung tidak menawarkannya');
  });

  test(
      'kasus user: dipakai 50.000 + uang baru 20.000 (Diterima 70.000) -> '
      'kembalian baru 10.000; Gabungkan hanya 10.000, BUKAN 60.000',
      () async {
    await round1();
    await round2(pay: 70000, reused: 50000);
    final pays = await db.getPaymentsForTx(txId);
    expect(pays.last.changeGiven, 10000);
    expect(await shown(), 10000);
    expect(unclaimedChangeTotal(pays), 10000,
        reason: 'tanpa Item 89 (lupa centang): 50.000 + 10.000 = 60.000');
  });

  test('dipakai SEBAGIAN: sisa 20.000 tetap tampil sbg Kembali', () async {
    await round1();
    await round2(add: 30000, pay: 30000, reused: 30000);
    expect((await tx()).status, 'lunas');
    expect(await shown(), 20000);
    expect(unclaimedChangeTotal(await db.getPaymentsForTx(txId)), 20000);
  });

  test(
      'Batalkan Pembayaran ronde yang memakai kembalian -> kembalian lama '
      '"hidup" lagi otomatis', () async {
    await round1();
    await round2(pay: 60000, reused: 50000);
    expect(await shown(), 0);
    final consumer = (await db.getPaymentsForTx(txId)).last;
    await db.voidPayment(consumer.id);
    expect(unclaimedChangeTotal(await db.getPaymentsForTx(txId)), 50000,
        reason: 'tanpa Item 89: centang "pakai" tersangkut walau ronde '
            'pemakainya sudah dibatalkan');
    // Barang tambahan tetap ada -> nota kembali kurang bayar (cuma Sisa).
    expect((await tx()).status, 'kurang_bayar');
    expect(await shown(), 0);
  });

  test(
      'ronde 1 lebih bayar, ronde 2 pas, ronde 3 memakai kembalian ronde 1: '
      'ditawarkan penuh & habis setelah dipakai', () async {
    await round1();
    await round2(add: 10000, pay: 10000, reused: 0);
    expect(reusableChangeTotal(await db.getPaymentsForTx(txId)), 50000,
        reason: 'dulu hanya menawarkan kembalian pembayaran TERAKHIR (0)');
    await round2(add: 20000, pay: 20000, reused: 20000);
    final pays = await db.getPaymentsForTx(txId);
    expect(reusableChangeTotal(pays), 30000);
    expect(await shown(), 30000);
  });

  test(
      'data LAMA (change_reused null): jatuh ke aturan centang lama — '
      'dicentang = dianggap dipakai, tidak dicentang = gross', () async {
    await round1();
    await round2(pay: 60000, reused: null);
    expect(await shown(), 50000, reason: 'belum dicentang -> gross');
    await tickHanded(0, true);
    expect(await shown(), 0, reason: 'legacy: dicentang -> net (perilaku lama)');
  });

  test('change_reused ikut sync ke device lain (sbg bagian baris)', () async {
    final b = AppDatabase(NativeDatabase.memory());
    addTearDown(b.close);
    await round1();
    await round2(pay: 70000, reused: 50000);
    final dump = await db.dumpSince(DateTime(2000));
    for (final e in dump.entries) {
      if (!LanSyncService.clientMergeableTables.contains(e.key)) continue;
      await b.mergeRows(
          e.key, e.value, LanSyncService.appendOnlyTables.contains(e.key));
    }
    final pays = await b.getPaymentsForTx(txId);
    expect(pays.map((p) => p.changeReused), containsAll([0, 50000]));
    expect(unclaimedChangeTotal(pays), 10000);
  });

  test('migrasi v45 -> v46: change_reused ditambah, baris lama null',
      () async {
    final path =
        '${Directory.systemTemp.path}/pos_mig46_${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    final v45 = raw.sqlite3.open(path);
    v45.execute('PRAGMA user_version = 45;');
    v45.execute('''
      CREATE TABLE transaction_payments(
        id TEXT PRIMARY KEY,
        transaction_id TEXT,
        amount INTEGER,
        method TEXT,
        change_taken INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER
      );
    ''');
    v45.execute("INSERT INTO transaction_payments (id, transaction_id, "
        "amount, method) VALUES ('pay-lama', 'tx', 10000, 'tunai');");
    v45.dispose();

    final d = AppDatabase(NativeDatabase(file), readOnly: true);
    final cols = await d
        .customSelect('PRAGMA table_info(transaction_payments)')
        .get();
    expect(cols.map((r) => r.data['name']), contains('change_reused'));
    final row = await d
        .customSelect('SELECT change_reused FROM transaction_payments')
        .getSingle();
    expect(row.data['change_reused'], isNull,
        reason: 'baris lama TIDAK diisi ulang — null = data lama');
    final ver = await d.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 46);
    await d.close();
    if (file.existsSync()) file.deleteSync();
  });
}
