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

  /// Tempel daftar teks lalu isi harga beli satuan (unit isi 4) di baris pertama.
  Future<void> pasteList(WidgetTester tester, {int price = 167621}) async {
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            w.decoration?.hintText?.startsWith('5 pcs') == true),
        '5 pcs Terigu Payung');
    await tester.tap(find.text('Proses Daftar'));
    await tester.pumpAndSettle();
    // Teks "pcs" cocok ke satuan dasar (Kg); pindah ke satuan isi 4 (ZAK).
    await tester.tap(find.byKey(const ValueKey('unit-chip-Terigu Payung-zak')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField &&
            (w.decoration?.labelText ?? '').startsWith('Harga per')),
        '$price');
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

  testWidgets(
      'owner: tempel daftar + harga beli -> pratinjau HPP -> simpan '
      '(stok & HPP berubah, pembelian tercatat)', (tester) async {
    await open(tester);
    await pasteList(tester);

    expect(
        find.textContaining('${formatRupiah(36000)} → ${formatRupiah(37752)}'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Tambahkan 1 Barang ke Stok'));
    await tester.pumpAndSettle();
    expect(await db.currentStock('pak'), 20);
    expect(await cost(), 37752);
    final head = (await db.select(db.purchases).get()).single;
    expect(head.status, 'received');
    await drain(tester);
  });

  testWidgets(
      'harga jual di bawah HPP baru & perubahan besar -> dialog '
      'peringatan sebelum simpan', (tester) async {
    await open(tester);
    await pasteList(tester, price: 200000);
    expect(find.textContaining('di bawah HPP baru'), findsOneWidget);
    await tester.tap(find.text('Tambahkan 1 Barang ke Stok'));
    await tester.pumpAndSettle();
    expect(find.text('Periksa dulu'), findsOneWidget);
    await tester.tap(find.text('Cek lagi'));
    await tester.pumpAndSettle();
    expect(await cost(), 36000, reason: 'belum disimpan');
    await drain(tester);
  });

  testWidgets(
      'pegawai berizin: HPP jadi usulan; owner menyetujui dari '
      'bagian "Menunggu persetujuan"', (tester) async {
    await (db.update(db.kasirPermissions)
          ..where((t) => t.permissionKey.equals('input_pembelian')))
        .write(const KasirPermissionsCompanion(isEnabled: Value(true)));
    await open(tester, device: pegawai);
    await pasteList(tester);
    expect(
        find.text('Perubahan HPP menunggu persetujuan owner'), findsOneWidget);
    await tester.tap(find.text('Tambahkan 1 Barang ke Stok'));
    await tester.pumpAndSettle();
    expect(await db.currentStock('pak'), 20);
    expect(await cost(), 36000, reason: 'HPP belum berubah');
    await drain(tester);

    await open(tester); // owner
    expect(find.byKey(const ValueKey('purchase-pending-card')), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('purchase-pending-card')),
        matching: find.byType(ListTile)));
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
    await tester.enterText(find.byType(TextField).first, '2 pcs Apa Saja');
    await tester.tap(find.text('Proses Daftar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Harga per'), findsNothing);
    await drain(tester);
  });

  testWidgets('pemilih satuan di baris (ganti satuan dgn satu ketukan)',
      (tester) async {
    await open(tester);
    await pasteList(tester);
    // Dua chip satuan; ganti ke satuan dasar dgn satu ketukan.
    expect(find.byKey(const ValueKey('unit-chip-Terigu Payung-zak')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unit-chip-Terigu Payung-pak')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Harga per'), findsWidgets);
    await drain(tester);
  });

  testWidgets('riwayat: pembelian tampil & bisa dibatalkan', (tester) async {
    await db.applyPurchase(
        invoiceNo: 'F-9',
        supplierName: 'Indomarco',
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
