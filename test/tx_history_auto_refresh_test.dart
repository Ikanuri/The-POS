import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/widgets/tx_history_sheet.dart';

/// Membuktikan perbaikan "Opsi C": transaksi baru yang dibuat SETELAH sheet
/// Riwayat Transaksi ditutup harus langsung terlihat saat sheet dibuka lagi,
/// TANPA perlu menekan tombol refresh manual. Sebelum fix ini, providernya
/// tetap ter-cache lintas tutup-buka (bukan sekali per widget lifetime),
/// jadi transaksi baru bisa "hilang" sampai tombol refresh ditekan.
///
/// Test ini SENGAJA tidak pakai helper `pumpWithFakeApp` — perlu ProviderScope
/// yang sama tetap hidup saat sheet ditutup-buka (beda widget instance, tapi
/// container Riverpod yang sama, persis kondisi nyata di aplikasi), bukan
/// ProviderScope baru yang mereset semua cache.
Future<void> _insertTx(AppDatabase db,
    {required String id, required String localId}) async {
  await db.into(db.transactions).insert(TransactionsCompanion.insert(
        id: id,
        localId: localId,
        status: 'lunas',
        total: 10000,
        paid: 10000,
        changeAmount: 0,
        paymentMethod: 'tunai',
      ));
}

void main() {
  testWidgets(
      'transaksi baru setelah sheet ditutup langsung muncul saat sheet '
      'dibuka lagi, tanpa tekan tombol refresh manual', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _insertTx(db, id: 'tx-lama', localId: 'K1-1');

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});

    const fakeDevice = DeviceIdentity(
      storeUuid: 'test-store-uuid',
      storeKey: 'test-store-key',
      storeName: 'Toko Uji',
      deviceName: 'Kasir Uji',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    var showSheet = true;
    late StateSetter setOuterState;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) {
              setOuterState = setState;
              return Scaffold(
                  body: showSheet ? const TxHistorySheet() : const SizedBox());
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('K1-1'), findsOneWidget);

    // "Tutup" sheet — widget-nya di-dispose, tapi ProviderScope/container
    // tetap hidup (persis seperti navigasi Navigator.pop di aplikasi asli).
    setOuterState(() => showSheet = false);
    await tester.pumpAndSettle();

    // Transaksi baru masuk SETELAH sheet ditutup (mis. checkout di Kasir).
    await _insertTx(db, id: 'tx-baru', localId: 'K1-2');

    // "Buka lagi" — instance widget BARU, tapi cache provider dari sebelum
    // sheet ditutup masih ada di container yang sama.
    setOuterState(() => showSheet = true);
    await tester.pumpAndSettle();

    expect(find.text('K1-2'), findsOneWidget,
        reason:
            'transaksi baru harus langsung terlihat saat sheet dibuka lagi, '
            'TANPA tekan tombol refresh manual');

    await db.close();
  });
}
