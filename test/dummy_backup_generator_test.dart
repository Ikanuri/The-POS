// Generator berkas backup DUMMY untuk uji restore (BPOP2, terenkripsi).
//
// Jalankan: `DUMMY_BACKUP_OUT=docs/test-data flutter test test/dummy_backup_generator_test.dart`
// (tanpa DUMMY_BACKUP_OUT berkas ditulis ke direktori sementara)
// Keluaran : docs/test-data/dummy-backup.bpos  (password: dummy12345)
//            docs/test-data/dummy-backup.json  (isi mentah, untuk dibaca)
//            docs/test-data/README.md          (isi & cara pakai)
//
// Isi: toko fiktif "Toko Berkah Jaya (DEMO)" — SEMUA tabel backup terisi,
// dengan variasi atribut (status nota, metode bayar, satuan bertingkat,
// varian, kategori harga, pre-order, pinjaman, titip, dst.). Test ini juga
// membuktikan round-trip: dekripsi -> restore ke DB kosong -> jumlah baris
// per tabel sama dgn sumber.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/services/db_export_service.dart';

const kDummyPassword = 'dummy12345';

String _d(DateTime t) =>
    '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';

/// Digit cek EAN-13.
String _ean13(String first12) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(first12[i]) * (i.isEven ? 1 : 3);
  }
  return '$first12${(10 - sum % 10) % 10}';
}

class _Unit {
  _Unit(this.id, this.productId, this.name, this.ratio, this.price, this.cost);
  final String id;
  final String productId;
  final String name;
  final double ratio;
  final int price;
  final int cost;
}

Future<AppDatabase> buildDummyDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  final rnd = Random(42);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime ago(int days, [int hour = 9, int min = 0]) =>
      today.subtract(Duration(days: days)).add(Duration(hours: hour, minutes: min));

  // ── Pengaturan toko ───────────────────────────────────────────────────
  final settings = <String, String>{
    'store_name': 'Toko Berkah Jaya (DEMO)',
    'store_address': 'Jl. Raya Kenari No. 17, Bekasi',
    'store_phone': '0218889900',
    'store_whatsapp': '6281234567890',
    'store_telegram': 'berkahjaya_demo',
    'receipt_header': 'TOKO BERKAH JAYA\nGrosir & Eceran',
    'receipt_note': 'Terima kasih. Barang yang sudah dibeli tidak dapat ditukar.',
    'receipt_show_employee': '1',
    'loyalty_points_per': '10000',
    'loyalty_point_threshold': '100',
    'allow_negative_stock': '0',
    'qris_dynamic_enabled': '0',
    'katalog_wa_direct': '1',
    'kasir_landing_title': 'Mau jual apa hari ini?',
    'kasir_landing_subtitle': 'Scan barang, ketik nama, atau pilih kategori',
    'saved_catalogs': jsonEncode([
      {'id': 'cat-1', 'name': 'Promo Akhir Pekan', 'productIds': ['p-001', 'p-002', 'p-010']},
    ]),
  };
  for (final e in settings.entries) {
    await db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: e.key, value: e.value));
  }

  // ── Kategori produk & jenis satuan ────────────────────────────────────
  const groups = ['Sembako', 'Minuman', 'Snack', 'Bumbu Dapur', 'Kebutuhan Rumah', 'Perawatan'];
  for (var i = 0; i < groups.length; i++) {
    await db.into(db.productGroups).insertOnConflictUpdate(ProductGroupsCompanion.insert(
        id: Value(i + 1), name: Value(groups[i]), sortOrder: Value(i)));
  }
  const unitTypes = ['Pcs', 'Dus', 'Kg', 'Karung', 'Pak', 'Liter', 'Lusin', 'Botol'];
  for (var i = 0; i < unitTypes.length; i++) {
    await db.into(db.unitTypes).insertOnConflictUpdate(UnitTypesCompanion.insert(
        id: Value(i + 1), name: unitTypes[i], abbrev: Value(unitTypes[i].toLowerCase())));
  }

  // ── Produk (katalog) ──────────────────────────────────────────────────
  // (nama, grup, hargaEcer, modal, satuanDus?, isi dus, kg?)
  final catalog = <(String, int, int, int, bool, int, bool)>[
    ('Beras Premium 5kg', 1, 68000, 62000, false, 0, false),
    ('Beras Medium (curah)', 1, 13500, 12200, false, 0, true),
    ('Gula Pasir (curah)', 1, 17000, 15200, false, 0, true),
    ('Minyak Goreng 1L', 1, 18500, 16800, true, 12, false),
    ('Minyak Goreng 2L', 1, 36000, 33000, true, 6, false),
    ('Tepung Terigu 1kg', 1, 12500, 11000, true, 20, false),
    ('Telur Ayam (curah)', 1, 29000, 26500, false, 0, true),
    ('Mie Instan Goreng', 1, 3200, 2750, true, 40, false),
    ('Mie Instan Kuah', 1, 3000, 2600, true, 40, false),
    ('Kopi Sachet', 3, 1500, 1200, true, 100, false),
    ('Teh Celup 25s', 2, 6500, 5400, true, 24, false),
    ('Air Mineral 600ml', 2, 3500, 2700, true, 24, false),
    ('Air Mineral Galon (isi ulang)', 2, 6000, 4500, false, 0, false),
    ('Susu Kental Manis', 2, 12500, 10900, true, 24, false),
    ('Teh Botol 450ml', 2, 5500, 4400, true, 24, false),
    ('Sirup Marjan 460ml', 2, 21000, 18500, true, 12, false),
    ('Biskuit Kelapa', 3, 9500, 8000, true, 20, false),
    ('Keripik Singkong', 3, 7500, 6000, true, 30, false),
    ('Wafer Coklat', 3, 2000, 1500, true, 50, false),
    ('Permen Mint', 3, 500, 350, true, 200, false),
    ('Garam Dapur 250g', 4, 3500, 2800, true, 40, false),
    ('Kecap Manis 135ml', 4, 8500, 7200, true, 24, false),
    ('Saus Sambal 140ml', 4, 7000, 5800, true, 24, false),
    ('Merica Bubuk', 4, 2500, 1800, true, 100, false),
    ('Bawang Merah (curah)', 4, 38000, 34000, false, 0, true),
    ('Bawang Putih (curah)', 4, 36000, 32000, false, 0, true),
    ('Cabai Rawit (curah)', 4, 65000, 55000, false, 0, true),
    ('Sabun Mandi', 6, 4500, 3600, true, 72, false),
    ('Shampo Sachet', 6, 1000, 750, true, 200, false),
    ('Pasta Gigi 75g', 6, 9500, 8000, true, 48, false),
    ('Deterjen Bubuk 800g', 5, 17500, 15500, true, 12, false),
    ('Sabun Cuci Piring 400ml', 5, 9500, 8000, true, 24, false),
    ('Pewangi Pakaian 900ml', 5, 15500, 13400, true, 12, false),
    ('Tisu Gulung', 5, 6500, 5300, true, 48, false),
    ('Kantong Plastik Kresek (pak)', 5, 11000, 9000, false, 0, false),
    ('Korek Api Gas', 5, 2500, 1800, true, 100, false),
    ('Baterai AA (2pcs)', 5, 8500, 6800, true, 30, false),
    ('Obat Nyamuk Bakar', 5, 8000, 6500, true, 48, false),
    ('Gas LPG 3kg (isi)', 5, 22000, 19000, false, 0, false),
    ('Pulsa & Token (jasa)', 5, 2500, 0, false, 0, false),
  ];
  final units = <_Unit>[];
  final productIds = <String>[];
  var seq = 0;
  String pid(int i) => 'p-${i.toString().padLeft(3, '0')}';
  final stockNow = <String, double>{};
  Future<void> ledger(String unitId, String type, double change,
      {String? ref, DateTime? at, String? note}) async {
    final after = (stockNow[unitId] ?? 0) + change;
    stockNow[unitId] = after;
    await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
          id: 'sl-${++seq}',
          productUnitId: unitId,
          type: type,
          qtyChange: change,
          stockAfter: after,
          referenceId: Value(ref),
          kasirId: const Value('K1'),
          note: Value(note),
          createdAt: Value(at ?? now),
        ));
  }

  var barcodeSeq = 0;
  for (var i = 0; i < catalog.length; i++) {
    final (name, g, price, cost, hasDus, dusQty, isKg) = catalog[i];
    final id = pid(i + 1);
    productIds.add(id);
    final nonStock = name.contains('jasa');
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
          productGroupId: Value(g),
          kodeProduk: Value('KD${(i + 1).toString().padLeft(4, '0')}'),
          markedOutOfStock: Value(name.startsWith('Teh Celup')),
          createdAt: Value(ago(90)),
          updatedAt: Value(ago(30)),
        ));
    await db.into(db.productGroupTags).insert(ProductGroupTagsCompanion.insert(
        productId: id, groupId: g));
    // Satuan dasar
    final baseUnitName = isKg ? 'Kg' : (name.contains('Galon') || name.contains('Gas') ? 'Pcs' : 'Pcs');
    final baseId = 'u-$id-1';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: baseId,
          productId: id,
          unitTypeId: Value(isKg ? 3 : 1),
          isBaseUnit: const Value(true),
          isNonStock: Value(nonStock),
          minStock: Value(nonStock ? null : (isKg ? 5 : 10)),
          requiresDeposit: Value(name.contains('Galon') || name.contains('Gas')),
        ));
    units.add(_Unit(baseId, id, baseUnitName, 1, price, cost));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't-$baseId-1', productUnitId: baseId, price: price, costPrice: Value(cost)));
    if (!isKg && price < 15000 && !nonStock) {
      // Tier grosir
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't-$baseId-12',
          productUnitId: baseId,
          minQty: const Value(12),
          price: (price * 0.95).round(),
          costPrice: Value(cost)));
    }
    // Barcode: campuran resmi 13-digit, 8-digit "asal tempel", generated 29...
    if (!nonStock && i % 3 != 2) {
      final bc = i % 3 == 0
          ? _ean13('899${(1000000 + i * 137).toString().padLeft(9, '0')}')
          : (10000000 + i * 7919).toString().padLeft(8, '0');
      await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'b-${++barcodeSeq}', productUnitId: baseId, barcode: bc, isPrimary: const Value(true)));
    } else if (!nonStock) {
      await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'b-${++barcodeSeq}',
          productUnitId: baseId,
          barcode: _ean13('29${(2000000 + i).toString().padLeft(10, '0')}'),
          isPrimary: const Value(true),
          isGenerated: const Value(true)));
    }
    // Stok awal
    if (!nonStock) {
      await ledger(baseId, 'adjust', (isKg ? 60 : 120 + rnd.nextInt(120)).toDouble(),
          at: ago(80), note: 'Stok awal');
    }
    // Satuan Dus (bertingkat)
    if (hasDus) {
      final dusId = 'u-$id-2';
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
            id: dusId,
            productId: id,
            unitTypeId: const Value(2),
            ratioToBase: Value(dusQty.toDouble()),
            minStock: const Value(2),
          ));
      final dusPrice = (price * dusQty * 0.93).round();
      units.add(_Unit(dusId, id, 'Dus', dusQty.toDouble(), dusPrice, cost * dusQty));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't-$dusId-1', productUnitId: dusId, price: dusPrice, costPrice: Value(cost * dusQty)));
      await db.into(db.productBarcodes).insert(ProductBarcodesCompanion.insert(
          id: 'b-${++barcodeSeq}',
          productUnitId: dusId,
          barcode: _ean13('898${(3000000 + i * 31).toString().padLeft(9, '0')}')));
    }
  }
  // Beras 5kg punya satuan Karung (kemasan besar, ratio 5 dari pcs)
  // Varian: Pop Ice (induk) + 3 varian rasa
  await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'p-pop', name: 'Pop Ice', productGroupId: const Value(2), kodeProduk: const Value('POP001')));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
      id: 'u-p-pop-1', productId: 'p-pop', unitTypeId: const Value(1), isBaseUnit: const Value(true)));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
      id: 't-pop-1', productUnitId: 'u-p-pop-1', price: 2500, costPrice: const Value(1900)));
  units.add(_Unit('u-p-pop-1', 'p-pop', 'Pcs', 1, 2500, 1900));
  productIds.add('p-pop');
  await ledger('u-p-pop-1', 'adjust', 200, at: ago(80), note: 'Stok awal');
  for (final (i, rasa) in ['Coklat', 'Vanila', 'Melon'].indexed) {
    final vid = 'p-pop-v$i';
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: vid,
        name: 'Pop Ice $rasa',
        productGroupId: const Value(2),
        parentProductId: const Value('p-pop')));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u-$vid-1',
        productId: vid,
        unitTypeId: const Value(1),
        isBaseUnit: const Value(true),
        followsParentPrice: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 't-$vid-1', productUnitId: 'u-$vid-1', price: 2500, costPrice: const Value(1900)));
    await ledger('u-$vid-1', 'adjust', 80, at: ago(80), note: 'Stok awal');
  }
  // Produk non-aktif
  await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'p-old', name: 'Produk Lama (nonaktif)', isActive: const Value(false)));

  // ── Kategori harga & harga alternatif ─────────────────────────────────
  const catWarung = 'pc-warung';
  const catReseller = 'pc-reseller';
  await db.into(db.priceCategories).insert(PriceCategoriesCompanion.insert(
      id: catWarung, name: const Value('Warung'), sortOrder: const Value(0)));
  await db.into(db.priceCategories).insert(PriceCategoriesCompanion.insert(
      id: catReseller, name: const Value('Reseller'), sortOrder: const Value(1)));
  var altSeq = 0;
  for (final u in units.where((u) => u.ratio == 1).take(25)) {
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: 'ap-${++altSeq}',
          productUnitId: u.id,
          label: 'Warung',
          price: (u.cost * 1.08).round(),
          priceCategoryId: const Value(catWarung),
          marginAnchor: const Value('modal'),
          marginType: const Value('percent'),
          marginValue: const Value(8.0),
        ));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: 'ap-${++altSeq}',
          productUnitId: u.id,
          label: 'Reseller',
          price: u.cost + 300,
          priceCategoryId: const Value(catReseller),
          marginAnchor: const Value('modal'),
          marginType: const Value('fixed'),
          marginValue: const Value(300.0),
          sortOrder: const Value(1),
        ));
  }
  // Harga alternatif manual (tanpa kategori)
  await db.into(db.altPrices).insert(AltPricesCompanion.insert(
      id: 'ap-${++altSeq}', productUnitId: units[0].id, label: 'Harga Toko A', price: 66000, sortOrder: const Value(2)));

  // ── Pelanggan ─────────────────────────────────────────────────────────
  await db.into(db.customerGroups).insert(CustomerGroupsCompanion.insert(
      id: 'cg-grosir', name: 'Grosir', color: const Value('#C96442')));
  await db.into(db.customerGroups).insert(CustomerGroupsCompanion.insert(
      id: 'cg-member', name: 'Member Setia', color: const Value('#2E7D74')));
  for (final u in units.where((u) => u.ratio == 1).take(8)) {
    await db.into(db.customerGroupPrices).insert(CustomerGroupPricesCompanion.insert(
        id: 'cgp-${u.id}', productUnitId: u.id, customerGroupId: 'cg-grosir', price: (u.price * 0.94).round()));
  }
  const custNames = [
    'Bu Ratna (Warung Ratna)', 'Pak Haji Sulaiman', 'Mbak Dewi', 'Bu Artia', 'Pak Joko Montir',
    'Warung Makmur', 'Bu Siti Aminah', 'Pak Ahmad Fauzi', 'Katering Bunda', 'Kantin SDN 03',
    'Bu Lilis', 'Pak RT Hendra', 'Mas Bayu', 'Ibu Yuni', 'Pelanggan Lama (nonaktif)',
  ];
  final custIds = <String>[];
  for (var i = 0; i < custNames.length; i++) {
    final id = 'c-${(i + 1).toString().padLeft(3, '0')}';
    custIds.add(id);
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: id,
          name: custNames[i],
          phone: Value('08${(1200000000 + i * 7311).toString()}'),
          address: Value('Jl. Mawar No. ${i + 1}, Bekasi'),
          customerGroupId: Value(i % 5 == 0 ? 'cg-grosir' : (i % 5 == 1 ? 'cg-member' : null)),
          creditLimit: Value(i % 3 == 0 ? 2000000 : 500000),
          loyaltyPoints: Value(i * 7),
          notes: Value(i == 3 ? 'Suka ambil barang sore hari' : null),
          isActive: Value(i != custNames.length - 1),
          createdAt: Value(ago(80 - i)),
        ));
  }

  // ── Pegawai, izin, metode bayar ───────────────────────────────────────
  for (final (i, n) in ['Sari', 'Rudi', 'Tono'].indexed) {
    await db.into(db.employees).insert(EmployeesCompanion.insert(
        id: 'e-${i + 1}', name: n, isActive: Value(i != 2)));
  }
  for (final k in ['input_stok', 'tambah_pelanggan', 'input_pengeluaran', 'terima_pembayaran']) {
    await db.into(db.kasirPermissions).insertOnConflictUpdate(
        KasirPermissionsCompanion.insert(permissionKey: k, isEnabled: const Value(true)));
  }
  await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
      id: 'pm-1', type: 'tunai', name: 'Tunai'));
  await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
      id: 'pm-2', type: 'qris', name: 'QRIS Toko', qrValue: const Value('00020101021126DUMMYQRISDEMO'), sortOrder: const Value(1)));
  await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
      id: 'pm-3', type: 'bank', name: 'BCA', data: const Value('1234567890 a.n. Toko Berkah'), sortOrder: const Value(2)));
  await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
      id: 'pm-4', type: 'ewallet', name: 'OVO', data: const Value('081234567890'), sortOrder: const Value(3), isActive: const Value(false)));

  // ── Supplier & pembelian ──────────────────────────────────────────────
  for (final (i, n) in ['CV Sumber Pangan', 'PT Indo Grosir', 'UD Maju Jaya', 'Agen Gas Pak Eko'].indexed) {
    await db.into(db.suppliers).insert(SuppliersCompanion.insert(
          id: 's-${i + 1}',
          name: n,
          phone: Value('021777${i}000'),
          outstandingDebt: Value(i == 1 ? 1500000 : 0),
          notes: Value(i == 0 ? 'Kirim Selasa & Jumat' : null),
        ));
  }
  for (var p = 0; p < 6; p++) {
    final pid2 = 'pu-${p + 1}';
    final items = units.where((u) => u.ratio == 1).skip(p * 3).take(4).toList();
    var total = 0;
    var discTotal = 0;
    var taxTotal = 0;
    for (final (j, u) in items.indexed) {
      final qty = (24 + j * 6).toDouble();
      final disc = j == 0 ? 5000 : 0;
      final sub = (u.cost * qty).round() - disc;
      final tax = p % 2 == 0 ? (sub * 0.11 / 1.11).round() : 0;
      total += sub;
      discTotal += disc;
      taxTotal += tax;
      await db.into(db.purchaseItems).insert(PurchaseItemsCompanion.insert(
            id: 'pi-$p-$j',
            purchaseId: pid2,
            productUnitId: u.id,
            qty: qty,
            pricePerUnit: u.cost,
            subtotal: sub,
            createdAt: Value(ago(60 - p * 8)),
            discount: Value(disc),
            priceIncludesTax: Value(p % 2 == 0),
            taxTreatment: Value(p % 2 == 0 ? 'ppn_included' : 'none'),
            taxRate: Value(p % 2 == 0 ? 11.0 : null),
            inputTax: Value(tax),
            costBefore: Value(u.cost),
            costAfter: Value(u.cost + (p == 5 ? 100 : 0)),
          ));
      await ledger(u.id, 'purchase', qty, ref: pid2, at: ago(60 - p * 8), note: 'Pembelian');
    }
    await db.into(db.purchases).insert(PurchasesCompanion.insert(
          id: pid2,
          localId: 'PB-${_d(ago(60 - p * 8))}-${(p + 1).toString().padLeft(3, '0')}',
          supplierId: Value('s-${(p % 4) + 1}'),
          kasirId: const Value('K1'),
          status: p == 1 ? 'hutang' : 'lunas',
          total: Value(total),
          paid: Value(p == 1 ? total ~/ 2 : total),
          note: Value(p == 3 ? 'Barang datang sebagian' : null),
          createdAt: Value(ago(60 - p * 8)),
          invoiceNo: Value('INV/$p/2026'),
          invoiceDate: Value(ago(60 - p * 8)),
          supplierName: Value(['CV Sumber Pangan', 'PT Indo Grosir', 'UD Maju Jaya', 'Agen Gas Pak Eko'][p % 4]),
          discountTotal: Value(discTotal),
          inputTaxTotal: Value(taxTotal),
        ));
  }

  // ── Transaksi (±120, 60 hari) ─────────────────────────────────────────
  final txIds = <String>[];
  final stockableUnits = units.where((u) => !u.name.contains('jasa')).toList();
  var payN = 0;
  var tN = 0;
  final perDayCount = <String, int>{};
  for (var day = 59; day >= 0; day--) {
    final perDay = 1 + rnd.nextInt(3);
    for (var k = 0; k < perDay; k++) {
      tN++;
      final at = ago(day, 8 + rnd.nextInt(11), rnd.nextInt(60));
      final dkey = _d(at);
      final n = (perDayCount[dkey] = (perDayCount[dkey] ?? 0) + 1);
      final id = 'tx-${tN.toString().padLeft(4, '0')}';
      txIds.add(id);
      final hasCust = rnd.nextInt(100) < 55;
      final custIdx = rnd.nextInt(custIds.length - 1);
      final status = tN % 23 == 0
          ? 'void'
          : tN % 11 == 0
              ? 'kurang_bayar'
              : tN % 29 == 0
                  ? 'tempo'
                  : 'lunas';
      final method = ['tunai', 'tunai', 'tunai', 'qris', 'transfer', 'ewallet'][rnd.nextInt(6)];
      // item
      final itemCount = 1 + rnd.nextInt(4);
      var total = 0;
      final picks = <_Unit>[];
      for (var q = 0; q < itemCount; q++) {
        picks.add(stockableUnits[rnd.nextInt(stockableUnits.length)]);
      }
      final lines = <(String, _Unit, double, int, bool)>[];
      for (final (q, u) in picks.indexed) {
        final isKg = u.name == 'Kg';
        final qty = isKg ? [0.25, 0.5, 1.0, 1.5, 2.0][rnd.nextInt(5)] : (1 + rnd.nextInt(6)).toDouble();
        final overridden = tN % 17 == 0 && q == 0;
        final price = overridden ? (u.price * 0.9).round() : u.price;
        final sub = (price * qty).round();
        total += sub;
        lines.add(('ti-$id-$q', u, qty, price, overridden));
      }
      final paid = status == 'kurang_bayar'
          ? (total * 0.5).round()
          : status == 'tempo'
              ? 0
              : (method == 'tunai' ? ((total + 4999) ~/ 5000) * 5000 : total);
      final change = status == 'lunas' && method == 'tunai' ? paid - total : 0;
      final pts = hasCust && status == 'lunas' ? total ~/ 10000 : 0;
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
            id: id,
            localId: 'K1-${_d(at)}-${n.toString().padLeft(4, '0')}',
            kasirId: const Value('K1'),
            customerId: Value(hasCust ? custIds[custIdx] : null),
            customerName: Value(hasCust ? custNames[custIdx] : (tN % 7 == 0 ? 'Pembeli Umum Ibu Tati' : null)),
            status: status,
            total: total,
            paid: paid,
            changeAmount: change,
            paymentMethod: method,
            methodName: Value(method == 'transfer' ? 'BCA' : (method == 'qris' ? 'QRIS Toko' : null)),
            internalNote: Value(tN % 13 == 0 ? 'Langganan, boleh bayar akhir bulan' : null),
            strukNote: Value(tN % 19 == 0 ? 'Titip salam untuk Bapak' : null),
            employeeName: Value(['Sari', 'Rudi', null][tN % 3]),
            pointsEarned: Value(pts),
            changeTaken: Value(change > 0 && tN % 4 != 0),
            checkedItemIds: Value(tN % 5 == 0 ? jsonEncode(lines.map((l) => l.$1).toList()) : null),
            createdAt: Value(at),
            updatedAt: Value(at),
            voidedBy: Value(status == 'void' ? 'K1' : null),
            voidReason: Value(status == 'void' ? 'Salah input barang' : null),
          ));
      for (final (liId, u, qty, price, overridden) in lines) {
        await db.into(db.transactionItems).insert(TransactionItemsCompanion.insert(
              id: liId,
              transactionId: id,
              productId: u.productId,
              productUnitId: u.id,
              qty: qty,
              priceAtSale: price,
              originalPrice: u.price,
              priceOverridden: Value(overridden),
              costAtSale: Value(u.cost),
              itemNote: Value(tN % 31 == 0 ? 'Yang kemasan baru' : null),
              subtotal: (price * qty).round(),
              addedAt: Value(at),
              updatedAt: Value(at),
            ));
        if (status != 'void') {
          await ledger(u.id, 'sale', -(qty * u.ratio), ref: id, at: at);
        }
      }
      if (paid > 0) {
        await db.into(db.transactionPayments).insert(TransactionPaymentsCompanion.insert(
              id: 'pay-${++payN}',
              transactionId: id,
              amount: paid,
              method: method,
              methodName: Value(method == 'transfer' ? 'BCA' : (method == 'qris' ? 'QRIS Toko' : null)),
              paidAt: Value(at),
              kasirId: const Value('K1'),
              changeGiven: Value(change),
              changeTaken: Value(change > 0 && tN % 4 != 0),
              voided: Value(status == 'void'),
              sisaAfter: Value(total - paid > 0 ? total - paid : 0),
              updatedAt: Value(at),
            ));
      }
      if (pts > 0) {
        await db.into(db.loyaltyPointLedger).insert(LoyaltyPointLedgerCompanion.insert(
            id: 'lp-$tN', customerId: custIds[custIdx], type: 'earn', points: pts, referenceId: Value(id), createdAt: Value(at)));
      }
    }
  }
  // Pelunasan hutang pada beberapa nota kurang_bayar (pembayaran susulan).
  final debtRows = await (db.select(db.transactions)..where((t) => t.status.equals('kurang_bayar'))).get();
  for (final (i, t) in debtRows.indexed) {
    final remaining = t.total - t.paid;
    final settle = i.isEven; // setengah dilunasi
    if (settle) {
      await db.into(db.transactionPayments).insert(TransactionPaymentsCompanion.insert(
            id: 'pay-${++payN}',
            transactionId: t.id,
            amount: remaining,
            method: 'tunai',
            paidAt: Value(t.createdAt.add(const Duration(days: 3))),
            kasirId: const Value('K1'),
            note: const Value('Pelunasan hutang'),
            sisaAfter: const Value(0),
          ));
      await (db.update(db.transactions)..where((x) => x.id.equals(t.id))).write(TransactionsCompanion(
          status: const Value('lunas'),
          paid: Value(t.total),
          debtSettlementDetail: Value(jsonEncode({'settledAt': t.createdAt.add(const Duration(days: 3)).toIso8601String(), 'amount': remaining}))));
    } else if (t.customerId != null) {
      await (db.update(db.customers)..where((c) => c.id.equals(t.customerId!))).write(CustomersCompanion(
          outstandingDebt: Value(remaining)));
    }
  }
  // Retur satu nota lunas: baris penyesuaian + stok kembali.
  final lunasRow = await (db.select(db.transactions)
        ..where((t) => t.status.equals('lunas'))
        ..limit(1, offset: 15))
      .getSingle();
  final retItem = await (db.select(db.transactionItems)
        ..where((i) => i.transactionId.equals(lunasRow.id))
        ..limit(1))
      .getSingle();
  final retPay = await (db.select(db.transactionPayments)
        ..where((p) => p.transactionId.equals(lunasRow.id))
        ..limit(1))
      .getSingle();
  final retUnit = units.firstWhere((u) => u.id == retItem.productUnitId);
  await db.into(db.transactionAdjustmentLines).insert(TransactionAdjustmentLinesCompanion.insert(
        id: 'adj-1',
        paymentId: retPay.id,
        transactionId: lunasRow.id,
        productId: retItem.productId,
        productUnitId: retItem.productUnitId,
        productName: 'Barang retur',
        unitName: retUnit.name,
        qty: 1,
        priceAtSale: retItem.priceAtSale,
        subtotal: retItem.priceAtSale,
      ));
  await (db.update(db.transactionItems)..where((i) => i.id.equals(retItem.id)))
      .write(TransactionItemsCompanion(returnedAt: Value(lunasRow.createdAt.add(const Duration(days: 1)))));
  await ledger(retItem.productUnitId, 'return_in', 1, ref: lunasRow.id, at: lunasRow.createdAt.add(const Duration(days: 1)));
  await ledger(units[3].id, 'adjust', -2, at: ago(12), note: 'Opname: rusak/kedaluwarsa');
  await ledger(units[7].id, 'adjustment', 3, at: ago(5), note: 'Koreksi hitung fisik');

  // Daftar nomor nota yang dipesan di muka
  for (var i = 1; i <= 3; i++) {
    await db.into(db.reservedOrderNumbers).insert(ReservedOrderNumbersCompanion.insert(
        localId: 'K1-${_d(today)}-90$i', createdAt: Value(now)));
  }

  // ── Pesanan ditahan (cartJson asli dari model) ────────────────────────
  for (var h = 0; h < 3; h++) {
    final u = units[h * 4];
    final item = CartItem(
        productId: u.productId,
        productUnitId: u.id,
        productName: catalog[h * 4].$1,
        unitName: u.name,
        qty: (h + 2).toDouble(),
        price: u.price,
        originalPrice: u.price,
        costPrice: u.cost);
    await db.into(db.heldOrders).insert(HeldOrdersCompanion.insert(
          id: 'ho-${h + 1}',
          label: ['Bu Artia', 'Pak Joko Montir', 'Tanpa Nama 3'][h],
          cartJson: jsonEncode({
            'items': [item.toJson()],
            'meta': {
              'customerId': h == 2 ? null : custIds[h == 0 ? 3 : 4],
              'customerName': ['Bu Artia', 'Pak Joko Montir', null][h],
            },
            'prabayar': [],
            'prabayarChangeTaken': 0,
            'priceCategory': h == 1 ? catWarung : null,
            'debtSettlement': [],
            'preorderSettlement': [],
          }),
          createdAt: Value(ago(0, 8 + h)),
        ));
  }

  // ── Pengeluaran ───────────────────────────────────────────────────────
  var exN = 0;
  for (var d = 58; d >= 0; d -= 4) {
    for (final (type, amt, note) in [
      ('daily_expense', 35000 + rnd.nextInt(50000), 'Listrik/plastik/bensin'),
      if (d % 12 == 2) ('owner_withdrawal', 500000, 'Ambil pribadi'),
      if (d % 16 == 6) ('supplier_payment', 750000, 'Bayar CV Sumber Pangan'),
      if (d % 8 == 0) ('change_given', 15000, 'Kembalian ditalangi'),
    ]) {
      exN++;
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: 'ex-$exN',
            localId: 'EX-${_d(ago(d))}-${exN.toString().padLeft(3, '0')}',
            type: type,
            amount: amt,
            note: Value(note),
            kasirId: const Value('K1'),
            createdAt: Value(ago(d, 17)),
          ));
    }
  }
  await db.into(db.expenses).insert(ExpensesCompanion.insert(
      id: 'ex-del', localId: 'EX-DEL-001', type: 'daily_expense', amount: 1000, note: const Value('Salah input'), deletedAt: Value(ago(3))));

  // ── Tutup kasir ───────────────────────────────────────────────────────
  for (var d = 7; d >= 1; d -= 2) {
    final sys = 800000 + rnd.nextInt(600000);
    final diff = d == 3 ? -5000 : 0;
    await db.into(db.cashClosings).insert(CashClosingsCompanion.insert(
          id: 'cc-$d',
          date: '${ago(d).year}-${ago(d).month.toString().padLeft(2, '0')}-${ago(d).day.toString().padLeft(2, '0')}',
          deviceCode: const Value('K1'),
          systemCash: sys,
          systemNonCash: const Value(350000),
          txCount: const Value(14),
          physicalCash: sys + diff,
          difference: diff,
          note: Value(d == 3 ? 'Selisih 5 ribu, kembalian' : null),
          createdAt: Value(ago(d, 21)),
        ));
  }

  // ── Laci Meja: titip/ketinggalan, pinjaman, pre-order, kejadian ───────
  final someTx = txIds[txIds.length - 10];
  final someTx2 = txIds[txIds.length - 20];
  await db.into(db.leftBehindItems).insert(LeftBehindItemsCompanion.insert(
        id: 'lb-1', transactionId: someTx, itemName: 'Gula Pasir (curah)', jenis: 'ketinggalan',
        customerId: Value(custIds[0]), customerNameText: Value(custNames[0]), qty: const Value(2.0),
        note: const Value('Belum dibawa, ambil besok')));
  await db.into(db.leftBehindItems).insert(LeftBehindItemsCompanion.insert(
        id: 'lb-2', transactionId: someTx2, itemName: 'Minyak Goreng 2L', jenis: 'titip',
        customerNameText: const Value('Pembeli Umum Ibu Tati'), qty: const Value(1.0),
        collectedAt: Value(ago(2))));
  await db.into(db.borrowedItems).insert(BorrowedItemsCompanion.insert(
        id: 'bw-1', transactionId: someTx, itemName: 'Tabung Gas 3kg (kosong)',
        customerId: Value(custIds[4]), customerNameText: Value(custNames[4]), qty: 2,
        qtyReturned: const Value(1), note: const Value('Pinjam tabung'), pinned: const Value(true)));
  await db.into(db.borrowedItems).insert(BorrowedItemsCompanion.insert(
        id: 'bw-2', transactionId: someTx2, itemName: 'Galon kosong',
        customerNameText: const Value('Warung Makmur'), qty: 3, qtyReturned: const Value(3),
        fullyReturnedAt: Value(ago(1))));
  final gas = units.firstWhere((u) => u.id.startsWith('u-p-040'));
  await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po-1', productId: gas.productId, productUnitId: gas.id, transactionId: Value(someTx),
        customerId: Value(custIds[1]), customerName: custNames[1], phone: const Value('0812000111'),
        qtyOrdered: 5, depositQty: const Value(5), paid: const Value(true), note: const Value('DP lunas')));
  await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po-2', productId: units[1].productId, productUnitId: units[1].id,
        customerName: 'Mbak Dewi', qtyOrdered: 10, note: const Value('Bayar saat barang datang'),
        fulfilledAt: Value(ago(1))));
  await db.into(db.preorderEntries).insert(PreorderEntriesCompanion.insert(
        id: 'po-3', productId: units[2].productId, productUnitId: units[2].id,
        customerName: 'Bu Lilis', qtyOrdered: 3, cancelledAt: Value(ago(4))));
  for (final (i, e) in [
    ('titip', 'lb-1', 'ambil', 1.0),
    ('pinjaman', 'bw-1', 'kembali', 1.0),
    ('preorder', 'po-2', 'penuhi', 10.0),
    ('preorder', 'po-3', 'batal', 0.0),
  ].indexed) {
    await db.into(db.laciMejaEvents).insert(LaciMejaEventsCompanion.insert(
          id: 'ev-${i + 1}', entityType: e.$1, entryId: e.$2, aksi: e.$3, qty: Value(e.$4),
          deviceCode: const Value('K1'), createdAt: Value(ago(4 - i)), appliedAt: Value(ago(4 - i))));
  }

  // ── Kamus alias penerimaan barang ─────────────────────────────────────
  for (final (i, a) in [
    ('minyak goreng bimoli 1l', 'pcs', units[3].id),
    ('mie goreng indomie', 'pcs', units[7].id),
    ('teh botol sosro 450', 'dus', units.firstWhere((u) => u.productId == pid(15) && u.name == 'Dus').id),
  ].indexed) {
    await db.into(db.productAliases).insert(ProductAliasesCompanion.insert(
        id: 'al-${i + 1}', normalizedName: a.$1, normalizedUnit: a.$2, productUnitId: a.$3));
  }

  // ── Ringkasan harian (dibangun ulang dari transaksi) ──────────────────
  await db.rebuildSummariesForTxIds(txIds.toSet());
  return db;
}

void main() {
  test('buat dummy-backup.bpos + round-trip restore', () async {
    final db = await buildDummyDb();
    addTearDown(() async => db.close());

    final dump = await db.dumpAllTables();
    final counts = {for (final e in dump.entries) e.key: e.value.length};
    // Semua tabel backup terisi (kecuali yang memang transient).
    final empty = counts.entries.where((e) => e.value == 0).map((e) => e.key).toList();
    expect(empty, isEmpty, reason: 'tabel kosong: $empty');

    final bytes = await DbExportService.exportPortable(db: db, password: kDummyPassword);
    // Default: tulis ke direktori sementara (suite penuh tidak mengubah repo).
    // Untuk membuat ulang berkas di repo: DUMMY_BACKUP_OUT=docs/test-data
    final out = Platform.environment['DUMMY_BACKUP_OUT'];
    final dir = (out != null
        ? Directory(out)
        : Directory.systemTemp.createTempSync('dummy_backup_'))
      ..createSync(recursive: true);
    File('${dir.path}/dummy-backup.bpos').writeAsBytesSync(bytes);
    File('${dir.path}/dummy-backup.json').writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert({
      'schemaVersion': db.schemaVersion,
      'tables': dump,
    }));
    final readme = StringBuffer()
      ..writeln('# Data dummy backup — Toko Berkah Jaya (DEMO)')
      ..writeln()
      ..writeln('Dibuat otomatis oleh `test/dummy_backup_generator_test.dart` '
          '(`DUMMY_BACKUP_OUT=docs/test-data flutter test test/dummy_backup_generator_test.dart`).')
      ..writeln()
      ..writeln('- Berkas: `dummy-backup.bpos` (format BPOP2, terenkripsi)')
      ..writeln('- **Password: `$kDummyPassword`**')
      ..writeln('- Skema DB: v${db.schemaVersion}')
      ..writeln('- Pakai: Pengaturan > Backup & Restore > Impor, pilih berkas, isi password. '
          'PERINGATAN: restore MENIMPA seluruh data di perangkat (pakai build **beta**).')
      ..writeln('- `dummy-backup.json` = isi mentah (tanpa enkripsi) untuk dibaca.')
      ..writeln()
      ..writeln('## Jumlah baris per tabel')
      ..writeln()
      ..writeln('| Tabel | Baris |')
      ..writeln('|---|---|');
    for (final e in counts.entries) {
      readme.writeln('| ${e.key} | ${e.value} |');
    }
    File('${dir.path}/README.md').writeAsStringSync(readme.toString());

    // Round-trip: dekripsi -> restore ke DB kosong.
    final dec = await DbExportService.decrypt(
        fileBytes: bytes, password: kDummyPassword, storeKey: '', storeUuid: '');
    final db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db2.close());
    await DbExportService.restore(db: db2, payload: dec.payload);
    final dump2 = await db2.dumpAllTables();
    for (final e in dump.entries) {
      expect(dump2[e.key]!.length, e.value.length, reason: 'tabel ${e.key}');
    }
  });
}
