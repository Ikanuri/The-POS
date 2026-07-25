import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/kasir_screen.dart';

/// Permintaan user — sheet "Verifikasi Pesanan" (Item 24b, centang barang
/// sebelum lanjut bayar) DIHAPUS: tap kartu antrian handoff pegawai via QR
/// sekarang langsung resume ke keranjang aktif, sama seperti pesanan
/// ditahan biasa — pengirim sudah menyusun barangnya sendiri, tidak perlu
/// dicek ulang lagi oleh penerima.
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
      'tap kartu antrian handoff (awaitingPayment) → langsung resume ke '
      'keranjang aktif, TANPA sheet verifikasi/centang apa pun',
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

    expect(find.textContaining('Verifikasi Pesanan'), findsNothing,
        reason: 'sheet centang sudah dihapus');
    expect(find.byType(Checkbox), findsNothing);
    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty,
        reason: 'langsung di-resume ke keranjang aktif, tanpa langkah antara');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'pesanan ditahan BIASA (bukan handoff pegawai) juga tap langsung '
      'resume', (tester) async {
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
        reason: 'pesanan ditahan biasa tidak pernah punya sheet verifikasi');
    final rows = await db.select(db.heldOrders).get();
    expect(rows, isEmpty, reason: 'langsung resume seperti perilaku sebelumnya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap DI LUAR wadah panel "Pesanan Ditahan" (mis. grid produk di '
      'bawahnya) menutup panel-nya saja, dengan animasi (AnimatedSize)',
      (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());
    await db.holdOrder(
      id: 'h1',
      label: 'Budi',
      cartJson:
          '{"items":[{"productId":"p1","productUnitId":"u1","productName":'
          '"Sedap Goreng","unitName":"Pcs","qty":2,"price":2500,'
          '"originalPrice":2500,"costPrice":0}],"meta":{}}',
    );

    await pumpKasir(tester, db);
    await openAntrianPanel(tester);
    expect(find.text('PESANAN DITAHAN'), findsOneWidget);

    // Titik jauh di bawah panel (panel selalu ada di atas grid produk) —
    // pasti di luar wadahnya berapa pun tinggi kontennya.
    await tester.tapAt(const Offset(200, 2300));
    await tester.pump(); // mulai animasi tutup
    await tester.pumpAndSettle();

    expect(find.text('PESANAN DITAHAN'), findsNothing,
        reason: 'tap di luar wadah panel harus menutup panelnya');

    final rows = await db.select(db.heldOrders).get();
    expect(rows, hasLength(1),
        reason: 'tap di luar cuma menutup panel, TIDAK meresume/menghapus '
            'antrian yang ada di dalamnya');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets(
      'tap DI DALAM wadah panel (bukan kartu antrian, mis. judul '
      '"PESANAN DITAHAN") TIDAK menutup panel', (tester) async {
    final db = await seedProduct();
    addTearDown(() async => db.close());
    await db.holdOrder(
      id: 'h1',
      label: 'Budi',
      cartJson:
          '{"items":[{"productId":"p1","productUnitId":"u1","productName":'
          '"Sedap Goreng","unitName":"Pcs","qty":2,"price":2500,'
          '"originalPrice":2500,"costPrice":0}],"meta":{}}',
    );

    await pumpKasir(tester, db);
    await openAntrianPanel(tester);

    await tester.tap(find.text('PESANAN DITAHAN'));
    await tester.pumpAndSettle();

    expect(find.text('PESANAN DITAHAN'), findsOneWidget,
        reason: 'tap di dalam wadah panel TIDAK boleh ikut menutup panel');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
