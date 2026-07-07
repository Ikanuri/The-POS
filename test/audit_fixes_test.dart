import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/csv_import_service.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/core/services/price_service.dart';

/// Test regresi hasil audit kode (sesi audit Juli 2026). Tiap group merujuk
/// nomor temuan (B1, B3, B4, B7, B10, B13) di laporan audit — masing-masing
/// sudah diverifikasi GAGAL terhadap kode lama sebelum fix diterapkan.

Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required String status,
    required int total,
    required int paid,
    required int createdAtSec,
    String? customerId,
    int pointsEarned = 0,
    String? internalNote}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: status,
        total: total,
        paid: paid,
        changeAmount: 0,
        paymentMethod: 'tunai',
        customerId: Value(customerId),
        pointsEarned: Value(pointsEarned),
        internalNote: Value(internalNote),
        createdAt:
            Value(DateTime.fromMillisecondsSinceEpoch(createdAtSec * 1000)),
      ));
}

void main() {
  // ───────────────────────────────────────────────────────────────────────
  group('B1 — filterArchivedRows (tutup buku vs full-dump sync)', () {
    // 1 Jan 2026 & 1 Jan 2027 dalam unix detik (lokal).
    final sec2026 = DateTime(2026, 3, 1).millisecondsSinceEpoch ~/ 1000;
    final sec2027 = DateTime(2027, 2, 1).millisecondsSinceEpoch ~/ 1000;

    test('tanpa arsip sama sekali → payload lolos apa adanya', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final tables = {
        'transactions': [
          {'id': 'tx-old', 'created_at': sec2026},
        ],
      };
      final out =
          await LanSyncService.filterArchivedRows(db, tables, const {});
      expect(out['transactions'], hasLength(1));
      await db.close();
    });

    test(
        'tahun SEBELUM arsip pertama (tidak pernah diarsip, datanya masih '
        'sah di DB utama) tetap lolos', () async {
      // Toko mulai 2024, baru pertama kali tutup buku untuk 2026 → data
      // 2024-2025 tidak pernah diarsip dan masih hidup di DB utama host.
      // Baris klien dari tahun-tahun itu TIDAK boleh ikut terbuang.
      final db = AppDatabase(NativeDatabase.memory());
      final sec2025 = DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000;
      final out = await LanSyncService.filterArchivedRows(db, {
        'transactions': [
          {'id': 'tx-2025', 'created_at': sec2025},
          {'id': 'tx-2026', 'created_at': sec2026},
        ],
      }, const {2026});
      expect(out['transactions']!.map((r) => r['id']), ['tx-2025'],
          reason: 'hanya tahun yang benar-benar diarsip yang disaring');
      await db.close();
    });

    test(
        'transaksi tahun terarsip DIBUANG (tidak hidup lagi setelah '
        'tutup buku), tahun berjalan tetap lolos', () async {
      final db = AppDatabase(NativeDatabase.memory());

      final tables = {
        'transactions': [
          {'id': 'tx-2026', 'created_at': sec2026, 'total': 1000},
          {'id': 'tx-2027', 'created_at': sec2027, 'total': 2000},
        ],
        'transaction_items': [
          // Item milik tx terarsip → ikut dibuang.
          {'id': 'ti-a', 'transaction_id': 'tx-2026'},
          // Item milik tx tahun berjalan → lolos.
          {'id': 'ti-b', 'transaction_id': 'tx-2027'},
          // Item yatim (induk tidak di payload & tidak di DB lokal) →
          // dibuang, mencegah pelanggaran FK saat merge.
          {'id': 'ti-c', 'transaction_id': 'tx-ghost'},
        ],
        'stock_ledger': [
          {'id': 'sl-old', 'created_at': sec2026},
          {'id': 'sl-new', 'created_at': sec2027},
        ],
      };

      final out =
          await LanSyncService.filterArchivedRows(db, tables, const {2026});
      expect(out['transactions']!.map((r) => r['id']), ['tx-2027']);
      expect(out['transaction_items']!.map((r) => r['id']), ['ti-b']);
      expect(out['stock_ledger']!.map((r) => r['id']), ['sl-new']);
      await db.close();
    });

    test('child row untuk transaksi yang SUDAH ada di DB lokal tetap lolos',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      // Nota lama tahun berjalan yang sudah ada di host — cicilan susulan
      // dari klien harus tetap bisa menempel.
      await _insertTx(db,
          id: 'tx-local',
          localId: 'K1-1',
          status: 'kurang_bayar',
          total: 50000,
          paid: 20000,
          createdAtSec: sec2027);

      final out = await LanSyncService.filterArchivedRows(db, {
        'transaction_payments': [
          {'id': 'tp-1', 'transaction_id': 'tx-local', 'amount': 30000},
        ],
      }, const {2026});
      expect(out['transaction_payments'], hasLength(1));
      await db.close();
    });

    test(
        'integrasi: payload klien full-dump TIDAK menghidupkan lagi transaksi '
        'yang dihapus tutup buku (tanpa filter, mergeRows me-resurrect)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());

      // Payload klien: transaksi 2026 yang di host sudah dihapus tutup buku.
      final payloadTx = [
        {
          'id': 'tx-arch',
          'local_id': 'K1-20260301-0001',
          'status': 'lunas',
          'total': 10000,
          'paid': 10000,
          'change_amount': 0,
          'payment_method': 'tunai',
          'points_earned': 0,
          'created_at': sec2026,
        },
      ];

      // Bukti bug lama: TANPA filter, merge me-resurrect baris terarsip.
      await db.mergeRows('transactions', payloadTx, true);
      var count = await (db.select(db.transactions)).get();
      expect(count, hasLength(1),
          reason: 'tanpa filter, transaksi terarsip hidup lagi (bug lama)');
      await (db.delete(db.transactions)).go(); // reset seperti pasca tutup buku

      // Jalur baru: filter dulu → tidak ada yang di-merge.
      final filtered = await LanSyncService.filterArchivedRows(
          db, {'transactions': payloadTx}, const {2026});
      await db.mergeRows(
          'transactions', filtered['transactions'] ?? const [], true);
      count = await (db.select(db.transactions)).get();
      expect(count, isEmpty,
          reason: 'dengan filter, data tahun terarsip tidak kembali');
      await db.close();
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B7 — addPaymentToTransaction (Tambah Bayar catat paid penuh)', () {
    test('bayar berlebih: paid penuh, lunas, kembalian dari paid - total',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1',
          localId: 'K1-1',
          status: 'tempo',
          total: 95000,
          paid: 0,
          createdAtSec: 1700000000);

      final change = await db.addPaymentToTransaction(
          txId: 'tx1', amount: 100000, method: 'tunai', kasirId: 'K1');
      expect(change, 5000);

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.paid, 100000, reason: 'paid dicatat PENUH, tidak di-cap');
      expect(tx.status, 'lunas');
      expect(tx.changeAmount, 5000);

      final payments = await db.getPaymentsForTx('tx1');
      expect(payments.single.amount, 100000);
      await db.close();
    });

    test('kembalian SELAMAT dari rekonsiliasi (dulu tertimpa jadi 0)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1',
          localId: 'K1-1',
          status: 'kurang_bayar',
          total: 95000,
          paid: 0,
          createdAtSec: 1700000000);
      await db.into(db.transactionItems).insert(
          TransactionItemsCompanion.insert(
              id: 'ti1',
              transactionId: 'tx1',
              productId: 'P1',
              productUnitId: 'U1',
              qty: 1,
              priceAtSale: 95000,
              originalPrice: 95000,
              subtotal: 95000));

      await db.addPaymentToTransaction(
          txId: 'tx1', amount: 100000, method: 'tunai', kasirId: 'K1');
      // Rekonsiliasi seperti yang terjadi setelah sync / tambah belanjaan.
      await db.reconcileTransactionsByIds({'tx1'});

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.changeAmount, 5000,
          reason: 'info "Kembali Rp 5.000" tidak boleh hilang pasca-reconcile');
      expect(tx.status, 'lunas');
      await db.close();
    });

    test('bayar sebagian: status kurang_bayar, kembalian 0', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1',
          localId: 'K1-1',
          status: 'tempo',
          total: 95000,
          paid: 0,
          createdAtSec: 1700000000);
      final change = await db.addPaymentToTransaction(
          txId: 'tx1', amount: 40000, method: 'transfer', kasirId: 'K1');
      expect(change, 0);
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals('tx1')))
          .getSingle();
      expect(tx.paid, 40000);
      expect(tx.status, 'kurang_bayar');
      await db.close();
    });

    test('nota void / amount <= 0 → tidak melakukan apa pun', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1',
          localId: 'K1-1',
          status: 'void',
          total: 95000,
          paid: 0,
          createdAtSec: 1700000000);
      expect(
          await db.addPaymentToTransaction(
              txId: 'tx1', amount: 1000, method: 'tunai', kasirId: 'K1'),
          0);
      expect(
          await db.addPaymentToTransaction(
              txId: 'tx1', amount: 0, method: 'tunai', kasirId: 'K1'),
          0);
      expect(await db.getPaymentsForTx('tx1'), isEmpty);
      await db.close();
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B10 — void nota retur memulihkan poin loyalty', () {
    test('retur memotong poin proporsional; void retur mengembalikannya',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'C1', name: 'Bu Sari', loyaltyPoints: const Value(100)));
      // Nota asal: total 100rb, dapat 100 poin.
      await _insertTx(db,
          id: 'tx-asal',
          localId: 'K1-1',
          status: 'lunas',
          total: 100000,
          paid: 100000,
          createdAtSec: 1700000000,
          customerId: 'C1',
          pointsEarned: 100);

      // Retur separuh nilai nota → poin dipotong 50.
      await db.addReturnTransaction(
        originalTxId: 'tx-asal',
        localId: 'K1-2',
        returnItems: [
          (
            productUnitId: 'U1',
            productId: 'P1',
            qty: 1.0,
            price: 50000,
            costPrice: 30000,
            itemNote: null,
          ),
        ],
        kasirId: 'K1',
      );
      var cust = await (db.select(db.customers)
            ..where((t) => t.id.equals('C1')))
          .getSingle();
      expect(cust.loyaltyPoints, 50, reason: 'retur memotong 50 poin');

      // Void nota retur → potongan poin harus kembali.
      final returTx = await (db.select(db.transactions)
            ..where((t) => t.internalNote.equals('RETUR:tx-asal')))
          .getSingle();
      await db.voidTransaction(returTx.id, 'K1');

      cust = await (db.select(db.customers)..where((t) => t.id.equals('C1')))
          .getSingle();
      expect(cust.loyaltyPoints, 100,
          reason: 'void retur mengembalikan poin yang dipotong retur');

      // Jejak audit di ledger poin.
      final ledger = await (db.select(db.loyaltyPointLedger)
            ..where((t) => t.customerId.equals('C1')))
          .get();
      expect(ledger.any((l) => l.points == 50 && l.note!.contains('Void retur')),
          isTrue);
      await db.close();
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B4 — resolvePrice harga grup: HPP dari tier, bukan 0', () {
    test('harga grup dipakai, costPrice tetap dari tier yang cocok', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.into(db.products).insert(
          ProductsCompanion.insert(id: 'P1', name: 'Gula'));
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'T1',
          productUnitId: 'U1',
          minQty: const Value(1),
          price: 15000,
          costPrice: const Value(13000)));
      await db.into(db.customerGroups).insert(
          CustomerGroupsCompanion.insert(id: 'G1', name: 'Langganan'));
      await db.into(db.customerGroupPrices).insert(
          CustomerGroupPricesCompanion.insert(
              id: 'GP1',
              productUnitId: 'U1',
              customerGroupId: 'G1',
              price: 14000));

      final resolved = await PriceService(db).resolvePrice(
          productUnitId: 'U1', qty: 1, customerGroupId: 'G1');
      expect(resolved.price, 14000);
      expect(resolved.source, PriceSource.customerGroup);
      expect(resolved.costPrice, 13000,
          reason: 'HPP harus dari tier — 0 membuat laba laporan melonjak palsu');
      await db.close();
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B3 — import CSV ulang: update produk lama, bukan duplikasi', () {
    const header = 'nama,satuan,harga_jual,harga_beli,barcode\n';

    test('import kedua (barcode sama) meng-update harga, TANPA produk baru '
        'dan TANPA memindahkan barcode', () async {
      final db = AppDatabase(NativeDatabase.memory());
      const csv1 = '${header}Gula Pasir,Kg,15000,13000,111222\n';
      final r1 = await CsvImportService.importFromBytes(
          bytes: utf8.encode(csv1), db: db);
      expect(r1.imported, 1);
      expect(r1.updated, 0);
      final unitIdAwal = (await db.lookupBarcode('111222'))!.productUnitId;

      // File yang sama diimport ulang dengan harga baru.
      const csv2 = '${header}Gula Pasir,Kg,16000,14000,111222\n';
      final r2 = await CsvImportService.importFromBytes(
          bytes: utf8.encode(csv2), db: db);
      expect(r2.imported, 0, reason: 'tidak boleh membuat produk duplikat');
      expect(r2.updated, 1);

      final products = await db.searchProducts('');
      expect(products, hasLength(1), reason: 'katalog tidak menggandakan diri');

      // Barcode masih menunjuk unit produk LAMA (tidak "dicuri").
      expect((await db.lookupBarcode('111222'))!.productUnitId, unitIdAwal);

      // Harga tier dasar ter-update.
      final tiers = await db.getPriceTiers(unitIdAwal);
      final base = tiers.firstWhere((t) => t.minQty == 1);
      expect(base.price, 16000);
      expect(base.costPrice, 14000);
      await db.close();
    });

    test('match nama+satuan (tanpa barcode) juga meng-update, satuan berbeda '
        'tetap dianggap produk baru', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await CsvImportService.importFromBytes(
          bytes: utf8.encode('${header}Beras Rojo,Kg,12000,10000,\n'), db: db);

      // Nama & satuan sama → update.
      final r2 = await CsvImportService.importFromBytes(
          bytes: utf8.encode('${header}Beras Rojo,Kg,12500,10500,\n'), db: db);
      expect(r2.updated, 1);
      expect(r2.imported, 0);

      // Nama sama tapi satuan lain (Sak) → produk/entri berbeda.
      final r3 = await CsvImportService.importFromBytes(
          bytes: utf8.encode('${header}Beras Rojo,Sak,300000,280000,\n'),
          db: db);
      expect(r3.imported, 1);
      expect(r3.updated, 0);
      await db.close();
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('B13 — parser CSV & sanitizer', () {
    test('field ber-kutip yang mengandung newline tidak memutus baris', () {
      final rows = CsvImportService.testParseCsv(
          'nama,catatan\n"Produk A","baris satu\nbaris dua"\nProduk B,x');
      expect(rows, hasLength(3));
      expect(rows[1][0], 'Produk A');
      expect(rows[1][1], 'baris satu\nbaris dua');
      expect(rows[2][0], 'Produk B');
    });

    test('nama produk berawalan "-" yang sah tidak terpangkas, '
        'formula tetap dinetralkan', () async {
      final db = AppDatabase(NativeDatabase.memory());
      const header = 'nama,satuan,harga_jual\n';
      await CsvImportService.importFromBytes(
          bytes: utf8.encode('$header-Promo Spesial,Pcs,1000\n'
              '"=SUM(A1)",Pcs,2000\n'),
          db: db);
      final products = await db.searchProducts('');
      final names = products.map((p) => p.name).toSet();
      expect(names, contains('-Promo Spesial'),
          reason: 'strip "-" hanya bila diikuti angka/kurung (formula)');
      expect(names, contains('SUM(A1)'),
          reason: 'prefix "=" (formula injection) tetap dibuang');
      await db.close();
    });
  });
}
