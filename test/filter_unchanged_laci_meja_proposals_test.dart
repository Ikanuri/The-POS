import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug nyata dilaporkan user: pre-order yang sudah "Dipenuhi" TETAP terus
/// diusulkan ulang ke owner tiap sync, walau ownernya sudah menerapkan
/// usulan itu sebelumnya — `dumpLaciMejaProposals` cuma memfilter
/// `locally_modified = 1`, tanpa membandingkan isinya thd data host (beda
/// dari usulan produk Item 40 yang sudah punya `filterUnchangedProposals`).
/// Test ini level DB murni utk `filterUnchangedLaciMejaProposals` — test
/// end-to-end lewat HTTP sungguhan ada di
/// `laci_meja_proposal_unchanged_end_to_end_test.dart`.
void main() {
  late AppDatabase hostDb;
  setUp(() => hostDb = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => hostDb.close());

  Future<String> seedTransaction(String id) async {
    await hostDb.into(hostDb.transactions).insert(TransactionsCompanion.insert(
          id: id,
          localId: id,
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    return id;
  }

  test(
      'pre-order yang sudah Dipenuhi & IDENTIK dgn host (cuma locally_modified/'
      'updated_at beda) DIBUANG dari usulan', () async {
    final txId = await seedTransaction('tx1');
    // Host SUDAH punya versi "sudah dipenuhi" ini (owner sudah approve
    // usulan sebelumnya).
    await hostDb.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        transactionId: txId,
        customerName: 'Budi',
        qtyOrdered: 2);
    await hostDb.fulfillPreorderEntry('p1');

    final hostRow =
        (await (hostDb.select(hostDb.preorderEntries)..where((t) => t.id.equals('p1')))
                .get())
            .single;

    // Usulan dari klien: PERSIS sama isinya (sudah fulfilled) — bedanya
    // cuma locally_modified=1 (macet, blm ke-reset) & updated_at klien.
    final proposalRow = {
      'id': 'p1',
      'product_id': 'prod1',
      'product_unit_id': 'unit1',
      'transaction_id': txId,
      'customer_name': 'Budi',
      'phone': null,
      'qty_ordered': 2.0,
      'deposit_qty': 0.0,
      'paid': 0,
      'note': null,
      'fulfilled_at': hostRow.fulfilledAt!.millisecondsSinceEpoch ~/ 1000,
      'cancelled_at': null,
      'locally_modified': 1,
      'created_at': hostRow.createdAt.millisecondsSinceEpoch ~/ 1000,
      'updated_at': 9999999999, // beda sengaja — bookkeeping, harus diabaikan
    };

    final filtered = await hostDb.filterUnchangedLaciMejaProposals(
        {'preorder_entries': [proposalRow]});

    expect(filtered, isEmpty,
        reason: 'baris identik (kecuali locally_modified/updated_at) harus '
            'dibuang, bukan diusulkan lagi ke owner');
  });

  test(
      'pre-order yang GENUINELY beda (mis. baru dibatalkan klien, host '
      'belum tahu) TETAP lolos filter', () async {
    final txId = await seedTransaction('tx1');
    await hostDb.addPreorderEntry(
        id: 'p1',
        productId: 'prod1',
        productUnitId: 'unit1',
        transactionId: txId,
        customerName: 'Budi',
        qtyOrdered: 2);
    // Host BELUM tahu ini sudah dibatalkan (cancelled_at masih null).

    final proposalRow = {
      'id': 'p1',
      'product_id': 'prod1',
      'product_unit_id': 'unit1',
      'transaction_id': txId,
      'customer_name': 'Budi',
      'phone': null,
      'qty_ordered': 2.0,
      'deposit_qty': 0.0,
      'paid': 0,
      'note': null,
      'fulfilled_at': null,
      'cancelled_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'locally_modified': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    final filtered = await hostDb.filterUnchangedLaciMejaProposals(
        {'preorder_entries': [proposalRow]});

    expect(filtered['preorder_entries'], hasLength(1),
        reason: 'perubahan sungguhan (baru dibatalkan) harus tetap muncul '
            'utk ditinjau owner');
  });

  test('baris yang BELUM ADA di host (baru) selalu lolos filter', () async {
    final proposalRow = {
      'id': 'p-new',
      'product_id': 'prod1',
      'product_unit_id': 'unit1',
      'transaction_id': null,
      'customer_name': 'Ani',
      'phone': null,
      'qty_ordered': 1.0,
      'deposit_qty': 0.0,
      'paid': 0,
      'note': null,
      'fulfilled_at': null,
      'cancelled_at': null,
      'locally_modified': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    };

    final filtered = await hostDb.filterUnchangedLaciMejaProposals(
        {'preorder_entries': [proposalRow]});

    expect(filtered['preorder_entries'], hasLength(1),
        reason: 'tidak ada pembanding di host — harus tetap lolos');
  });
}
