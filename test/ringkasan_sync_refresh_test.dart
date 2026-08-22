import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/data_refresh_provider.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/ringkasan/ringkasan_screen.dart';

/// Bug nyata dilaporkan user: setelah KLIEN sync dari host (transaksi baru
/// masuk lewat `mergeRows`), total pendapatan hari ini di Ringkasan klien
/// TIDAK bertambah — walau data di DB lokal sudah benar (kelihatan kalau
/// user tekan tombol refresh manual). Akar masalah: `_ringkasanProvider`
/// (`ringkasan_screen.dart`) adalah `FutureProvider` biasa, TIDAK pernah
/// `.watch()` tabel `transactions` — hanya re-fetch saat dibuka pertama
/// kali, tombol refresh ditekan, atau (di layar Laporan) rentang tanggal
/// berubah. Insert baris baru ke DB (persis yg dilakukan `mergeRows` saat
/// sync) TIDAK otomatis memicu re-fetch.
///
/// Fix: `dataSyncedTickProvider` (`core/providers/data_refresh_provider.
/// dart`) di-`ref.watch()` di baris pertama provider ini, lalu di-bump oleh
/// `SyncStateNotifier` setiap kali sync SUNGGUHAN menerima data (baik
/// klien menerima dari host, maupun host menerima approve dari klien).
/// Test ini mensimulasikan itu SECARA LANGSUNG (bump tick manual, tanpa
/// menjalankan LAN sync sungguhan — sudah diuji terpisah di file lain)
/// untuk membuktikan providernya sendiri BENAR reaktif thd tick tsb.
void main() {
  testWidgets(
      'total pendapatan hari ini ikut BERTAMBAH begitu dataSyncedTickProvider '
      'di-bump (simulasi sync menerima transaksi baru), TANPA tap refresh',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = const DeviceIdentity(
          storeUuid: 's',
          storeKey: 'k',
          storeName: 'Toko',
          deviceName: 'Kasir',
          deviceCode: 'K1',
          deviceRole: 'owner',
        )),
    ]);
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: RingkasanScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // Awal: belum ada transaksi apa pun -> "Rp 0".
    expect(find.text(formatRupiah(0)), findsWidgets);

    // Simulasikan PERSIS efek `mergeRows` saat klien sync dari host: insert
    // langsung ke DB TANPA lewat provider/notifier app (raw write, sama spt
    // sync sungguhan menulis via `customInsert`).
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx-from-host',
          localId: 'HOST-1',
          status: 'lunas',
          total: 50000,
          paid: 50000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));

    // TANPA tap refresh sama sekali — cuma bump tick, persis yg dilakukan
    // `SyncStateNotifier.sync()`/`approveSync()` sesudah menerima data.
    container.read(dataSyncedTickProvider.notifier).state++;
    await tester.pumpAndSettle();

    expect(find.text(formatRupiah(50000)), findsWidgets,
        reason: 'total pendapatan hari ini HARUS ikut ter-refresh begitu '
            'tick sync di-bump, tanpa perlu tap tombol refresh manual');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
