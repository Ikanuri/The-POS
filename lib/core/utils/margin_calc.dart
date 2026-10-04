// Item 91 (keputusan user) — kalkulator "Margin" dua arah di form produk:
// ketik margin -> harga jual terisi; ubah harga jual/HPP -> margin dihitung
// ulang. HANYA bantuan input: yang disimpan tetap harga jual (+ HPP), margin
// tidak pernah disimpan (tanpa schema/sync). Rumus = MARKUP DARI MODAL,
// sama persis dgn Kategori Harga (pakai ulang `price_category_calc.dart`
// berjangkar 'modal') supaya hasilnya konsisten.
import 'price_category_calc.dart';

/// Margin dari harga jual & HPP. null bila HPP <= 0 (kolom Margin dimatikan).
double? marginFromPrice({
  required int costPrice,
  required int sellPrice,
  required bool isPercent,
}) {
  if (costPrice <= 0) return null;
  return computeMarginValue(
    basePrice: sellPrice,
    costPrice: costPrice,
    sellPrice: sellPrice,
    marginAnchor: kMarginAnchorModal,
    marginType: isPercent ? kMarginTypePercent : kMarginTypeFixed,
  );
}

/// Harga jual dari HPP & margin, dibulatkan rupiah. null bila HPP <= 0.
int? priceFromMargin({
  required int costPrice,
  required double margin,
  required bool isPercent,
}) {
  if (costPrice <= 0) return null;
  final p = computeCategoryPrice(
    basePrice: 0,
    costPrice: costPrice,
    marginAnchor: kMarginAnchorModal,
    marginType: isPercent ? kMarginTypePercent : kMarginTypeFixed,
    marginValue: margin,
  );
  return p < 0 ? 0 : p;
}

/// Teks margin utk kolom: persen maks 2 desimal (koma, nol dibuang),
/// rupiah bulat tanpa pemisah (kolom angka mentah, sama spt kolom harga).
String formatMarginInput(double v, {required bool isPercent}) {
  if (!isPercent) return v.round().toString();
  final r = double.parse(v.toStringAsFixed(2));
  var t = r.toStringAsFixed(2);
  t = t.replaceFirst(RegExp(r'\.?0+$'), '');
  return t.replaceAll('.', ',');
}

/// Parse kolom margin: terima koma/titik desimal & tanda minus.
double? parseMarginInput(String raw) {
  final t = raw.trim().replaceAll(',', '.');
  if (t.isEmpty || t == '-' || t == '.') return null;
  return double.tryParse(t);
}
