import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/purchase_ai_format.dart';

/// PLAN Item 90 tahap 5 — parser "Tempel hasil AI". Acuan = faktur contoh
/// Indomarco dari owner (nomor 124256-RPS).
void main() {
  // Balasan AI realistis: diawali kalimat & dibungkus pagar kode, angka
  // sebagian berformat string ("167,621"), satu saran id produk tak dikenal.
  const reply = '''Berikut hasil pembacaan faktur:
```json
{
  "versi": 1,
  "faktur": [{
    "nomor": "124256-RPS",
    "tanggal": "28/09/2026",
    "supplier": "PT Indomarco Adi Prima",
    "harga_termasuk_ppn": true,
    "potongan_faktur": 0,
    "total_bayar": 4983779,
    "total_ppn": 493888,
    "baris": [
      {"nama": "Terigu Payung 5 kg x 4 Pa", "satuan": "ZAK", "isi": 4,
       "qty_besar": 5, "qty_kecil": 0, "harga_satuan": "167,621",
       "potongan_persen": 0, "potongan_rupiah": 0, "jumlah_bersih": 838106,
       "product_unit_id": "zak-terigu", "yakin": true},
      {"nama": "Terigu Segitiga Biru 5 kg", "satuan": "ZAK", "isi": 4,
       "qty_besar": 5, "qty_kecil": 0, "harga_satuan": 195543,
       "potongan_persen": 0, "potongan_rupiah": 0, "jumlah_bersih": 977715,
       "product_unit_id": null, "yakin": true},
      {"nama": "Krimer Kental Manis Tiga Sapi", "satuan": "CAR", "isi": 48,
       "qty_besar": 3, "qty_kecil": 0, "harga_satuan": 590450,
       "potongan_persen": 0, "potongan_rupiah": 0, "jumlah_bersih": 1771350,
       "product_unit_id": "ngarang", "yakin": true},
      {"nama": "Susu Steril Indomilk CH", "satuan": "CAR", "isi": 24,
       "qty_besar": 6, "qty_kecil": 0, "harga_satuan": 85848,
       "potongan_persen": 0.58, "potongan_rupiah": 3000,
       "jumlah_bersih": 512088, "product_unit_id": null, "yakin": true},
      {"nama": "Susu Kental Manis Indomilk Plain", "satuan": "CAR",
       "isi": 120, "qty_besar": 6, "qty_kecil": 0, "harga_satuan": 150920,
       "potongan_persen": 2.32, "potongan_rupiah": 21000,
       "jumlah_bersih": 884520, "product_unit_id": null, "yakin": true}
    ]
  }]
}
```
Semoga membantu.''';

  test('faktur contoh terbaca utuh & lolos validasi total/PPN', () {
    final r = parsePurchaseAiResponse(reply, knownUnitIds: {'zak-terigu'});
    expect(r.ok, isTrue);
    final inv = r.invoices.single;
    expect(inv.invoiceNo, '124256-RPS');
    expect(inv.invoiceDate, DateTime(2026, 9, 28));
    expect(inv.lines, hasLength(5));
    expect(inv.lines[0].unitPrice, 167621, reason: 'string "167,621" = ribuan');
    expect(inv.lines[0].productUnitId, 'zak-terigu');
    expect(inv.lines[3].discount, 3000);
    expect(inv.problems, isEmpty,
        reason: 'total 5 baris - potongan = total tercetak; PPN tepat 11%');
    expect(inv.lines[2].productUnitId, isNull,
        reason: 'id karangan AI dibuang');
    expect(inv.lines[2].problems, isNotEmpty);
  });

  test('salah baca harga (390.450 vs 590.450) tertangkap validasi', () {
    final wrong = reply.replaceFirst('590450', '390450');
    final inv = parsePurchaseAiResponse(wrong, knownUnitIds: const {})
        .invoices
        .single;
    expect(inv.lines[2].problems.join(), contains('Jumlah bersih'));
    expect(inv.problems.join(), contains('Total faktur'));
  });

  test('qty dua bagian & potongan persen', () {
    const t = '{"faktur":[{"baris":[{"nama":"X","satuan":"CAR","isi":24,'
        '"qty_besar":2,"qty_kecil":6,"harga_satuan":24000,'
        '"potongan_persen":10,"potongan_rupiah":0}]}]}';
    final l = parsePurchaseAiResponse(t, knownUnitIds: const {})
        .invoices
        .single
        .lines
        .single;
    expect(l.qty, 2.25);
    expect(l.discount, 5400);
  });

  test('teks rusak / tanpa JSON -> pesan jelas', () {
    expect(parsePurchaseAiResponse('maaf saya tidak bisa',
            knownUnitIds: const {})
        .error, isNotNull);
    expect(parsePurchaseAiResponse('{"faktur": [', knownUnitIds: const {})
        .error, isNotNull);
  });

  test('parseLooseNumber', () {
    expect(parseLooseNumber('167.621'), 167621);
    expect(parseLooseNumber('1.234,5'), 1234.5);
    expect(parseLooseNumber('12,5'), 12.5);
    expect(parseLooseNumber('Rp 5.000'), 5000);
    expect(parseLooseNumber(2.32), 2.32);
    expect(parseLooseNumber(''), isNull);
  });

  test('prompt melarang kode & hitungan; CSV tanpa harga', () async {
    final p = buildPurchaseAiPrompt();
    expect(p, contains('JANGAN menulis kode'));
    expect(p, contains('JANGAN menghitung'));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'P1', name: 'Terigu, Payung'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'pak',
        productId: 'P1',
        unitTypeId: const Value(1),
        isBaseUnit: const Value(true)));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'zak',
        productId: 'P1',
        unitTypeId: const Value(2),
        ratioToBase: const Value(4.0)));
    final csv = buildPurchaseAiCsv(await db.getPurchaseAiCsvRows());
    final lines = csv.trim().split('\n');
    expect(lines.first,
        'product_unit_id,nama_produk,satuan,isi_dalam_satuan_dasar,satuan_dasar');
    expect(lines, hasLength(3));
    expect(lines[1], startsWith('pak,"Terigu, Payung",'));
    expect(lines[2], contains(',4,'));
    expect(csv.toLowerCase(), isNot(contains('harga')));
  });
}
