import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;
import 'package:the_pos/features/produk/purchase_history_screen.dart';
import 'package:the_pos/features/produk/receive_goods_screen.dart';

import 'helpers/pump_app.dart';

/// PLAN Item 90 tahap 2-6 — layar Penerimaan Barang sbg Input Pembelian:
/// tempel hasil AI -> konfirmasi saran produk -> pratinjau HPP -> simpan;
/// peringatan; usulan HPP pegawai disetujui owner; riwayat & batalkan.
/// Lebar HP sempit (360) sesuai CLAUDE.md.
void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'P1', name: 'Terigu Payung'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'pak',
            productId: 'P1',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true),
            isNonStock: const Value(false)),
        ProductUnitsCompanion.insert(
            id: 'zak',
            productId: 'P1',
            unitTypeId: const Value(2),
            ratioToBase: const Value(4.0),
            isNonStock: const Value(false)),
      ],
      tiersByUnitTempId: {
        'pak': [
          PriceTiersCompanion.insert(
              id: 't1',
              productUnitId: 'pak',
              price: 45000,
              costPrice: const Value(36000)),
        ],
        'zak': [
          PriceTiersCompanion.insert(
              id: 't2',
              productUnitId: 'zak',
              price: 175000,
              costPrice: const Value(144000)),
        ],
      },
      barcodesByUnitTempId: const {},
    );
  });
  tearDown(() async => db.close());

  String aiReply({int price = 167621}) => '''```json
{"versi":1,"faktur":[{"nomor":"124256-RPS","supplier":"Indomarco",
"harga_termasuk_ppn":true,"baris":[{"nama":"Terigu Payung 5 kg","satuan":"ZAK",
"isi":4,"qty_besar":5,"qty_kecil":0,"harga_satuan":$price,
"potongan_persen":0,"potongan_rupiah":0,"product_unit_id":"zak","yakin":true}]}]}
```''';

  Future<int> cost() async => (await (db.select(db.priceTiers)
            ..where((t) => t.productUnitId.equals('pak')))
          .getSingle())
      .costPrice;

  Future<void> open(WidgetTester tester, {DeviceIdentity? device}) async {
    await pumpWithFakeApp(tester,
        db: db,
        device: device,
        child: const ReceiveGoodsScreen(),
        surfaceSize: const Size(360, 2400));
    await tester.pumpAndSettle();
  }

  Future<void> pasteAi(WidgetTester tester, String reply) async {
    await tester.tap(find.text('Hasil AI'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('purchase-ai-input')), reply);
    await tester.tap(find.byKey(const ValueKey('purchase-ai-process')));
    await tester.pumpAndSettle();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  const pegawai = DeviceIdentity(
    storeUuid: 'test-store-uuid',
    storeKey: 'test-store-key',
    storeName: 'Toko Uji',
    deviceName: 'HP Pegawai',
    deviceCode: 'K2',
    deviceRole: 'kasir',
  );

  testWidgets('owner: hasil AI -> saran produk wajib dikonfirmasi -> '
      'pratinjau HPP -> simpan (stok & HPP berubah, faktur tercatat)',
      (tester) async {
    await open(tester);
    await pasteAi(tester, aiReply());

    expect(find.text('Tambahkan 0 Barang ke Stok'), findsOneWidget,
        reason: 'saran AI belum dikonfirmasi -> belum boleh disimpan');
    await tester.tap(find.text('Benar, ini produknya'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining(
            '${formatRupiah(36000)} → ${formatRupiah(37752)}'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Tambahkan 1 Barang ke Stok'));
    await tester.pumpAndSettle();
    expect(await db.currentStock('pak'), 20);
    expect(await cost(), 37752);
    final head = (await db.select(db.purchases).get()).single;
    expect(head.invoiceNo, '124256-RPS');
    expect(head.status, 'received');
    expect(await db.resolveReceiveUnit(name: 'Terigu Payung 5 kg', unit: 'ZAK'),
        'zak', reason: 'saran AI yang dikonfirmasi dipelajari ke kamus');
    await drain(tester);
  });

  testWidgets('harga jual di bawah HPP baru & perubahan besar -> dialog '
      'peringatan sebelum simpan', (tester) async {
    await open(tester);
    await pasteAi(tester, aiReply(price: 200000));
    await tester.tap(find.text('Benar, ini produknya'));
    await tester.pumpAndSettle();
    expect(find.textContaining('di bawah HPP baru'), findsOneWidget);
    await tester.tap(find.text('Tambahkan 1 Barang ke Stok'));
    await tester.pumpAndSettle();
    expect(find.text('Periksa dulu'), findsOneWidget);
    await tester.tap(find.text('Cek lagi'));
    await tester.pumpAndSettle();
    expect(await cost(), 36000, reason: 'belum disimpan');
    await drain(tester);
  });

  testWidgets('pegawai berizin: HPP jadi usulan; owner menyetujui dari '
      'bagian "Menunggu persetujuan"', (tester) async {
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('input_pembelian')))
        .write(const KasirPermissionsCompanion(isEnabled: Value(true)));
    await open(tester, device: pegawai);
    await pasteAi(tester, aiReply());
    await tester.tap(find.text('Benar, ini produknya'));
    await tester.pumpAndSettle();
    expect(find.text('Perubahan HPP menunggu persetujuan owner'),
        findsOneWidget);
    await tester.tap(find.text('Tambahkan 1 Barang ke Stok'));
    await tester.pumpAndSettle();
    expect(await db.currentStock('pak'), 20);
    expect(await cost(), 36000, reason: 'HPP belum berubah');
    await drain(tester);

    await open(tester); // owner
    expect(find.byKey(const ValueKey('purchase-pending-card')), findsOneWidget);
    await tester.tap(find.textContaining('Faktur 124256-RPS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('purchase-approve')));
    await tester.pumpAndSettle();
    expect(await cost(), 37752);
    expect(find.byKey(const ValueKey('purchase-pending-card')), findsNothing);
    await drain(tester);
  });

  testWidgets('pegawai TANPA izin: tanpa kolom harga (hanya stok)',
      (tester) async {
    await open(tester, device: pegawai);
    expect(find.text('Hasil AI'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '2 pcs Apa Saja');
    await tester.tap(find.text('Proses Daftar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Harga per'), findsNothing);
    await drain(tester);
  });

  testWidgets('riwayat: pembelian tampil & bisa dibatalkan', (tester) async {
    await db.applyPurchase(invoiceNo: 'F-9', supplierName: 'Indomarco',
        lines: const [
          PurchaseLineInput(productUnitId: 'zak', qty: 5, unitPrice: 167621),
        ]);
    await pumpWithFakeApp(tester,
        db: db,
        child: const PurchaseHistoryScreen(),
        surfaceSize: const Size(360, 1600));
    await tester.pumpAndSettle();
    expect(find.textContaining('F-9'), findsOneWidget);
    await tester.tap(find.textContaining('F-9'));
    await tester.pumpAndSettle();
    expect(find.textContaining(formatRupiah(37752)), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('purchase-void')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Batalkan'));
    await tester.pumpAndSettle();
    expect(await db.currentStock('pak'), 0);
    expect(await cost(), 36000);
    expect(find.textContaining('Dibatalkan'), findsWidgets);
    await drain(tester);
  });
}
