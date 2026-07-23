import 'dart:math';

import '../database/app_database.dart';

/// Generator barcode internal — EAN-13 dgn prefix `29` (2 digit), reserved
/// resmi oleh GS1 sbg "Restricted Circulation Number" khusus pemakaian
/// internal toko. Kode dgn prefix ini DIJAMIN tidak akan pernah dipakai
/// produk manufaktur resmi di mana pun, jadi aman dari tabrakan dgn barcode
/// asli — beda dari kode 8-digit "asal tempel angka" yang selama ini dipakai
/// toko (lihat analisis perbandingan induk-cabang, banyak produk beda malah
/// kebetulan sama formatnya). Tetap format EAN-13 standar (13 digit +
/// checksum valid) supaya scanner/kamera yang sudah dipakai app ini baca
/// tanpa perubahan apa pun, dan otomatis lolos heuristik "barcode resmi
/// 13-digit numerik" di `PriceMatchService`.
String _ean13Checksum(String digits12) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = int.parse(digits12[i]);
    sum += (i % 2 == 0) ? d : d * 3;
  }
  return ((10 - (sum % 10)) % 10).toString();
}

/// Generate barcode EAN-13 internal yang BELUM dipakai di [db]. Melempar
/// [StateError] kalau gagal menemukan kode unik setelah beberapa percobaan
/// (praktis mustahil — ruang kode 10^10 per prefix). Parameter [random]
/// dapat di-inject (mis. `Random(seed)`) khusus untuk test deterministik —
/// produksi selalu pakai default `Random()` non-seeded.
Future<String> generateInternalBarcode(AppDatabase db, {Random? random}) async {
  final rnd = random ?? Random();
  for (var attempt = 0; attempt < 20; attempt++) {
    final seq = List.generate(10, (_) => rnd.nextInt(10)).join();
    final base = '29$seq';
    final candidate = base + _ean13Checksum(base);
    final exists = await db.lookupBarcode(candidate);
    if (exists == null) return candidate;
  }
  throw StateError('Gagal generate barcode unik setelah 20 percobaan');
}
