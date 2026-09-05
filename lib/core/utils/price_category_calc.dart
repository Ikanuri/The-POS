/// Kalkulasi murni harga "Kategori Harga" (Fase B) — sengaja dipisah dari
/// `AppDatabase` supaya gampang diuji tanpa DB (lihat
/// `test/price_category_calc_test.dart`).
///
/// Margin bisa diisi 2 arah (keputusan desain user, `PLAN.md`/briefing):
/// (a) owner ketik harga jual target -> [computeMarginValue] hitung margin
///     yang disimpan; (b) owner ketik margin langsung -> [computeCategoryPrice]
///     hitung harga jual hasilnya. Kedua arah menulis ke field yang SAMA
///     (margin = sumber kebenaran) sehingga begitu disimpan, harga TIDAK
///     BEKU — kalau harga acuan produk berubah nanti, harga kategori ikut
///     bergerak otomatis (live-computed saat dibaca).
library;

/// Acuan margin yang valid — `'modal'` (HPP/`costPrice` tier) atau
/// `'dasar'` (harga jual dasar, tier `minQty=1`).
const kMarginAnchorModal = 'modal';
const kMarginAnchorDasar = 'dasar';

/// Jenis margin yang valid — `'percent'` atau `'fixed'` (Rupiah tetap).
const kMarginTypePercent = 'percent';
const kMarginTypeFixed = 'fixed';

/// Resolusi nilai acuan (modal atau dasar) + GUARD anchor 'modal' tanpa HPP.
///
/// KEPUTUSAN: anchor 'modal' dengan `costPrice<=0` dianggap TIDAK VALID
/// (sebagian produk toko nyata belum diisi HPP — bukan kasus langka, lihat
/// briefing). UI WAJIB mencegah kombinasi ini (opsi "Harga Modal" disabled
/// kalau costPrice produk<=0), TAPI fungsi murni di sini tetap melempar
/// [ArgumentError] eksplisit alih-alih diam-diam menghitung "persen dari
/// nol" atau mengarang angka — supaya bug (baik di UI maupun data lama yang
/// tidak konsisten) ketahuan jelas saat dites, bukan menghasilkan harga
/// yang salah tanpa peringatan. Pemanggil level-DB (`AppDatabase.
/// getAltPrices`) membungkus pemanggilan ini dengan try/catch & fallback ke
/// harga snapshot terakhir yang tersimpan — supaya satu baris data lama/
/// tidak konsisten tidak menggagalkan seluruh query, sementara logic
/// kalkulasi inti sendiri tetap gagal keras & jelas.
int _resolveAnchorValue(String marginAnchor, int basePrice, int costPrice) {
  switch (marginAnchor) {
    case kMarginAnchorModal:
      if (costPrice <= 0) {
        throw ArgumentError(
            'Acuan "Harga Modal" tidak valid untuk produk ini: HPP '
            '(costPrice) belum diisi (<=0). Pilih acuan "Harga Dasar" atau '
            'isi HPP produk dulu.');
      }
      return costPrice;
    case kMarginAnchorDasar:
      return basePrice;
    default:
      throw ArgumentError(
          'marginAnchor tidak dikenal: "$marginAnchor" (harus '
          '"$kMarginAnchorModal" atau "$kMarginAnchorDasar").');
  }
}

void _validateMarginType(String marginType) {
  if (marginType != kMarginTypePercent && marginType != kMarginTypeFixed) {
    throw ArgumentError(
        'marginType tidak dikenal: "$marginType" (harus '
        '"$kMarginTypePercent" atau "$kMarginTypeFixed").');
  }
}

/// Hitung harga jual dari acuan (modal/dasar) + margin (persen/Rp tetap),
/// dibulatkan ke rupiah bulat terdekat.
///
/// `percent`: `acuan * (1 + marginValue/100)`.
/// `fixed`: `acuan + marginValue`.
int computeCategoryPrice({
  required int basePrice,
  required int costPrice,
  required String marginAnchor,
  required String marginType,
  required double marginValue,
}) {
  _validateMarginType(marginType);
  final anchor = _resolveAnchorValue(marginAnchor, basePrice, costPrice);
  final result = marginType == kMarginTypePercent
      ? anchor * (1 + marginValue / 100)
      : anchor + marginValue;
  return result.round();
}

/// Kebalikan [computeCategoryPrice] — dari harga jual TARGET, hitung margin
/// yang disimpan (sumber kebenaran, lihat dok library).
double computeMarginValue({
  required int basePrice,
  required int costPrice,
  required int sellPrice,
  required String marginAnchor,
  required String marginType,
}) {
  _validateMarginType(marginType);
  final anchor = _resolveAnchorValue(marginAnchor, basePrice, costPrice);
  if (marginType == kMarginTypePercent) {
    if (anchor == 0) {
      // Tidak seharusnya tercapai (_resolveAnchorValue sudah menjamin
      // anchor 'modal' > 0, dan anchor 'dasar' = basePrice — produk tanpa
      // harga dasar sudah kasus rusak duluan), tapi dijaga eksplisit demi
      // menghindari pembagian dgn nol yang diam-diam menghasilkan
      // Infinity/NaN.
      throw ArgumentError(
          'Tidak bisa menghitung persen margin dari acuan bernilai 0.');
    }
    return (sellPrice - anchor) / anchor * 100;
  }
  return (sellPrice - anchor).toDouble();
}
