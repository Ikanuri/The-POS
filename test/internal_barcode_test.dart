import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/internal_barcode.dart';

/// Fitur "Generate Barcode" — EAN-13 dgn prefix `29` (reserved GS1 utk
/// pemakaian internal toko, TIDAK PERNAH dipakai produk manufaktur resmi)
/// supaya produk non-barcode (mis. Telur/Kg) bisa dapat identitas barcode
/// tanpa risiko tabrakan dgn barcode asli.
bool _isValidEan13(String code) {
  if (code.length != 13) return false;
  if (!RegExp(r'^\d{13}$').hasMatch(code)) return false;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = int.parse(code[i]);
    sum += (i % 2 == 0) ? d : d * 3;
  }
  final expectedCheck = (10 - (sum % 10)) % 10;
  return int.parse(code[12]) == expectedCheck;
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('barcode yang dihasilkan format EAN-13 valid dgn prefix 29', () async {
    final code = await generateInternalBarcode(db, random: Random(1));
    expect(code.startsWith('29'), isTrue);
    expect(_isValidEan13(code), isTrue,
        reason: 'checksum EAN-13 harus valid: $code');
  });

  test('tidak pernah bentrok dgn barcode yang sudah ada di DB — kandidat '
      'pertama yang collide otomatis dilewati', () async {
    // Ambil kandidat PERTAMA yang dihasilkan seed tertentu (DB kosong).
    final firstCandidate = await generateInternalBarcode(db, random: Random(7));

    // Simulasikan barcode itu SUDAH terpakai produk lain (unit type id 1
    // sudah ada dari seed default `AppDatabase`, tidak perlu insert lagi).
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Produk A'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', unitTypeId: const Value(1)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 1000)
        ]
      },
      barcodesByUnitTempId: {
        'u1': [
          ProductBarcodesCompanion.insert(
              id: 'b1', productUnitId: 'u1', barcode: firstCandidate),
        ]
      },
      altPricesByUnitTempId: const {},
    );

    // Generate ULANG dgn seed SAMA (Random(7) mulai dari state awal yg
    // sama) — kandidat pertama yg dicoba pasti = firstCandidate lagi
    // (barcode sudah terpakai), jadi fungsi WAJIB lanjut ke kandidat
    // berikutnya, BUKAN mengembalikan firstCandidate yang bentrok.
    final result = await generateInternalBarcode(db, random: Random(7));
    expect(result, isNot(equals(firstCandidate)));
    expect(_isValidEan13(result), isTrue);

    final lookup = await db.lookupBarcode(result);
    expect(lookup, isNull,
        reason: 'kode yg dikembalikan harus benar2 belum dipakai di DB');
  });
}
