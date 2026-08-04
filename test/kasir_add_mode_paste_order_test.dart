import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): tombol "Tempel Pesanan" dulu sengaja
/// disembunyikan di mode "Tambah Belanjaan" (`KasirScreen(addToTxId:)`,
/// nota yang sudah checkout tempo/lunas) — sekarang diaktifkan juga di sana,
/// supaya pesanan tambahan (dari pelanggan via katalog HTML atau pegawai
/// tanpa izin terima_pembayaran) bisa ditempel ke nota yang sedang ditambah,
/// bukan cuma di kasir mode biasa.
///
/// `KasirScreen` pakai beberapa `StreamProvider` (drift `.watch()`, mis.
/// antrian held orders) — widget test yang MEMBUKANYA (walau cuma baca)
/// bisa HANG 10 menit penuh saat disposal kalau tidak di-`drain()` (lihat
/// CLAUDE.md §Gotcha). Tiap test di sini WAJIB ditutup dgn drain manual.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'mode Tambah Belanjaan (addToTxId) menampilkan tombol "Tempel '
      'Pesanan" juga (dulu disembunyikan)', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const KasirScreen(addToTxId: 'tx1'));

    expect(find.textContaining('Tempel'), findsOneWidget,
        reason: 'tombol Tempel Pesanan harus tampil di mode tambah belanjaan');

    await drain(tester);
  });

  testWidgets('kasir mode biasa tetap menampilkan tombol "Tempel Pesanan" '
      '(tidak terpengaruh perubahan ini)', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const KasirScreen());

    expect(find.textContaining('Tempel'), findsOneWidget);

    await drain(tester);
  });

  testWidgets('mode Katalog TETAP tidak menampilkan tombol "Tempel Pesanan" '
      '(bukan transaksi sungguhan)', (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const KasirScreen(catalogMode: true));

    expect(find.textContaining('Tempel'), findsNothing);

    await drain(tester);
  });
}
