import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/services/order_parser_service.dart';

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
}
