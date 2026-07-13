import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Item 24b — sheet "Verifikasi Pesanan": tap kartu antrian handoff pegawai
/// (awaitingPayment) buka sheet checklist dulu (pegawai bacakan barang,
/// owner centang) sebelum lanjut ke keranjang untuk bayar. Pesanan ditahan
/// BIASA (bukan handoff) tetap langsung resume seperti sebelumnya — tanpa
/// sheet verifikasi, karena tidak ada yang perlu diverifikasi.
void main() {
  Future<AppDatabase> seedProduct() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1',
          productUnitId: 'u1',
          minQty: const Value(1),
          price: 2500,
        ));
    return db;
  }

  Future<void> pumpKasir(WidgetTester tester, AppDatabase db) async {
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const fakeDevice = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Owner',
      deviceCode: 'K1',
      deviceRole: 'owner',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        deviceProvider.overrideWith((ref) => DeviceNotifier()..state = fakeDevice),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: KasirScreen()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openAntrianPanel(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.pause_circle_outline_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'tap kartu antrian handoff (awaitingPayment) → buka sheet '
      'Verifikasi Pesanan, BUKAN langsung resume ke keranjang',
      (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());
    await db.holdOrder(
      id: 'h1',
      label: 'Budi',
      cartJson:
          '{"items":[{"productId":"p1","productUnitId":"u1","productName":'
          '"Sedap Goreng","unitName":"Pcs","qty":2,"price":2500,'
          '"originalPrice":2500,"costPrice":0}],"meta":{},'
          '"awaitingPayment":true}',
    );

    await pumpKasir(tester, db);
    await openAntrianPanel(tester);
    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();

    expect(find.text('Verifikasi Pesanan · Budi'), findsOneWidget);
    expect(find.text('Sedap Goreng'), findsWidgets);
    // Keranjang belum berubah — antrian belum di-resume.
    final rows = await db.select(db.heldOrders).get();
    expect(rows, hasLength(1), reason: 'belum di-resume, masih di antrian');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'centang item di sheet verifikasi tersimpan permanen ke held_orders '
      '(bertahan walau sheet ditutup tanpa "Lanjut")', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());
    await db.holdOrder(
      id: 'h1',
      label: 'Budi',
      cartJson:
          '{"items":[{"productId":"p1","productUnitId":"u1","productName":'
          '"Sedap Goreng","unitName":"Pcs","qty":2,"price":2500,'
          '"originalPrice":2500,"costPrice":0}],"meta":{},'
          '"awaitingPayment":true}',
    );

    await pumpKasir(tester, db);
    await openAntrianPanel(tester);
    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    final rows = await db.select(db.heldOrders).get();
    expect(rows.single.cartJson, contains('"checked":[true]'),
        reason: 'centangan harus langsung ditulis ke DB, bukan cuma state widget');

    // Tutup sheet TANPA tekan "Lanjut" (drag/back) — buka lagi, centangan
    // harus masih ada (bukti persisted, bukan cuma state sheet lama).
    Navigator.of(tester.element(find.byType(Checkbox))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tombol "Lanjut ke Keranjang" menutup sheet, hapus dari antrian, '
      'isi keranjang aktif dengan barangnya', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());
    await db.holdOrder(
      id: 'h1',
      label: 'Budi',
      cartJson:
          '{"items":[{"productId":"p1","productUnitId":"u1","productName":'
          '"Sedap Goreng","unitName":"Pcs","qty":2,"price":2500,'
          '"originalPrice":2500,"costPrice":0}],"meta":{},'
          '"awaitingPayment":true}',
    );

    await pumpKasir(tester, db);
    await openAntrianPanel(tester);
    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Lanjut ke Keranjang'));
    await tester.pumpAndSettle();

    expect(find.text('Verifikasi Pesanan · Budi'), findsNothing);
    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty, reason: 'antrian sudah di-resume ke keranjang aktif');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'pesanan ditahan BIASA (bukan handoff pegawai) tap langsung resume, '
      'TANPA sheet verifikasi', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());
    await db.holdOrder(
      id: 'h1',
      label: 'Pelanggan Umum',
      cartJson:
          '{"items":[{"productId":"p1","productUnitId":"u1","productName":'
          '"Sedap Goreng","unitName":"Pcs","qty":1,"price":2500,'
          '"originalPrice":2500,"costPrice":0}],"meta":{}}',
    );

    await pumpKasir(tester, db);
    await openAntrianPanel(tester);
    await tester.tap(find.text('Pelanggan Umum'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Verifikasi Pesanan'), findsNothing,
        reason: 'pesanan ditahan biasa tidak perlu diverifikasi');
    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty, reason: 'langsung resume seperti perilaku sebelumnya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
