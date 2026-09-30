// Usulan user (sesi 83) — "Isi per Satuan" boleh dihitung dari satuan lain
// (mis. 1 dus = 4 bal, bal = 2.000 biji -> dus = 8.000). Ini HANYA bantuan
// input: hasilnya disimpan sbg `ratioToBase` biasa (snapshot, tanpa kolom
// baru) — mengubah isi "bal" belakangan TIDAK mengubah "dus".

/// Satuan acuan: [name] & isinya dalam satuan dasar (satuan dasar = 1).
typedef RatioReference = ({String name, double ratioToBase});

/// [count] x isi satuan acuan, dibulatkan 6 desimal (buang derau floating
/// point). null bila masukan tidak valid (<= 0 / bukan angka hingga).
double? ratioFromReference({
  required double count,
  required double referenceRatioToBase,
}) {
  if (!count.isFinite || !referenceRatioToBase.isFinite) return null;
  if (count <= 0 || referenceRatioToBase <= 0) return null;
  final v = double.parse((count * referenceRatioToBase).toStringAsFixed(6));
  return v > 0 ? v : null;
}

/// Angka isi tanpa ".0" di belakang — 8000.0 -> "8000", 0.5 -> "0.5".
String formatRatio(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
