import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';

/// Susulan (permintaan user): "buat opsi usulan juga ketika disync (entah
/// itu ubah data atau tambah baru)" utk pelanggan — sinkronisasi end-to-end
/// ASLI (real HTTP loopback, bukan simulasi payload manual, sesuai standar
/// test Networking di CLAUDE.md). Sebelum ini, pelanggan yang
/// ditambah/diubah di device NON-owner TIDAK PERNAH sampai ke host sama
/// sekali (customers = master data, sengaja tidak diupload klien->host)
/// — sekarang lewat antrian usulan terpisah, pola SAMA PERSIS dgn Item 40
/// (produk) & Item 52 (Laci Meja).
Future<T> _withRealHttp<T>(Future<T> Function() body) => HttpOverrides.runZoned(
      body,
      createHttpClient: (context) => Zone.root.run(() {
        final prevGlobal = HttpOverrides.current;
        HttpOverrides.global = null;
        try {
          return HttpClient(context: context);
        } finally {
          HttpOverrides.global = prevGlobal;
        }
      }),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/network_info'),
          (call) async => call.method == 'wifiIPAddress' ? '127.0.0.1' : null);

  tearDown(() async {
    await LanSyncService.stopHost();
    LanSyncService.debugClearProposals();
    LanSyncService.debugClearCustomerProposals();
  });

  test(
      'klien -> host: pelanggan BARU dibuat device NON-owner '
      '(locallyModified=true) TIDAK auto-merge, masuk antrian usulan '
      'terpisah menunggu approve owner', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.customers).insert(CustomersCompanion.insert(
          id: 'c-new',
          name: 'Pelanggan Baru dari Kasir',
          locallyModified: const Value(true),
        ));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
          deviceCode: 'K1',
        ));

    // TIDAK auto-merge ke tabel host: harus menunggu review, sama seperti
    // usulan produk/Laci Meja.
    final hostCustomers = await (hostDb.select(hostDb.customers)).get();
    expect(hostCustomers, isEmpty,
        reason: 'usulan client->host wajib lewat review dulu, bukan '
            'langsung masuk tabel host (customers = master data)');

    expect(LanSyncService.pendingCustomerProposals, hasLength(1));
    final proposal = LanSyncService.pendingCustomerProposals.single;
    expect(proposal.customerCount, 1);
    expect(proposal.rows.single['id'], 'c-new');
    expect(proposal.rows.single['name'], 'Pelanggan Baru dari Kasir');

    final applied = await LanSyncService.applyCustomerProposal(
        proposal.id, {'c-new'});
    expect(applied, 1);
    expect(LanSyncService.pendingCustomerProposals, isEmpty);

    final hostRows = await (hostDb.select(hostDb.customers)).get();
    expect(hostRows, hasLength(1));
    expect(hostRows.single.locallyModified, isFalse,
        reason: 'setelah owner approve, flag usulan dilepas (host adalah '
            'sumber kebenaran sekarang)');
  });

  test(
      'usulan produk (Item 40) dan usulan pelanggan BENAR-BENAR independen '
      '— satu ada isinya, satunya kosong, tidak saling mengganggu',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await clientDb.into(clientDb.products).insert(ProductsCompanion.insert(
          id: 'p-new',
          name: 'Produk Baru',
          locallyModified: const Value(true),
        ));
    await clientDb.into(clientDb.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'p-new-u',
          productId: 'p-new',
          isBaseUnit: const Value(true),
        ));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    expect(LanSyncService.pendingProposals, hasLength(1),
        reason: 'usulan produk tetap berjalan normal');
    expect(LanSyncService.pendingCustomerProposals, isEmpty,
        reason: 'tidak ada pelanggan yang diusulkan, antrian itu harus '
            'tetap kosong (bukan ikut terisi/error)');
  });

  test(
      'pelanggan yang DIUBAH (bukan cuma baru) di device non-owner juga '
      'masuk usulan, membawa data TERBARU (nama/HP yang sudah diedit)',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Pelanggan sudah ada (mis. hasil sync host->klien sebelumnya).
    await clientDb.into(clientDb.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Budi',
        ));
    // Kasir ubah nomor HP-nya.
    await clientDb.markCustomerLocallyModified('c1');
    await (clientDb.update(clientDb.customers)
          ..where((t) => t.id.equals('c1')))
        .write(const CustomersCompanion(phone: Value('081234567')));

    final (_, token) =
        await LanSyncService.startHost(db: hostDb, storeKey: 'shared-key');

    await _withRealHttp(() => LanSyncService.syncToHost(
          db: clientDb,
          storeKey: 'shared-key',
          hostIp: '127.0.0.1',
          syncToken: token,
        ));

    expect(LanSyncService.pendingCustomerProposals, hasLength(1));
    final proposal = LanSyncService.pendingCustomerProposals.single;
    expect(proposal.rows.single['phone'], '081234567',
        reason: 'usulan harus membawa data TERBARU (HP yg sudah diedit), '
            'bukan snapshot lama');
  });
}
