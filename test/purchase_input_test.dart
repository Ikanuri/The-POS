import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/lan_sync_service.dart';
import 'package:the_pos/core/utils/purchase_calc.dart';

/// PLAN Item 90 tahap 1 — Input Pembelian: hitung HPP dari faktur (diskon,
/// PPN fleksibel per baris, isi satuan), terapkan (stok + HPP) & batalkan.
/// Angka acuan = faktur contoh Indomarco dari owner.
void main() {
  group('purchase_calc', () {
    test('Terigu Payung: 5 ZAK @167.621 inkl PPN 11%, isi 4 -> HPP 37.752 '
        '(pisah) / 41.905 (modal)', () {
      final pisah = computePurchaseLine(
          qty: 5,
          unitPrice: 167621,
          priceIncludesTax: true,
          treatment: PurchaseTaxTreatment.pisah,
          taxRate: 11,
          ratioToBase: 4);
      expect(pisah.gross, 838105);
      expect(pisah.costPerBaseUnit, 37752);
      expect(pisah.inputTax, pisah.tax);
      expect(pisah.dpp + pisah.tax, 838105);
      final modal = computePurchaseLine(
          qty: 5,
          unitPrice: 167621,
          priceIncludesTax: true,
          treatment: PurchaseTaxTreatment.modal,
          taxRate: 11,
          ratioToBase: 4);
      expect(modal.costPerBaseUnit, 41905);
      expect(modal.inputTax, 0, reason: 'PPN masuk modal, tidak dicatat');
    });

    test('potongan baris (susu: 6 CAR @150.920 - 21.000), bebas PPN, harga '
        'belum termasuk PPN', () {
      final r = computePurchaseLine(
          qty: 6,
          unitPrice: 150920,
          discount: 21000,
          priceIncludesTax: true,
          treatment: PurchaseTaxTreatment.pisah,
          taxRate: 11,
          ratioToBase: 120);
      expect(r.net, 884520);
      expect(r.costPerBaseUnit, (884520 / 1.11 / 6 / 120).round());
      final bebas = computePurchaseLine(
          qty: 2,
          unitPrice: 10000,
          priceIncludesTax: true,
          treatment: PurchaseTaxTreatment.bebas,
          taxRate: 11,
          ratioToBase: 1);
      expect(bebas.costPerBaseUnit, 10000);
      expect(bebas.tax, 0);
      final excl = computePurchaseLine(
          qty: 1,
          unitPrice: 10000,
          priceIncludesTax: false,
          treatment: PurchaseTaxTreatment.modal,
          taxRate: 11,
          ratioToBase: 1);
      expect(excl.costPerBaseUnit, 11100);
    });

    test('diskon faktur dibagi proporsional, jumlah persis', () {
      final a = allocateInvoiceDiscount([838106, 977715, 1771350], 1000);
      expect(a.fold<int>(0, (s, v) => s + v), 1000);
      expect(a[2], greaterThan(a[0]));
      expect(allocateInvoiceDiscount([100, 0], 0), [0, 0]);
    });

    test('ambang peringatan perubahan HPP', () {
      expect(exceedsCostChangeThreshold(10000, 13500, 30), isTrue);
      expect(exceedsCostChangeThreshold(10000, 12000, 30), isFalse);
      expect(exceedsCostChangeThreshold(0, 12000, 30), isFalse,
          reason: 'HPP lama kosong: tidak ada acuan');
    });
  });

  group('DB', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      // Terigu: dasar = pak (Rp45.000 jual, HPP 36.000), ZAK isi 4.
      await db.saveProduct(
        product: ProductsCompanion.insert(id: 'P1', name: 'Terigu Payung'),
        units: [
          ProductUnitsCompanion.insert(
              id: 'pak',
              productId: 'P1',
              isBaseUnit: const Value(true),
              isNonStock: const Value(false)),
          ProductUnitsCompanion.insert(
              id: 'zak',
              productId: 'P1',
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
            PriceTiersCompanion.insert(
                id: 't1b',
                productUnitId: 'pak',
                minQty: const Value(10),
                price: 44000,
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

    Future<List<int>> costs(String unitId) async => (await (db
                .select(db.priceTiers)
              ..where((t) => t.productUnitId.equals(unitId)))
            .get())
        .map((t) => t.costPrice)
        .toList();

    test('terapkan: stok +20 pak, HPP semua satuan & tingkat harga, catatan '
        'faktur', () async {
      final id = await db.applyPurchase(
        invoiceNo: '124256-RPS',
        supplierName: 'Indomarco',
        lines: const [
          PurchaseLineInput(productUnitId: 'zak', qty: 5, unitPrice: 167621),
        ],
        kasirId: 'O1',
      );
      expect(await db.currentStock('pak'), 20);
      expect(await costs('pak'), everyElement(37752));
      expect(await costs('zak'), [37752 * 4]);
      final head = await (db.select(db.purchases)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(head.status, 'received');
      expect(head.invoiceNo, '124256-RPS');
      expect(head.inputTaxTotal, greaterThan(0));
      final item = (await db.select(db.purchaseItems).get()).single;
      expect(item.costBefore, 36000);
      expect(item.costAfter, 37752);
      expect(item.taxTreatment, 'pisah');
    });

    test('"Perbarui HPP" mati / harga kosong -> hanya stok', () async {
      await db.applyPurchase(lines: const [
        PurchaseLineInput(
            productUnitId: 'zak', qty: 1, unitPrice: 160000, applyCost: false),
        PurchaseLineInput(productUnitId: 'pak', qty: 2, unitPrice: 0),
      ]);
      expect(await db.currentStock('pak'), 6);
      expect(await costs('pak'), everyElement(36000));
      final items = await db.select(db.purchaseItems).get();
      expect(items.every((i) => i.costAfter == null), isTrue);
    });

    test('batalkan: stok kembali & HPP dipulihkan; idempotent', () async {
      final id = await db.applyPurchase(lines: const [
        PurchaseLineInput(productUnitId: 'zak', qty: 5, unitPrice: 167621),
      ]);
      expect(await db.voidPurchase(id), isEmpty);
      expect(await db.currentStock('pak'), 0);
      expect(await costs('pak'), everyElement(36000));
      expect(await costs('zak'), [144000]);
      final head = await (db.select(db.purchases)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(head.status, 'void');
      expect(await db.voidPurchase(id), isEmpty);
      expect(await db.currentStock('pak'), 0, reason: 'tidak dobel');
    });

    test('batalkan setelah HPP berubah lagi oleh pembelian berikutnya -> '
        'hanya stok, HPP tidak dipulihkan & dilaporkan', () async {
      final first = await db.applyPurchase(lines: const [
        PurchaseLineInput(productUnitId: 'zak', qty: 1, unitPrice: 167621),
      ]);
      await db.applyPurchase(lines: const [
        PurchaseLineInput(productUnitId: 'zak', qty: 1, unitPrice: 177600),
      ]);
      final costNow = (await costs('pak')).first;
      final notRestored = await db.voidPurchase(first);
      expect(notRestored, ['zak']);
      expect(await costs('pak'), everyElement(costNow));
      expect(await db.currentStock('pak'), 4);
    });

    test('pengaturan pembelian: default & tersimpan; key ikut sync', () async {
      final d = await db.getPurchaseSettings();
      expect(d.treatment, PurchaseTaxTreatment.pisah);
      expect(d.taxRate, 11);
      expect(d.warnPct, 30);
      await db.setSetting(kPurchaseCostWarnPctKey, '20');
      await db.setSetting(kPurchaseTaxTreatmentKey, 'modal');
      final s = await db.getPurchaseSettings();
      expect(s.warnPct, 20);
      expect(s.treatment, PurchaseTaxTreatment.modal);
      expect(
          AppDatabase.syncableSettingKeys,
          containsAll([
            kPurchaseTaxTreatmentKey,
            kPurchaseTaxRateKey,
            kPurchaseCostWarnPctKey
          ]));
    });

    test('sync owner -> klien: catatan pembelian & HPP baru sampai', () async {
      final client = AppDatabase(NativeDatabase.memory());
      addTearDown(client.close);
      await db.applyPurchase(invoiceNo: 'F-1', lines: const [
        PurchaseLineInput(productUnitId: 'zak', qty: 5, unitPrice: 167621),
      ]);
      final dump = await db.dumpSince(DateTime(2000));
      for (final e in dump.entries) {
        if (!LanSyncService.clientMergeableTables.contains(e.key)) continue;
        await client.mergeRows(
            e.key, e.value, LanSyncService.appendOnlyTables.contains(e.key));
      }
      final head = (await client.select(client.purchases).get()).single;
      expect(head.invoiceNo, 'F-1');
      expect((await client.select(client.purchaseItems).get()).single.costAfter,
          37752);
      final tiers = await (client.select(client.priceTiers)
            ..where((t) => t.productUnitId.equals('pak')))
          .get();
      expect(tiers.map((t) => t.costPrice), everyElement(37752));
    });
  });

  group('tahap 3-4 (usulan pegawai, kategori harga, sync dua arah)', () {
    late AppDatabase host;
    late AppDatabase client;
    Future<void> seed(AppDatabase db) => db.saveProduct(
          product: ProductsCompanion.insert(id: 'P1', name: 'Terigu Payung'),
          units: [
            ProductUnitsCompanion.insert(
                id: 'pak',
                productId: 'P1',
                isBaseUnit: const Value(true),
                isNonStock: const Value(false)),
            ProductUnitsCompanion.insert(
                id: 'zak',
                productId: 'P1',
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
    setUp(() async {
      host = AppDatabase(NativeDatabase.memory());
      client = AppDatabase(NativeDatabase.memory());
      await seed(host);
      await seed(client);
    });
    tearDown(() async {
      await host.close();
      await client.close();
    });

    Future<int> cost(AppDatabase db) async => (await (db.select(db.priceTiers)
              ..where((t) => t.productUnitId.equals('pak')))
            .getSingle())
        .costPrice;

    // Klien -> host: hanya tabel append-only & dua-arah (sama dgn host asli).
    Future<void> up() async {
      final dump = await client.dumpSince(DateTime(2000),
          includeMasterData: false);
      for (final e in dump.entries) {
        final ao = LanSyncService.appendOnlyTables.contains(e.key);
        if (!ao && !LanSyncService.sharedTables.contains(e.key)) continue;
        await host.mergeRows(e.key, e.value, ao);
      }
    }

    Future<void> down() async {
      final dump = await host.dumpSince(DateTime(2000));
      for (final e in dump.entries) {
        if (!LanSyncService.clientMergeableTables.contains(e.key)) continue;
        await client.mergeRows(
            e.key, e.value, LanSyncService.appendOnlyTables.contains(e.key));
      }
    }

    test('pegawai: stok langsung, HPP jadi usulan; naik ke owner, disetujui, '
        'HPP & status turun lagi', () async {
      final id = await client.applyPurchase(costAsProposal: true, lines: const [
        PurchaseLineInput(productUnitId: 'zak', qty: 5, unitPrice: 167621),
      ]);
      expect(await client.currentStock('pak'), 20);
      expect(await cost(client), 36000, reason: 'HPP belum berubah (usulan)');
      expect(
          (await (client.select(client.purchases)
                    ..where((t) => t.id.equals(id)))
                  .getSingle())
              .status,
          'pending');

      await up();
      final onHost = await (host.select(host.purchases)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      expect(onHost?.status, 'pending',
          reason: 'tanpa sync dua arah, usulan tidak pernah sampai ke owner');

      expect(await host.approvePurchase(id), isTrue);
      expect(await cost(host), 37752);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await down();
      expect(await cost(client), 37752);
      expect(
          (await (client.select(client.purchases)
                    ..where((t) => t.id.equals(id)))
                  .getSingle())
              .status,
          'received');
    });

    test('owner tolak usulan: HPP tetap, status cost_rejected; batalkan '
        'usulan tidak menyentuh HPP', () async {
      final id = await host.applyPurchase(costAsProposal: true, lines: const [
        PurchaseLineInput(productUnitId: 'zak', qty: 1, unitPrice: 167621),
      ]);
      expect(await host.rejectPurchaseCost(id), isTrue);
      expect(await cost(host), 36000);
      final id2 = await host.applyPurchase(costAsProposal: true, lines: const [
        PurchaseLineInput(productUnitId: 'zak', qty: 1, unitPrice: 167621),
      ]);
      expect(await host.voidPurchase(id2), isEmpty,
          reason: 'usulan belum pernah mengubah HPP -> tidak ada peringatan');
      expect(await cost(host), 36000);
      expect(await host.approvePurchase(id), isFalse,
          reason: 'yang sudah ditolak tidak bisa disetujui');
    });

    test('dampak Kategori Harga berjangkar modal', () async {
      await host.into(host.priceCategories).insert(
          PriceCategoriesCompanion.insert(id: 'k1', name: const Value('Grosir')));
      await host.into(host.altPrices).insert(AltPricesCompanion.insert(
          id: 'a1',
          productUnitId: 'pak',
          label: 'Grosir',
          price: 39600,
          priceCategoryId: const Value('k1'),
          marginAnchor: const Value('modal'),
          marginType: const Value('percent'),
          marginValue: const Value(10)));
      final impact = await host.getCategoryPriceImpact('pak', 37752);
      expect(impact.single.oldPrice, 39600);
      expect(impact.single.newPrice, 41527);
      expect(await host.getCategoryPriceImpact('pak', 36000), isEmpty);
    });

    test('info satuan: perlakuan PPN terakhir diingat per barang', () async {
      expect((await host.getPurchaseUnitInfo('zak'))!.lastTreatment, isNull);
      await host.applyPurchase(lines: const [
        PurchaseLineInput(
            productUnitId: 'zak',
            qty: 1,
            unitPrice: 100000,
            treatment: PurchaseTaxTreatment.modal),
      ]);
      final info = (await host.getPurchaseUnitInfo('pak'))!;
      expect(info.lastTreatment, PurchaseTaxTreatment.modal);
      expect(info.ratio, 1);
      expect((await host.getPurchaseUnitInfo('zak'))!.ratio, 4);
      expect(await host.purchaseInvoiceExists(''), isFalse);
    });
  });

  test('migrasi v46 -> v47: kolom pembelian ditambah, data lama utuh',
      () async {
    final path = '${Directory.systemTemp.path}/pos_mig47_'
        '${DateTime.now().microsecondsSinceEpoch}.db';
    final file = File(path);
    final v46 = raw.sqlite3.open(path);
    v46.execute('PRAGMA user_version = 46;');
    v46.execute('CREATE TABLE purchases(id TEXT PRIMARY KEY, local_id TEXT, '
        'supplier_id TEXT, kasir_id TEXT, status TEXT, total INTEGER, '
        'paid INTEGER, note TEXT, created_at INTEGER, synced_at INTEGER, '
        'updated_at INTEGER);');
    v46.execute('CREATE TABLE purchase_items(id TEXT PRIMARY KEY, '
        'purchase_id TEXT, product_unit_id TEXT, qty REAL, '
        'price_per_unit INTEGER, subtotal INTEGER, created_at INTEGER);');
    v46.execute("INSERT INTO purchases (id, local_id, status, total, paid) "
        "VALUES ('pb', 'PB-1', 'received', 1000, 0);");
    v46.dispose();

    final d = AppDatabase(NativeDatabase(file), readOnly: true);
    final pCols = (await d.customSelect('PRAGMA table_info(purchases)').get())
        .map((r) => r.data['name'])
        .toSet();
    expect(pCols, containsAll(['invoice_no', 'input_tax_total']));
    final iCols =
        (await d.customSelect('PRAGMA table_info(purchase_items)').get())
            .map((r) => r.data['name'])
            .toSet();
    expect(iCols, containsAll(['tax_treatment', 'cost_before', 'cost_after']));
    final row = await d
        .customSelect("SELECT total FROM purchases WHERE id = 'pb'")
        .getSingle();
    expect(row.data['total'], 1000);
    final ver = await d.customSelect('PRAGMA user_version').getSingle();
    expect(ver.data.values.first, 47);
    await d.close();
    if (file.existsSync()) file.deleteSync();
  });
}
