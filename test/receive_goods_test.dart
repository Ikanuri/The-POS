import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/receive_text_parser.dart';

/// Penerimaan Barang: tempel teks dari tools cek-stok eksternal, qty
/// MENAMBAH stok (bukan menimpa spt opname). Pencocokan PERSIS saja
/// (keputusan user — tidak ada fuzzy), ambiguitas diselesaikan lewat
/// pilihan manual yang lalu DIINGAT di kamus.
late AppDatabase db;

Future<void> _product(String pid, String uid, String name,
    {double ratio = 1, bool base = true}) async {
  await db.into(db.products).insert(
      ProductsCompanion.insert(id: pid, name: name));
  await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: uid,
        productId: pid,
        isBaseUnit: Value(base),
        ratioToBase: Value(ratio),
      ));
}

Future<double> _stock(String uid) async {
  final rows = await db.customSelect(
    'SELECT stock_after FROM stock_ledger WHERE product_unit_id = ? '
    'ORDER BY created_at DESC, rowid DESC LIMIT 1',
    variables: [Variable.withString(uid)],
  ).get();
  return rows.isEmpty ? 0 : (rows.first.data['stock_after'] as num).toDouble();
}

void main() {
  group('Parser teks', () {
    test('format "qty satuan nama"', () {
      final p = ReceiveTextParser.parseLine('5 pcs Indomie Goreng')!;
      expect(p.qty, 5);
      expect(p.unit, 'pcs');
      expect(p.name, 'Indomie Goreng');
    });

    test('header tanggal ala tools user DIABAIKAN', () {
      expect(ReceiveTextParser.parseLine('── Hari ini ──'), isNull);
      expect(ReceiveTextParser.parseLine('── Kemarin ──'), isNull);
      expect(ReceiveTextParser.parseLine('── 11 Agu ──'), isNull);
      expect(ReceiveTextParser.parseLine('-----'), isNull);
    });

    test('qty desimal: koma maupun titik diterima', () {
      expect(ReceiveTextParser.parseLine('2,5 kg Beras')!.qty, 2.5);
      expect(ReceiveTextParser.parseLine('2.5 kg Beras')!.qty, 2.5);
    });

    test(
        'baris TANPA satuan -> satuan dibiarkan KOSONG, seluruh sisa jadi '
        'nama (jangan sampai kata pertama nama salah dibaca sbg satuan)', () {
      final p = ReceiveTextParser.parseLine('3 Beras')!;
      expect(p.unit, '');
      expect(p.name, 'Beras');
    });

    test('parse teks penuh: data terkumpul, sampah masuk `unparsed`', () {
      final r = ReceiveTextParser.parse('''
── Hari ini ──
5 pcs Indomie Goreng
2 dus Aqua

barang rusak tanpa angka
''');
      expect(r.lines, hasLength(2));
      expect(r.lines.first.name, 'Indomie Goreng');
      expect(r.unparsed, ['barang rusak tanpa angka'],
          reason: 'baris berisi yang gagal diparse TIDAK dibuang diam-diam');
    });
  });

  group('Pencocokan & kamus', () {
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('nama PERSIS (beda huruf besar/kecil & spasi) -> ketemu', () async {
      await _product('p1', 'u1', 'Indomie Goreng');
      final uid = await db.resolveReceiveUnit(
          name: '  indomie   goreng ', unit: 'pcs');
      expect(uid, 'u1');
    });

    test('nama TIDAK persis -> TIDAK dicocokkan (tidak ada fuzzy)', () async {
      await _product('p1', 'u1', 'Indomie Goreng');
      expect(await db.resolveReceiveUnit(name: 'Indomie Grg', unit: 'pcs'),
          isNull,
          reason: 'keputusan user: pencocokan persis saja, ambiguitas '
              'diselesaikan manual lewat dropdown');
    });

    test('nama sama dimiliki 2 produk -> ambigu, null (biar user pilih)',
        () async {
      await _product('p1', 'u1', 'Beras');
      await _product('p2', 'u2', 'Beras');
      expect(await db.resolveReceiveUnit(name: 'Beras', unit: 'kg'), isNull);
    });

    test('setelah dipelajari, teks yang SAMA langsung ketemu', () async {
      await _product('p1', 'u1', 'Indomie Goreng');
      expect(await db.resolveReceiveUnit(name: 'Indomie Grg', unit: 'pcs'),
          isNull);

      await db.learnReceiveAlias(
          name: 'Indomie Grg', unit: 'pcs', productUnitId: 'u1');

      expect(await db.resolveReceiveUnit(name: 'Indomie Grg', unit: 'pcs'),
          'u1');
    });

    test(
        'kamus 2 tingkat: dipelajari DENGAN satuan, teks TANPA satuan '
        '(atau satuan lain) tetap ketemu lewat kunci fallback', () async {
      await _product('p1', 'u1', 'Indomie Goreng');
      await db.learnReceiveAlias(
          name: 'Indomie Grg', unit: 'pcs', productUnitId: 'u1');

      expect(await db.resolveReceiveUnit(name: 'Indomie Grg', unit: ''), 'u1');
      expect(
          await db.resolveReceiveUnit(name: 'Indomie Grg', unit: 'dus'), 'u1');
    });

    test('memilih ulang menimpa alias lama (bukan bikin duplikat)', () async {
      await _product('p1', 'u1', 'Beras A');
      await _product('p2', 'u2', 'Beras B');
      await db.learnReceiveAlias(
          name: 'beras premium', unit: 'kg', productUnitId: 'u1');
      await db.learnReceiveAlias(
          name: 'beras premium', unit: 'kg', productUnitId: 'u2');

      expect(await db.resolveReceiveUnit(name: 'beras premium', unit: 'kg'),
          'u2');
      final all = await db.getReceiveAliases();
      expect(all.where((a) => a.normalizedName == 'beras premium'), hasLength(2),
          reason: '2 kunci (ber-satuan + fallback), BUKAN 4 baris duplikat');
    });

    test('alias menunjuk satuan yang sudah dihapus -> diabaikan, tidak '
        'mengembalikan id hantu', () async {
      await _product('p1', 'u1', 'Beras');
      await db.learnReceiveAlias(
          name: 'beras x', unit: 'kg', productUnitId: 'u1');
      await (db.delete(db.productUnits)..where((t) => t.id.equals('u1'))).go();

      expect(await db.resolveReceiveUnit(name: 'beras x', unit: 'kg'), isNull);
    });
  });

  group('Commit penerimaan', () {
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('qty MENAMBAH stok (bukan menimpa spt opname)', () async {
      await _product('p1', 'u1', 'Beras');
      await db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl0',
            productUnitId: 'u1',
            type: 'opening',
            qtyChange: 10,
            stockAfter: 10,
            createdAt: Value(DateTime.now().subtract(const Duration(days: 1))),
          ));

      await db.commitReceive(
        entries: [(productUnitId: 'u1', qty: 4)],
        note: AppDatabase.buildReceiveNote(DateTime.now()),
        kasirId: 'K1',
      );

      expect(await _stock('u1'), 14,
          reason: 'penerimaan menambah; opname yang menimpa');
    });

    test('satuan non-dasar dikonversi ke satuan dasar lewat ratioToBase',
        () async {
      await _product('p1', 'u1', 'Aqua');
      // Satuan "dus" isi 24 dari produk yang sama.
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
            id: 'u1-dus',
            productId: 'p1',
            isBaseUnit: const Value(false),
            ratioToBase: const Value(24),
          ));

      await db.commitReceive(
        entries: [(productUnitId: 'u1-dus', qty: 2)],
        note: AppDatabase.buildReceiveNote(DateTime.now()),
        kasirId: 'K1',
      );

      expect(await _stock('u1'), 48,
          reason: '2 dus x isi 24 = 48 satuan dasar');
    });

    test('qty <= 0 dilewati, tidak bikin baris ledger sampah', () async {
      await _product('p1', 'u1', 'Beras');
      await db.commitReceive(
        entries: [(productUnitId: 'u1', qty: 0)],
        note: 'x',
        kasirId: 'K1',
      );
      final rows = await db.select(db.stockLedger).get();
      expect(rows, isEmpty);
    });
  });

  group('Sync kamus', () {
    test('kamus ikut dump KLIEN->HOST (includeMasterData: false) — beda dari '
        'master data yang sengaja satu arah', () async {
      db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _product('p1', 'u1', 'Beras');
      await db.learnReceiveAlias(
          name: 'beras x', unit: 'kg', productUnitId: 'u1');

      final dump = await db.dumpSince(DateTime(2000), includeMasterData: false);

      expect(dump['product_aliases'], isNotNull);
      expect(dump['product_aliases'], isNotEmpty,
          reason: 'permintaan user: kamus yang dipelajari kasir HARUS sampai '
              'ke owner, bukan cuma sebaliknya');
      expect(dump['products'], isNull,
          reason: 'master data TETAP tidak ikut naik — guard satu arah '
              'tidak boleh ikut longgar');
    });
  });
}
