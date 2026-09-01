import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/produk/cek_stok_screen.dart';
import 'package:the_pos/features/produk/reset_stock_screen.dart';

import 'helpers/pump_app.dart';

/// Susulan (permintaan user): "Reset Stok" — timpa stok produk terpilih
/// (seluruh atau satu kategori) jadi 0 sekaligus, TANPA hitung fisik (beda
/// dari Stock Opname biasa). Alur: pilih cakupan → review daftar dampak
/// (Sistem vs Baru=0) → dialog "ketik RESET" → commit lewat
/// `AppDatabase.commitOpname` (numpang mekanisme opname yang sudah ada).
void main() {
  Future<String> addProduct(AppDatabase db, String name,
      {double initialStock = 0, int? groupId}) async {
    final id = 'p-$name';
    final unitId = '$id-u';
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: id, name: name, productGroupId: Value(groupId)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
        ));
    if (initialStock != 0) {
      await db.adjustStock(productUnitId: unitId, newQty: initialStock);
    }
    return unitId;
  }

  testWidgets(
      'tombol "Reset Stok" HANYA muncul utk owner, tidak utk kasir/asisten',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await pumpWithFakeApp(tester,
        db: db,
        child: const CekStokScreen(),
        device: const DeviceIdentity(
          storeUuid: 'test-store-uuid',
          storeKey: 'test-store-key',
          storeName: 'Toko Uji',
          deviceName: 'Kasir Uji',
          deviceCode: 'K1',
          deviceRole: 'kasir',
        ));
    expect(find.byTooltip('Reset Stok'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('owner melihat tombol "Reset Stok" di Cek Stok', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    expect(find.byTooltip('Reset Stok'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'produk yang stoknya SUDAH 0 tidak ikut ke daftar review (tidak ada '
      'yang perlu diubah)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await addProduct(db, 'Beras', initialStock: 10);
    await addProduct(db, 'Air Kosong', initialStock: 0);

    await pumpWithFakeApp(tester, db: db, child: const ResetStockScreen());
    await tester.tap(find.text('Lihat & Reset'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Beras'), findsOneWidget);
    expect(find.textContaining('Air Kosong'), findsNothing,
        reason: 'stok yang sudah 0 tidak ada selisih, tidak perlu direset');
    expect(find.text('1 produk akan direset ke 0 (seluruh kategori)'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'cakupan "Semua" tanpa produk berstok -> pesan ditolak, TIDAK lanjut '
      'ke review', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await addProduct(db, 'Kosong', initialStock: 0);

    await pumpWithFakeApp(tester, db: db, child: const ResetStockScreen());
    await tester.tap(find.text('Lihat & Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Tidak ada produk berstok di cakupan ini'),
        findsOneWidget);
    expect(find.text('Review Reset Stok'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tombol "Reset ke 0" di review TIDAK langsung commit — wajib ketik '
      'RESET dulu di dialog konfirmasi', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final u = await addProduct(db, 'Gula', initialStock: 10);

    await pumpWithFakeApp(tester, db: db, child: const ResetStockScreen());
    await tester.tap(find.text('Lihat & Reset'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset ke 0'));
    await tester.pumpAndSettle();

    expect(find.text('Reset Stok?'), findsOneWidget);
    // Tombol "Reset ke 0" di DIALOG (bukan yg di layar review, sudah
    // tertutup) harus disabled sebelum teks konfirmasi cocok.
    final dialogButton = tester.widget<FilledButton>(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Reset ke 0')));
    expect(dialogButton.onPressed, isNull);
    expect(await db.currentStock(u), 10,
        reason: 'belum commit apa pun sebelum konfirmasi diketik benar');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'ketik RESET lalu konfirmasi -> stok seluruh produk terpilih jadi 0, '
      'tersimpan ke stock_ledger via commitOpname (muncul di riwayat '
      'opname)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final u1 = await addProduct(db, 'Gula', initialStock: 10);
    final u2 = await addProduct(db, 'Kopi', initialStock: 3);

    await pumpWithFakeApp(tester, db: db, child: const ResetStockScreen());
    await tester.tap(find.text('Lihat & Reset'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset ke 0'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'RESET');
    await tester.pumpAndSettle();

    final dialogButton = tester.widget<FilledButton>(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Reset ke 0')));
    expect(dialogButton.onPressed, isNotNull);

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Reset ke 0')));
    await tester.pumpAndSettle();

    expect(await db.currentStock(u1), 0);
    expect(await db.currentStock(u2), 0);

    final sessions = await db.getOpnameSessions();
    expect(sessions.length, 1);
    expect(sessions.first.note, contains('Reset ke 0'));
    expect(sessions.first.itemCount, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('cakupan per-kategori: reset HANYA produk di kategori itu, '
      'produk kategori lain TIDAK tersentuh', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db.into(db.productGroups).insert(ProductGroupsCompanion.insert(
        id: const Value(1), name: const Value('Rokok')));
    const rokokId = 1;
    final uRokok =
        await addProduct(db, 'Rokok A', initialStock: 12, groupId: rokokId);
    final uLain = await addProduct(db, 'Minyak', initialStock: 5);

    await pumpWithFakeApp(tester, db: db, child: const ResetStockScreen());
    await tester.tap(find.text('Rokok'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat & Reset'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Rokok A'), findsOneWidget);
    expect(find.textContaining('Minyak'), findsNothing);

    await tester.tap(find.text('Reset ke 0'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'RESET');
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Reset ke 0')));
    await tester.pumpAndSettle();

    expect(await db.currentStock(uRokok), 0);
    expect(await db.currentStock(uLain), 5,
        reason: 'produk di luar kategori terpilih tidak boleh ikut direset');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
