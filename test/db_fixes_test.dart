import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/tutup_buku_service.dart';

/// Fake path_provider — mengarahkan getApplicationDocumentsDirectory ke folder
/// temp asli tanpa memerlukan platform channel (murni override interface).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

/// Sisipkan satu baris transactions minimal-valid (semua kolom NOT NULL diisi).
Future<void> _insertTx(AppDatabase db,
    {required String id,
    required String localId,
    required String status,
    required int total,
    required int paid,
    required int createdAtSec,
    String? internalNote}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: status,
        total: total,
        paid: paid,
        changeAmount: 0,
        paymentMethod: 'tunai',
        internalNote: Value(internalNote),
        createdAt: Value(DateTime.fromMillisecondsSinceEpoch(createdAtSec * 1000)),
      ));
}

/// Sisipkan satu baris transaction_items minimal-valid.
Future<void> _insertItem(AppDatabase db,
    {required String id,
    required String transactionId,
    required String productUnitId,
    required double qty,
    required int priceAtSale,
    String productId = 'P1'}) async {
  await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
        id: id,
        transactionId: transactionId,
        productId: productId,
        productUnitId: productUnitId,
        qty: qty,
        priceAtSale: priceAtSale,
        originalPrice: priceAtSale,
        subtotal: (priceAtSale * qty).round(),
      ));
}

void main() {
  group('returnUnpaidTransactionItems', () {
    test('retur sebagian pada nota tempo: qty & total berkurang, status tetap tempo',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1', localId: 'K1-1', status: 'tempo', total: 30000, paid: 0, createdAtSec: 1700000000);
      await _insertItem(db,
          id: 'ti1', transactionId: 'tx1', productUnitId: 'U1', qty: 3, priceAtSale: 10000);

      await db.returnUnpaidTransactionItems(
        txId: 'tx1',
        returns: [(transactionItemId: 'ti1', qty: 1)],
        kasirId: 'K1',
      );

      final item = await (db.select(db.transactionItems)
            ..where((t) => t.id.equals('ti1')))
          .getSingle();
      expect(item.qty, 2, reason: 'qty berkurang 1 (dari 3 jadi 2)');
      expect(item.subtotal, 20000);

      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx1'))).getSingle();
      expect(tx.total, 20000, reason: 'total nota ikut berkurang dari 30000');
      expect(tx.paid, 0);
      expect(tx.status, 'tempo', reason: 'masih ada sisa & belum dibayar → tetap tempo');

      // Stok dikembalikan.
      expect(await db.currentStock('U1'), 1,
          reason: 'return_in menambah stok sebesar qty yang diretur');

      // Jejak audit tercatat, amount 0 (bukan uang sungguhan).
      final payments = await db.getPaymentsForTx('tx1');
      expect(payments.length, 1);
      expect(payments.single.amount, 0);
      expect(payments.single.method, 'retur');

      await db.close();
    });

    test('retur SELURUH qty baris: baris hilang dari nota, total 0 → status jadi lunas',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1', localId: 'K1-1', status: 'tempo', total: 19400, paid: 0, createdAtSec: 1700000000);
      await _insertItem(db,
          id: 'ti1', transactionId: 'tx1', productUnitId: 'U1', qty: 1, priceAtSale: 19400);

      await db.returnUnpaidTransactionItems(
        txId: 'tx1',
        returns: [(transactionItemId: 'ti1', qty: 1)],
        kasirId: 'K1',
      );

      final items = await (db.select(db.transactionItems)
            ..where((t) => t.transactionId.equals('tx1')))
          .get();
      expect(items, isEmpty, reason: 'baris yang diretur penuh hilang dari nota, seperti contoh referensi');

      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx1'))).getSingle();
      expect(tx.total, 0);
      expect(tx.status, 'lunas',
          reason: 'tidak ada tagihan tersisa → tidak boleh menggantung sebagai tempo');
    });

    test('retur pada kurang_bayar yang paid > total baru → lunas dengan kembalian otomatis',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      // Total 100rb, sudah dibayar 50rb (kurang_bayar). Retur 60rb → total
      // baru 40rb, tapi paid tetap 50rb (uang itu memang sudah masuk) →
      // pelanggan jadi kelebihan bayar 10rb yang harus dikembalikan.
      await _insertTx(db,
          id: 'tx1', localId: 'K1-1', status: 'kurang_bayar', total: 100000, paid: 50000, createdAtSec: 1700000000);
      await db.into(db.transactionPayments).insert(TransactionPaymentsCompanion.insert(
            id: 'p1',
            transactionId: 'tx1',
            amount: 50000,
            method: 'tunai',
            paidAt: Value(DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000)),
          ));
      await _insertItem(db,
          id: 'ti1', transactionId: 'tx1', productUnitId: 'U1', qty: 6, priceAtSale: 10000);

      await db.returnUnpaidTransactionItems(
        txId: 'tx1',
        returns: [(transactionItemId: 'ti1', qty: 6)],
        kasirId: 'K1',
      );

      final tx = await (db.select(db.transactions)..where((t) => t.id.equals('tx1'))).getSingle();
      expect(tx.total, 0);
      expect(tx.paid, 50000, reason: 'uang yang sudah masuk tidak diutak-atik oleh retur');
      expect(tx.status, 'lunas');
      expect(tx.changeAmount, 50000,
          reason: 'kelebihan bayar relatif terhadap total baru harus tampil sebagai kembalian');

      await db.close();
    });

    test('ditolak untuk nota yang sudah lunas — pakai addReturnTransaction, bukan ini', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await _insertTx(db,
          id: 'tx1', localId: 'K1-1', status: 'lunas', total: 10000, paid: 10000, createdAtSec: 1700000000);
      await _insertItem(db,
          id: 'ti1', transactionId: 'tx1', productUnitId: 'U1', qty: 1, priceAtSale: 10000);

      // Pass Future-nya langsung (bukan closure) + await expectLater, agar
      // db.close() di bawah tidak jalan lebih dulu daripada Future ini
      // benar-benar reject.
      await expectLater(
        db.returnUnpaidTransactionItems(
          txId: 'tx1',
          returns: [(transactionItemId: 'ti1', qty: 1)],
          kasirId: 'K1',
        ),
        throwsA(isA<StateError>()),
      );

      await db.close();
    });
  });

  group('getReturnedQtyByUnit', () {
    test('retur yang di-void tidak dihitung — hanya retur aktif', () async {
      final db = AppDatabase(NativeDatabase.memory());

      await _insertTx(db,
          id: 'orig1', localId: 'K1-1', status: 'lunas', total: 30000, paid: 30000, createdAtSec: 1700000000);

      // Retur AKTIF: 3 unit dikembalikan.
      await _insertTx(db,
          id: 'ret1',
          localId: 'K1-2',
          status: 'lunas',
          total: -9000,
          paid: -9000,
          createdAtSec: 1700000100,
          internalNote: 'RETUR:orig1');
      await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
            id: 'ti1',
            transactionId: 'ret1',
            productId: 'P1',
            productUnitId: 'U1',
            qty: -3,
            priceAtSale: 3000,
            originalPrice: 3000,
            subtotal: -9000,
          ));

      // Retur yang SUDAH DIBATALKAN (void): 5 unit — tidak boleh ikut terhitung.
      await _insertTx(db,
          id: 'ret2',
          localId: 'K1-3',
          status: 'void',
          total: -15000,
          paid: -15000,
          createdAtSec: 1700000200,
          internalNote: 'RETUR:orig1');
      await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
            id: 'ti2',
            transactionId: 'ret2',
            productId: 'P1',
            productUnitId: 'U1',
            qty: -5,
            priceAtSale: 3000,
            originalPrice: 3000,
            subtotal: -15000,
          ));

      final result = await db.getReturnedQtyByUnit('orig1');

      expect(result['U1'], 3,
          reason: 'retur void (5) harus dikecualikan; hanya retur aktif (3) yang dihitung');

      await db.close();
    });
  });

  group('mergeRows — local_id collision', () {
    test('rename mencari suffix bebas, tidak berhenti di -S pertama', () async {
      final db = AppDatabase(NativeDatabase.memory());

      // Dua device sudah pernah bentrok sebelumnya: 'K1-1' dan 'K1-1-S' sudah ada.
      await _insertTx(db, id: 'existing1', localId: 'K1-1', status: 'lunas', total: 1000, paid: 1000, createdAtSec: 1700000000);
      await _insertTx(db, id: 'existing2', localId: 'K1-1-S', status: 'lunas', total: 2000, paid: 2000, createdAtSec: 1700000001);

      // Device ketiga mengirim transaksi baru dengan local_id yang sama persis.
      final incoming = {
        'id': 'incoming3',
        'local_id': 'K1-1',
        'kasir_id': null,
        'customer_id': null,
        'customer_name': null,
        'status': 'lunas',
        'total': 3000,
        'paid': 3000,
        'change_amount': 0,
        'payment_method': 'tunai',
        'internal_note': null,
        'struk_note': null,
        'employee_name': null,
        'points_earned': 0,
        'created_at': 1700000002,
        'synced_at': null,
      };

      final count = await db.mergeRows('transactions', [incoming], true);
      expect(count, 1, reason: 'baris harus tetap ter-INSERT (tidak di-drop diam-diam)');

      final rows = await db.select(db.transactions).get();
      expect(rows.length, 3);
      final merged = rows.firstWhere((t) => t.id == 'incoming3');
      expect(merged.localId, 'K1-1-S2',
          reason: 'suffix -S sudah dipakai, harus lanjut ke -S2, bukan gagal/ditolak');

      await db.close();
    });
  });

  group('TutupBukuService — saldo stok tidak hilang', () {
    late Directory tempDir;
    late PathProviderPlatform originalPlatform;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pos_tutup_buku_');
      originalPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = originalPlatform;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
        'unit yang seluruh riwayat ledger-nya terarsip: saldo dibawa via entri baru',
        () async {
      final dbFile = File('${tempDir.path}/the_pos.db');
      final db = AppDatabase(NativeDatabase(dbFile));

      const archivedYear = 2024;
      final inArchived = DateTime(archivedYear, 6, 15);
      final inCurrent = DateTime(archivedYear + 1, 1, 10);

      // Transaksi placeholder di tahun terarsip (agar txArchived > 0) & di
      // tahun berjalan (harus tetap ada setelah tutup buku).
      await _insertTx(db,
          id: 'tx-arch',
          localId: 'K1-A',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          createdAtSec: inArchived.millisecondsSinceEpoch ~/ 1000);
      await _insertTx(db,
          id: 'tx-cur',
          localId: 'K1-B',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          createdAtSec: inCurrent.millisecondsSinceEpoch ~/ 1000);

      // U-ORPHAN: SELURUH riwayat ledger-nya ada di tahun yang akan diarsip.
      // Ini skenario bug: setelah delete, baris ledger-nya habis → tanpa fix,
      // stok jadi 0.
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl-orphan-1',
            productUnitId: 'U-ORPHAN',
            type: 'opening',
            qtyChange: 100,
            stockAfter: 100,
            createdAt: Value(inArchived.subtract(const Duration(days: 10))),
          ));
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl-orphan-2',
            productUnitId: 'U-ORPHAN',
            type: 'sale',
            qtyChange: -58,
            stockAfter: 42,
            createdAt: Value(inArchived),
          ));

      // U-KEEP: punya entri di tahun terarsip DAN tahun berjalan → setelah
      // delete, baris tahun-berjalan tetap ada, saldo tak perlu dibawa.
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl-keep-1',
            productUnitId: 'U-KEEP',
            type: 'opening',
            qtyChange: 100,
            stockAfter: 100,
            createdAt: Value(inArchived),
          ));
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl-keep-2',
            productUnitId: 'U-KEEP',
            type: 'sale',
            qtyChange: -20,
            stockAfter: 80,
            createdAt: Value(inCurrent),
          ));

      final stockOrphanBefore = await db.currentStock('U-ORPHAN');
      final stockKeepBefore = await db.currentStock('U-KEEP');
      expect(stockOrphanBefore, 42);
      expect(stockKeepBefore, 80);

      // ── Jalankan tutup buku SUNGGUHAN (bukan reimplementasi) ──────────────
      final result = await TutupBukuService.execute(db: db, year: archivedYear);

      expect(result.archivedYear, archivedYear);
      expect(result.txArchived, 1, reason: 'hanya tx-arch yang di tahun terarsip');
      expect(File(result.archivePath).existsSync(), isTrue,
          reason: 'file arsip harus benar-benar tercipta di disk');

      // Transaksi tahun terarsip terhapus dari DB utama; tahun berjalan tetap ada.
      final remainingTx = await db.select(db.transactions).get();
      expect(remainingTx.map((t) => t.id), equals(['tx-cur']));

      // Inti perbaikan: stok U-ORPHAN TIDAK reset ke 0 walau seluruh ledger-nya
      // ikut terhapus bersama tahun yang diarsipkan.
      final stockOrphanAfter = await db.currentStock('U-ORPHAN');
      expect(stockOrphanAfter, 42,
          reason: 'saldo harus dibawa via entri adjustment baru, bukan hilang');

      // U-KEEP tidak terganggu (baris tahun-berjalannya memang masih ada).
      final stockKeepAfter = await db.currentStock('U-KEEP');
      expect(stockKeepAfter, 80);

      // Verifikasi entri carry-forward benar-benar baris BARU beralasan jelas,
      // bukan kebetulan baris lama yang lolos delete.
      final orphanLedger = await (db.select(db.stockLedger)
            ..where((t) => t.productUnitId.equals('U-ORPHAN')))
          .get();
      expect(orphanLedger.length, 1,
          reason: '2 baris lama terhapus, 1 baris carry-forward baru tersisa');
      expect(orphanLedger.single.type, 'adjustment');
      expect(orphanLedger.single.note, contains('tutup buku'));

      await db.close();
    });

    test('tidak ada saldo yang perlu dibawa (semua unit punya sisa riwayat) → tanpa entri tambahan',
        () async {
      final dbFile = File('${tempDir.path}/the_pos.db');
      final db = AppDatabase(NativeDatabase(dbFile));
      const archivedYear = 2024;
      final inArchived = DateTime(archivedYear, 3, 1);
      final inCurrent = DateTime(archivedYear + 1, 2, 1);

      await _insertTx(db,
          id: 'tx-cur',
          localId: 'K1-B',
          status: 'lunas',
          total: 20000,
          paid: 20000,
          createdAtSec: inCurrent.millisecondsSinceEpoch ~/ 1000);

      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl-1',
            productUnitId: 'U-X',
            type: 'opening',
            qtyChange: 50,
            stockAfter: 50,
            createdAt: Value(inArchived),
          ));
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl-2',
            productUnitId: 'U-X',
            type: 'sale',
            qtyChange: -10,
            stockAfter: 40,
            createdAt: Value(inCurrent),
          ));

      await TutupBukuService.execute(db: db, year: archivedYear);

      final ledger = await (db.select(db.stockLedger)
            ..where((t) => t.productUnitId.equals('U-X')))
          .get();
      expect(ledger.length, 1, reason: 'tidak ada carry-forward yang perlu ditambahkan');
      expect(ledger.single.id, 'sl-2');
      expect(await db.currentStock('U-X'), 40);

      await db.close();
    });
  });
}
