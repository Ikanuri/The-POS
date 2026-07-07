import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';

/// Harness widget test: render [child] dengan `databaseProvider` &
/// `deviceProvider` diganti versi palsu, tanpa device/SQLCipher sungguhan.
///
/// Hampir semua screen di app ini memanggil `ref.watch(databaseProvider)`,
/// yang pada kondisi asli akan throw kalau device belum "configured"
/// (`DeviceIdentity.isConfigured`). Fungsi ini membuat device selalu
/// dianggap sudah configured & terhubung ke [db] palsu (biasanya
/// `AppDatabase(NativeDatabase.memory())` yang sudah diisi data uji SEBELUM
/// dipanggil), sehingga screen bisa dirender & diuji tanpa emulator/device
/// asli.
///
/// Tidak menyertakan `GoRouter` — cukup untuk widget yang navigasinya hanya
/// terpicu saat tombol tertentu DI-TAP (bukan saat build). Kalau butuh
/// menguji alur navigasi sungguhan, bungkus [child] dengan router terpisah
/// di test yang bersangkutan.
///
/// [surfaceSize] dibuat generus panjangnya (default): banyak screen di app
/// ini (mis. ReceiptScreen) memakai `ListView(children: [...])` yang me-
/// LAZY-BUILD anak di luar viewport — kalau layar test terlalu pendek,
/// tombol yang secara visual "di bawah" (mis. Retur/Batalkan) tidak ikut
/// ter-build sama sekali sehingga `find.text(...)` tidak akan menemukannya,
/// padahal bukan itu yang mau diuji. Perbesar tinggi surface menghindari
/// kelas masalah ini tanpa perlu scroll manual di tiap test.
///
/// [child] dibungkus `Scaffold` — beberapa widget (mis. `TxHistorySheet`)
/// didesain untuk dipakai di dalam `showModalBottomSheet` yang secara
/// otomatis menyediakan ancestor `Material` (dibutuhkan mis. oleh
/// `TextField`); tanpa Scaffold di sini, widget seperti itu akan error
/// "No Material widget found" walau di app sungguhan tidak pernah bermasalah.
Future<void> pumpWithFakeApp(
  WidgetTester tester, {
  required AppDatabase db,
  required Widget child,
  DeviceIdentity? device,
  Size surfaceSize = const Size(430, 2400),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});

  final fakeDevice = device ??
      const DeviceIdentity(
        storeUuid: 'test-store-uuid',
        storeKey: 'test-store-key',
        storeName: 'Toko Uji',
        deviceName: 'Kasir Uji',
        deviceCode: 'K1',
        deviceRole: 'owner',
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    ),
  );
  // Beberapa screen memuat data lewat rantai FutureProvider (mis.
  // _txHistoryProvider yang bergantung pada databaseProvider).
  await tester.pumpAndSettle();
}
