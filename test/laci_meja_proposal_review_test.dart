import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/features/pengaturan/sync_screen.dart';

/// Item 52 ("Laci Meja") — layar review usulan client->host (bagian yang
/// sengaja ditunda saat eksekusi awal Item 52, lihat docs/HANDOFF.md).
/// PARALEL dari review usulan produk (Item 40) — pola test sama:
/// `debugAddLaciMejaProposal` (seam test-only, TANPA host/HTTP sungguhan —
/// lihat dok panjang di `sync_screen_host_lifecycle_test.dart` soal
/// `testWidgets` + `HttpServer` asli yang bikin hang).
void main() {
  const ownerDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'O1',
      deviceRole: 'owner');

  tearDown(() {
    LanSyncService.debugHostRunningOverride = false;
    LanSyncService.debugClearLaciMejaProposals();
  });

  testWidgets(
      'kartu "Usulan Laci Meja" tampil di layar Sync, tap Tinjau -> baris '
      'muncul di layar review, Terapkan -> tertulis ke DB host & antrian '
      'kosong', (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);

    // Bangun usulan NYATA (row-set asli hasil dumpLaciMejaProposals) dari
    // DB kasir simulasi, bukan data palsu.
    final kasirDb = AppDatabase(NativeDatabase.memory());
    await kasirDb.into(kasirDb.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'tx1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await kasirDb.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Payung',
        jenis: 'titip',
        customerNameText: 'Budi',
        locallyModified: true);
    await kasirDb.addBorrowedItem(
        id: 'b1',
        transactionId: 'tx1',
        itemName: 'Galon Aqua',
        qty: 3,
        locallyModified: true);
    final rows = await kasirDb.dumpLaciMejaProposals();
    await kasirDb.close();

    LanSyncService.debugHostRunningOverride = true;
    LanSyncService.debugAddLaciMejaProposal(PendingLaciMejaProposal(
      id: 'prop1',
      fromIp: '192.168.2.50',
      arrivedAt: DateTime.now(),
      rows: rows,
      entryCount: 2,
    ));

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(hostDb),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SyncScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Usulan Laci Meja (1)'), findsOneWidget);
    expect(find.textContaining('2 entri diusulkan'), findsOneWidget);

    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();

    expect(find.text('Titip/Ketinggalan (1)'), findsOneWidget);
    expect(find.text('Payung'), findsOneWidget);
    expect(find.textContaining('Dititip — Budi'), findsOneWidget);
    expect(find.text('Pinjaman Barang (1)'), findsOneWidget);
    expect(find.text('Galon Aqua'), findsOneWidget);

    await tester.tap(find.text('Terapkan (2 baris)'));
    await tester.pumpAndSettle();

    // Kembali ke layar Sync, antrian usulan Laci Meja sudah kosong.
    expect(find.textContaining('Usulan Laci Meja'), findsNothing);

    final leftBehindRows = await hostDb.select(hostDb.leftBehindItems).get();
    expect(leftBehindRows, hasLength(1));
    expect(leftBehindRows.single.itemName, 'Payung');
    expect(leftBehindRows.single.locallyModified, isFalse,
        reason: 'owner sudah approve, flag usulan dilepas');

    final borrowedRows = await hostDb.select(hostDb.borrowedItems).get();
    expect(borrowedRows, hasLength(1));
    expect(borrowedRows.single.itemName, 'Galon Aqua');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'uncheck salah satu baris sebelum Terapkan -> baris itu TIDAK ikut '
      'tertulis ke DB host', (tester) async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);

    final kasirDb = AppDatabase(NativeDatabase.memory());
    await kasirDb.into(kasirDb.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'tx1',
          status: 'lunas',
          total: 10000,
          paid: 10000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
    await kasirDb.addLeftBehindItem(
        id: 'l1',
        transactionId: 'tx1',
        itemName: 'Payung',
        jenis: 'titip',
        locallyModified: true);
    await kasirDb.addLeftBehindItem(
        id: 'l2',
        transactionId: 'tx1',
        itemName: 'Topi',
        jenis: 'ketinggalan',
        locallyModified: true);
    final rows = await kasirDb.dumpLaciMejaProposals();
    await kasirDb.close();

    LanSyncService.debugHostRunningOverride = true;
    LanSyncService.debugAddLaciMejaProposal(PendingLaciMejaProposal(
      id: 'prop1',
      fromIp: '192.168.2.50',
      arrivedAt: DateTime.now(),
      rows: rows,
      entryCount: 2,
    ));

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(hostDb),
      deviceProvider.overrideWith((ref) => DeviceNotifier()..state = ownerDevice),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SyncScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tinjau'));
    await tester.pumpAndSettle();

    // Semua default tercentang -> uncheck "Topi".
    await tester.tap(find.text('Topi'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Terapkan (1 baris)'));
    await tester.pumpAndSettle();

    final leftBehindRows = await hostDb.select(hostDb.leftBehindItems).get();
    expect(leftBehindRows, hasLength(1));
    expect(leftBehindRows.single.itemName, 'Payung');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
