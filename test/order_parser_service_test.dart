import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/services/order_parser_service.dart';
import 'package:the_pos/core/theme/app_theme.dart' show formatRupiah;

/// Test Tier 1 (DB murni) untuk fitur eksperimental "Tempel Pesanan" —
/// sisi kasir yang membaca teks pesanan hasil Katalog Pesanan (HTML) dan
/// mencocokkannya balik ke data produk lokal.

Future<String> _addProduct(
  AppDatabase db, {
  required String name,
  required int price,
  int costPrice = 0,
  bool isActive = true,
  String? parentProductId,
  int unitTypeId = 2, // Pcs
}) async {
  final productId = 'p-${DateTime.now().microsecondsSinceEpoch}-$name';
  final unitId = '$productId-u';
  await db.into(db.products).insert(ProductsCompanion.insert(
        id: productId,
        name: name,
        isActive: Value(isActive),
        parentProductId: Value(parentProductId),
      ));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId,
        productId: productId,
        unitTypeId: Value(unitTypeId),
        isBaseUnit: const Value(true),
      ));
  await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: '$unitId-t1',
        productUnitId: unitId,
        minQty: const Value(1),
        price: price,
        costPrice: Value(costPrice),
      ));
  return productId;
}

Future<String> _unitIdOf(AppDatabase db, String productId) async {
  final u = await (db.select(db.productUnits)
        ..where((t) => t.productId.equals(productId)))
      .getSingle();
  return u.id;
}

void main() {
  test(
      'teks tanpa kode mesin (#PSN:) dilaporkan hasMachineCode=false, '
      'bukan error', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final result =
        await OrderParserService.parse(db: db, text: 'halo, ada gula?');
    expect(result.hasMachineCode, isFalse);
    expect(result.items, isEmpty);
    await db.close();
  });

  test(
      'parse berhasil: item cocok ke DB lokal dengan harga LIVE dari DB, '
      'bukan angka di teks pesanan (katalog terkirim bisa basi)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Gula Pasir', price: 15000);
    final unitId = await _unitIdOf(db, productId);

    // Harga di DB naik SETELAH katalog HTML dikirim ke pelanggan — teks
    // pesanan yang ditempel tidak membawa info harga sama sekali, murni
    // productUnitId + qty.
    await db.update(db.priceTiers).write(const PriceTiersCompanion(
          price: Value(17000),
        ));

    final text = 'Nama: Budi\nHP: 0812\n#PSN:$unitId=3;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.hasMachineCode, isTrue);
    expect(result.items, hasLength(1));
    expect(result.items.first.qty, 3);
    expect(result.items.first.price, 17000,
        reason: 'harga harus di-resolve ulang dari DB saat parse, bukan '
            'dari harga lama saat katalog dibuat');
    expect(result.customerName, 'Budi');
    expect(result.customerPhone, '0812');
    await db.close();
  });

  test('unitId dobel di kode mesin digabung qty-nya, bukan jadi 2 baris',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Minyak', price: 32000);
    final unitId = await _unitIdOf(db, productId);

    final text = '#PSN:$unitId=1;$unitId=2;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.items, hasLength(1),
        reason: 'unitId sama tidak boleh jadi baris keranjang terpisah');
    expect(result.items.first.qty, 3);
    await db.close();
  });

  test(
      'unitId yang sudah dihapus/dinonaktifkan sejak katalog dibuat masuk '
      'notFound, tidak menggagalkan baris valid lain', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Sabun', price: 5000);
    final unitId = await _unitIdOf(db, productId);
    await _addProduct(db, name: 'Dihapus', price: 1000, isActive: false);
    final ghostUnitId = await _unitIdOf(
        db,
        (await (db.select(db.products)..where((t) => t.name.equals('Dihapus')))
                .getSingle())
            .id);

    final text = '#PSN:$unitId=1;$ghostUnitId=1;unit-tak-ada=1;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.items, hasLength(1));
    expect(result.items.first.productName, 'Sabun');
    expect(result.notFound, containsAll([ghostUnitId, 'unit-tak-ada']));
    await db.close();
  });

  test(
      'baris Nama/HP bertanda "-" (fallback template saat pelanggan tidak '
      'isi field) diperlakukan sebagai kosong; baris Catatan yang tidak ada '
      'sama sekali (template melewatkannya bila kosong) juga null', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Beras', price: 65000);
    final unitId = await _unitIdOf(db, productId);

    final text = 'Nama: -\nHP: -\n#PSN:$unitId=1;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.customerName, isNull);
    expect(result.customerPhone, isNull);
    expect(result.note, isNull);
    await db.close();
  });

  test(
      'varian ikut ditandai isVariant+parentProductId agar keranjang bisa '
      'menjaga invariant stok induk', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final parentId = await _addProduct(db, name: 'Pop Ice', price: 2000);
    final variantId = await _addProduct(db,
        name: 'Coklat', price: 2500, parentProductId: parentId);
    final variantUnitId = await _unitIdOf(db, variantId);

    final text = '#PSN:$variantUnitId=2;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.items.first.isVariant, isTrue);
    expect(result.items.first.parentProductId, parentId);
    await db.close();
  });

  test(
      'Item 26a — segmen catatan per-produk ter-encodeURIComponent di-decode '
      'balik jadi itemNote, ikut ke CartItem', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Ayam', price: 25000);
    final unitId = await _unitIdOf(db, productId);

    // Catatan asli "yang matang; jangan pedas" — mengandung ';' mentah,
    // yang harus AMAN karena sisi HTML mengirim hasil encodeURIComponent.
    const encoded = 'yang%20matang%3B%20jangan%20pedas';
    final text = '#PSN:$unitId=2:$encoded;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.items, hasLength(1));
    expect(result.items.first.itemNote, 'yang matang; jangan pedas');
    expect(result.items.first.toCartItem().itemNote,
        'yang matang; jangan pedas');
    await db.close();
  });

  test(
      'Item 26a — item TANPA catatan (format lama "id=qty" polos) tetap '
      'parse normal, itemNote null (backward-compatible)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Gula Pasir', price: 15000);
    final unitId = await _unitIdOf(db, productId);

    final text = '#PSN:$unitId=3;';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.items, hasLength(1));
    expect(result.items.first.qty, 3);
    expect(result.items.first.itemNote, isNull);
    await db.close();
  });

  test(
      'Item 24d — baris "Pegawai: <nama>" di-parse jadi ParsedOrder.employeeName, '
      'pembeda handoff pegawai dari pesanan pelanggan biasa', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Gula Pasir', price: 15000);
    final unitId = await _unitIdOf(db, productId);

    final text = '#PSN:$unitId=2;\nPegawai: Budi';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.employeeName, 'Budi');
    expect(result.items, hasLength(1));
    await db.close();
  });

  test(
      'Item 24d — TANPA baris "Pegawai:" → employeeName null (pesanan '
      'pelanggan biasa, alur Tempel Pesanan tidak berubah)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Gula Pasir', price: 15000);
    final unitId = await _unitIdOf(db, productId);

    final text = '#PSN:$unitId=2;\nNama: Ani';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.employeeName, isNull);
    expect(result.customerName, 'Ani');
    await db.close();
  });

  test(
      'Bugfix — baris "Pegawai:" MENEMPEL ke kode mesin TANPA newline '
      '(scanner HID tertentu tidak mengirim embedded newline sbg Enter) '
      'tetap dikenali employeeName-nya, tidak salah rute ke Tempel Pesanan',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Gula Pasir', price: 15000);
    final unitId = await _unitIdOf(db, productId);

    // TANPA '\n' antara kode mesin & "Pegawai:" — meniru payload yang
    // datang sebagai SATU string utuh dari scanner yang tidak
    // menerjemahkan newline di dalam QR jadi keystroke Enter terpisah.
    final text = '#PSN:$unitId=2;Pegawai: Budi';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.employeeName, 'Budi');
    expect(result.items, hasLength(1));
    expect(result.items.first.qty, 2);
    await db.close();
  });

  test(
      'Bugfix — baris "Nama:" & "HP:" yang sama-sama menempel tanpa '
      'newline (mis. "Pegawai: BudiNama: AniHP: 0812") tetap terpisah benar',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final productId = await _addProduct(db, name: 'Gula Pasir', price: 15000);
    final unitId = await _unitIdOf(db, productId);

    final text = '#PSN:$unitId=1;Pegawai: BudiNama: AniHP: 0812';
    final result = await OrderParserService.parse(db: db, text: text);

    expect(result.employeeName, 'Budi');
    expect(result.customerName, 'Ani');
    expect(result.customerPhone, '0812');
    await db.close();
  });

  test(
      'Item 24d — encodeHandoff() menghasilkan teks yang bisa di-parse balik '
      'oleh parse() sendiri (round-trip), termasuk item dgn catatan', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final p1 = await _addProduct(db, name: 'Ayam Potong', price: 25000);
    final u1 = await _unitIdOf(db, p1);
    final p2 = await _addProduct(db, name: 'Beras', price: 12000);
    final u2 = await _unitIdOf(db, p2);

    final cart = [
      CartItem(
        productId: p1,
        productUnitId: u1,
        productName: 'Ayam Potong',
        unitName: 'Kg',
        qty: 2,
        price: 25000,
        originalPrice: 25000,
        costPrice: 18000,
        itemNote: 'yang segar; bukan beku',
      ),
      CartItem(
        productId: p2,
        productUnitId: u2,
        productName: 'Beras',
        unitName: 'Kg',
        qty: 5,
        price: 12000,
        originalPrice: 12000,
        costPrice: 10000,
      ),
    ];

    final encoded =
        OrderParserService.encodeHandoff(items: cart, employeeName: 'Budi');
    expect(encoded, startsWith('#PSN:'));
    expect(encoded, contains('Pegawai: Budi'));

    final result = await OrderParserService.parse(db: db, text: encoded);
    expect(result.employeeName, 'Budi');
    expect(result.items, hasLength(2));
    final ayam = result.items.firstWhere((i) => i.productId == p1);
    expect(ayam.qty, 2);
    expect(ayam.itemNote, 'yang segar; bukan beku',
        reason:
            'catatan dgn karakter ";" harus selamat lewat encode/decode');
    final beras = result.items.firstWhere((i) => i.productId == p2);
    expect(beras.qty, 5);
    expect(beras.itemNote, isNull);
    await db.close();
  });

  test(
      'Bug nyata dilaporkan user: handoff QR sekarang bawa SEMUA atribut '
      'keranjang (harga override, checklist verifikasi, status pre-order) '
      'ke penerima — bukan cuma nama barang+qty yang di-harga-ulang',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    // Harga produk di DB PENERIMA sengaja BEDA dari harga di keranjang
    // pengirim (mis. baru saja diubah, atau pengirim override manual) —
    // sebelum fix, parse() SELALU resolve fresh dari sini, menimpa harga
    // asli pengirim diam-diam.
    final p1 = await _addProduct(db, name: 'Ayam Potong', price: 30000);
    final u1 = await _unitIdOf(db, p1);
    final p2 = await _addProduct(db, name: 'Galon Aqua', price: 5000);
    final u2 = await _unitIdOf(db, p2);

    final cart = [
      CartItem(
        productId: p1,
        productUnitId: u1,
        productName: 'Ayam Potong',
        unitName: 'Kg',
        qty: 2,
        price: 27000, // Override manual pengirim, BEDA dari 30000 di DB.
        originalPrice: 30000,
        costPrice: 22000,
        priceOverridden: true,
        checked: true, // Sudah diverifikasi fisik oleh pengirim.
      ),
      CartItem(
        productId: p2,
        productUnitId: u2,
        productName: 'Galon Aqua',
        unitName: 'Galon',
        qty: 1,
        price: 0, // Pre-order belum dibayar — harga sengaja 0.
        originalPrice: 5000,
        costPrice: 4000,
        isPreorder: true,
        preorderPaid: false,
        depositQty: 1,
      ),
    ];

    final encoded =
        OrderParserService.encodeHandoff(items: cart, employeeName: 'Budi');
    final result = await OrderParserService.parse(db: db, text: encoded);
    expect(result.items, hasLength(2));

    final ayam = result.items.firstWhere((i) => i.productId == p1);
    expect(ayam.price, 27000,
        reason: 'harga override pengirim harus ikut, BUKAN di-resolve '
            'ulang jadi 30000 (harga terkini DB penerima)');
    expect(ayam.originalPrice, 30000);
    expect(ayam.priceOverridden, isTrue);
    expect(ayam.checked, isTrue,
        reason: 'checklist verifikasi pengirim harus ikut ke penerima');
    expect(ayam.toCartItem().priceOverridden, isTrue);
    expect(ayam.toCartItem().checked, isTrue);

    final galon = result.items.firstWhere((i) => i.productId == p2);
    expect(galon.price, 0);
    expect(galon.originalPrice, 5000);
    expect(galon.isPreorder, isTrue);
    expect(galon.preorderPaid, isFalse);
    expect(galon.depositQty, 1);
    final galonCart = galon.toCartItem();
    expect(galonCart.isPreorder, isTrue);
    expect(galonCart.depositQty, 1);

    await db.close();
  });

  test(
      'Susulan (kekhawatiran user, valid): encodeHandoff(trustPrices: false) '
      'utk device TANPA izin terima_pembayaran — harga TIDAK ikut dibawa '
      '(resolve fresh dari DB penerima), tapi checklist/status pre-order '
      'TETAP ikut (bukan itu yang jadi concern)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    // Harga DB penerima BEDA dari harga di keranjang pengirim — kalau
    // trustPrices:false TIDAK bekerja, test ini akan salah expect harga
    // override (27000) alih-alih harga live DB (30000).
    final p1 = await _addProduct(db, name: 'Ayam Potong', price: 30000);
    final u1 = await _unitIdOf(db, p1);

    final cart = [
      CartItem(
        productId: p1,
        productUnitId: u1,
        productName: 'Ayam Potong',
        unitName: 'Kg',
        qty: 2,
        // Pegawai TANPA izin bayar bisa saja mengatur Harga Lain/override
        // manual di keranjangnya sendiri (tidak digerbang izin apa pun di
        // item_entry_sheet.dart) — kalau ini ikut dibawa mentah-mentah,
        // owner menerima harga yang belum pernah divalidasi.
        price: 27000,
        originalPrice: 30000,
        costPrice: 22000,
        priceOverridden: true,
        checked: true,
      ),
    ];

    final encoded = OrderParserService.encodeHandoff(
        items: cart, employeeName: 'Budi', trustPrices: false);
    // Segmen harga TIDAK ADA sama sekali di kode mesin.
    expect(encoded, isNot(contains('|p=')));
    expect(encoded, isNot(contains('|o=')));
    expect(encoded, isNot(contains('|k=')));
    expect(encoded, isNot(contains('|v=')));
    // Tapi checklist verifikasi TETAP ada (bukan concern-nya harga).
    expect(encoded, contains('|c=1'));

    final result = await OrderParserService.parse(db: db, text: encoded);
    final ayam = result.items.single;
    expect(ayam.price, 30000,
        reason: 'harga override pengirim tak berizin TIDAK boleh dipakai — '
            'harus resolve fresh dari DB penerima');
    expect(ayam.priceOverridden, isFalse);
    expect(ayam.checked, isTrue,
        reason: 'checklist verifikasi TETAP ikut walau trustPrices:false');

    await db.close();
  });

  test(
      'Kode dari katalog HTML pelanggan (TANPA flag |p=/|c=/dst.) tetap '
      'resolve harga fresh dari DB — perilaku lama TIDAK berubah', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final p1 = await _addProduct(db, name: 'Ayam Potong', price: 25000);
    final u1 = await _unitIdOf(db, p1);

    // Format lama polos, PERSIS output buildOrderText() katalog HTML —
    // tidak ada segmen '|' apa pun setelah qty.
    final text = '#PSN:$u1=2';
    final result = await OrderParserService.parse(db: db, text: text);

    final ayam = result.items.single;
    expect(ayam.price, 25000, reason: 'tetap resolve fresh dari DB lokal');
    expect(ayam.originalPrice, 25000);
    expect(ayam.priceOverridden, isFalse);
    expect(ayam.checked, isFalse);
    expect(ayam.isPreorder, isFalse);
    await db.close();
  });

  test(
      'encodeHandoff() dgn customerName ikut baris "Nama:" — round-trip '
      'balik ke customerName (bukan cuma employeeName)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final p1 = await _addProduct(db, name: 'Ayam Potong', price: 25000);
    final u1 = await _unitIdOf(db, p1);

    final cart = [
      CartItem(
        productId: p1,
        productUnitId: u1,
        productName: 'Ayam Potong',
        unitName: 'Kg',
        qty: 1,
        price: 25000,
        originalPrice: 25000,
        costPrice: 18000,
      ),
    ];

    final encoded = OrderParserService.encodeHandoff(
      items: cart,
      employeeName: 'Budi',
      customerName: 'Siti',
    );
    expect(encoded, contains('Pegawai: Budi'));
    expect(encoded, contains('Nama: Siti'));

    final result = await OrderParserService.parse(db: db, text: encoded);
    expect(result.employeeName, 'Budi');
    expect(result.customerName, 'Siti',
        reason:
            'atribusi pelanggan yang dipilih pegawai harus ikut terbawa QR');
    await db.close();
  });

  test(
      'encodeHandoff() TANPA customerName (pegawai belum pilih pelanggan) → '
      'tidak ada baris "Nama:" sama sekali', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final p1 = await _addProduct(db, name: 'Ayam Potong', price: 25000);
    final u1 = await _unitIdOf(db, p1);
    final cart = [
      CartItem(
        productId: p1,
        productUnitId: u1,
        productName: 'Ayam Potong',
        unitName: 'Kg',
        qty: 1,
        price: 25000,
        originalPrice: 25000,
        costPrice: 18000,
      ),
    ];

    final encoded =
        OrderParserService.encodeHandoff(items: cart, employeeName: 'Budi');
    expect(encoded, isNot(contains('Nama:')));

    final result = await OrderParserService.parse(db: db, text: encoded);
    expect(result.customerName, isNull);
    await db.close();
  });

  group('Item 54 — encodeHandoff(storeName:) bawa keterangan item', () {
    test(
        'dgn storeName: keterangan item + Total tampil DI DEPAN kode mesin, '
        'format sama pola dgn buildOrderText() katalog HTML', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final p1 = await _addProduct(db, name: 'Ayam Potong', price: 25000);
      final u1 = await _unitIdOf(db, p1);
      final p2 = await _addProduct(db, name: 'Beras', price: 12000);
      final u2 = await _unitIdOf(db, p2);
      final cart = [
        CartItem(
          productId: p1,
          productUnitId: u1,
          productName: 'Ayam Potong',
          unitName: 'Kg',
          qty: 2,
          price: 25000,
          originalPrice: 25000,
          costPrice: 18000,
        ),
        CartItem(
          productId: p2,
          productUnitId: u2,
          productName: 'Beras',
          unitName: 'Kg',
          qty: 1,
          price: 12000,
          originalPrice: 12000,
          costPrice: 10000,
        ),
      ];

      final encoded = OrderParserService.encodeHandoff(
        items: cart,
        employeeName: 'Budi',
        storeName: 'Toko Segar',
      );

      expect(encoded, startsWith('PESANAN — Toko Segar\n'));
      expect(encoded, contains('Ayam Potong Kg × 2'));
      expect(encoded, contains('Beras Kg × 1'));
      expect(encoded, contains('Total: ${formatRupiah(62000)}'));
      // Kode mesin & baris meta tetap di BAWAH, urutan sama persis
      // buildOrderText() (manusia baca isi pesanan dulu, kode di akhir).
      expect(encoded.indexOf('#PSN:'), greaterThan(encoded.indexOf('Total:')));
      expect(encoded, contains('Pegawai: Budi'));

      final result = await OrderParserService.parse(db: db, text: encoded);
      expect(result.items, hasLength(2),
          reason: 'parse() harus tetap berhasil walau ada header baru di '
              'depan kode mesin — regex per-baris sudah mentolerir baris '
              'tambahan apa pun, sama seperti teks katalog HTML');
      expect(result.employeeName, 'Budi');
      await db.close();
    });

    test('TANPA storeName (default lama): tidak ada header "PESANAN —" sama '
        'sekali, perilaku lama utuh', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final p1 = await _addProduct(db, name: 'Ayam Potong', price: 25000);
      final u1 = await _unitIdOf(db, p1);
      final cart = [
        CartItem(
          productId: p1,
          productUnitId: u1,
          productName: 'Ayam Potong',
          unitName: 'Kg',
          qty: 1,
          price: 25000,
          originalPrice: 25000,
          costPrice: 18000,
        ),
      ];

      final encoded =
          OrderParserService.encodeHandoff(items: cart, employeeName: 'Budi');
      expect(encoded, isNot(contains('PESANAN —')));
      expect(encoded, startsWith('#PSN:'));

      final result = await OrderParserService.parse(db: db, text: encoded);
      expect(result.items, hasLength(1));
      await db.close();
    });

    test('varian (induk+anak): baris induk jadi header, anak diberi '
        'indentasi "  > ", baris qty=0 murni placeholder DILEWATI', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final parentId = await _addProduct(db, name: 'Kaos', price: 50000);
      final parentUnitId = await _unitIdOf(db, parentId);
      final childId =
          await _addProduct(db, name: 'Merah', price: 50000, parentProductId: parentId);
      final childUnitId = await _unitIdOf(db, childId);

      final cart = [
        // Placeholder induk (qty 0) — hanya penanda struktur grouping,
        // dibuat otomatis saat varian pertama ditambahkan (lihat
        // kasir_screen.dart), BUKAN barang yang dibeli.
        CartItem(
          productId: parentId,
          productUnitId: parentUnitId,
          productName: 'Kaos',
          unitName: 'Pcs',
          qty: 0,
          price: 50000,
          originalPrice: 50000,
          costPrice: 30000,
        ),
        CartItem(
          productId: childId,
          productUnitId: childUnitId,
          productName: 'Merah',
          unitName: 'Pcs',
          qty: 3,
          price: 50000,
          originalPrice: 50000,
          costPrice: 30000,
          parentProductId: parentId,
          isVariant: true,
        ),
      ];

      final encoded = OrderParserService.encodeHandoff(
        items: cart,
        employeeName: 'Budi',
        storeName: 'Toko Segar',
      );

      expect(encoded, contains('Kaos\n  > Merah Pcs × 3'),
          reason: 'header induk lalu baris varian berindentasi, baris '
              'placeholder qty=0 sendiri TIDAK ikut tampil sbg baris '
              'terpisah');
      expect(encoded, contains('Total: ${formatRupiah(150000)}'));

      final result = await OrderParserService.parse(db: db, text: encoded);
      expect(result.items, hasLength(1));
      expect(result.items.single.qty, 3);
      await db.close();
    });
  });

  group('Susulan — peringatan mismatch harga transfer transaksi', () {
    test(
        'kode transfer (flag |p= ADA) dgn harga pengirim BEDA dari resolve '
        'fresh lokal → priceTrustedFromSender=true, currentResolvedPrice = '
        'harga LOKAL (bukan harga dari flag)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final p1 = await _addProduct(db, name: 'Ayam Potong', price: 30000);
      final u1 = await _unitIdOf(db, p1);

      final cart = [
        CartItem(
          productId: p1,
          productUnitId: u1,
          productName: 'Ayam Potong',
          unitName: 'Kg',
          qty: 2,
          price: 27000, // Beda dari harga live DB penerima (30000).
          originalPrice: 27000,
          costPrice: 22000,
        ),
      ];
      final encoded =
          OrderParserService.encodeHandoff(items: cart, employeeName: 'Budi');
      final result = await OrderParserService.parse(db: db, text: encoded);

      final ayam = result.items.single;
      expect(ayam.priceTrustedFromSender, isTrue);
      expect(ayam.price, 27000,
          reason: 'harga yg DIPAKAI tetap harga pengirim (bukan koreksi)');
      expect(ayam.currentResolvedPrice, 30000,
          reason: 'currentResolvedPrice harus harga fresh lokal PENERIMA');
      await db.close();
    });

    test(
        'kode transfer dgn harga pengirim SAMA dgn resolve fresh lokal → '
        'currentResolvedPrice == price (tidak mismatch)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final p1 = await _addProduct(db, name: 'Beras', price: 12000);
      final u1 = await _unitIdOf(db, p1);

      final cart = [
        CartItem(
          productId: p1,
          productUnitId: u1,
          productName: 'Beras',
          unitName: 'Kg',
          qty: 1,
          price: 12000,
          originalPrice: 12000,
          costPrice: 10000,
        ),
      ];
      final encoded =
          OrderParserService.encodeHandoff(items: cart, employeeName: 'Budi');
      final result = await OrderParserService.parse(db: db, text: encoded);

      final beras = result.items.single;
      expect(beras.priceTrustedFromSender, isTrue);
      expect(beras.currentResolvedPrice, beras.price);
      await db.close();
    });

    test(
        'kode transfer dgn trustPrices:false (pengirim tak berwenang) → '
        'priceTrustedFromSender=false (flag |p= tidak disertakan)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final p1 = await _addProduct(db, name: 'Ayam Potong', price: 30000);
      final u1 = await _unitIdOf(db, p1);

      final cart = [
        CartItem(
          productId: p1,
          productUnitId: u1,
          productName: 'Ayam Potong',
          unitName: 'Kg',
          qty: 2,
          price: 27000,
          originalPrice: 27000,
          costPrice: 22000,
        ),
      ];
      final encoded = OrderParserService.encodeHandoff(
          items: cart, employeeName: 'Budi', trustPrices: false);
      final result = await OrderParserService.parse(db: db, text: encoded);

      final ayam = result.items.single;
      expect(ayam.priceTrustedFromSender, isFalse);
      expect(ayam.currentResolvedPrice, ayam.price,
          reason: 'tanpa flag harga, price = resolve fresh, jadi selalu sama');
      await db.close();
    });

    test(
        'kode katalog HTML pelanggan biasa (tanpa flag apa pun) → '
        'priceTrustedFromSender=false', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final p1 = await _addProduct(db, name: 'Gula Pasir', price: 15000);
      final u1 = await _unitIdOf(db, p1);

      final text = '#PSN:$u1=2';
      final result = await OrderParserService.parse(db: db, text: text);

      expect(result.items.single.priceTrustedFromSender, isFalse);
      await db.close();
    });

    test(
        'baris dobel (unitId sama muncul 2x, digabung qty) tetap set '
        'priceTrustedFromSender/currentResolvedPrice dari re-resolve, '
        'bukan konstruktor lama', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final p1 = await _addProduct(db, name: 'Minyak', price: 32000);
      final u1 = await _unitIdOf(db, p1);

      final cart = [
        CartItem(
          productId: p1,
          productUnitId: u1,
          productName: 'Minyak',
          unitName: 'Liter',
          qty: 1,
          price: 28000, // Beda dari harga live DB (32000).
          originalPrice: 28000,
          costPrice: 24000,
        ),
      ];
      final encoded =
          OrderParserService.encodeHandoff(items: cart, employeeName: 'Budi');
      // Duplikasi baris item manual (simulasi tempel 2x) — sisipkan segmen
      // sama lagi sebelum baris meta.
      final psnMatch = RegExp(r'#PSN:(.+)').firstMatch(encoded)!;
      final itemPart = psnMatch.group(1)!;
      final duped = encoded.replaceFirst(
          '#PSN:$itemPart', '#PSN:$itemPart;$itemPart');

      final result = await OrderParserService.parse(db: db, text: duped);
      expect(result.items, hasLength(1));
      final minyak = result.items.single;
      expect(minyak.qty, 2, reason: 'qty digabung dari 2 baris identik');
      expect(minyak.priceTrustedFromSender, isTrue);
      expect(minyak.currentResolvedPrice, 32000);
      await db.close();
    });
  });
}
