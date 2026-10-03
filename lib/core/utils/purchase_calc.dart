// PLAN Item 90 tahap 1 — perhitungan murni Input Pembelian (tanpa DB/
// Flutter, mudah dites): HPP dari harga faktur dgn diskon, PPN, dan isi
// satuan. Keputusan user/owner (3 Okt 2026):
//  * Perlakuan PPN FLEKSIBEL PER BARIS — 'modal' (PPN masuk modal),
//    'pisah' (modal tanpa PPN, PPN masukan dicatat), 'bebas' (barang
//    tidak kena PPN, harga apa adanya).
//  * Faktur distributor umumnya mencetak harga SUDAH TERMASUK PPN & PPN
//    hanya di total (faktur contoh Indomarco) -> [priceIncludesTax].
//  * Aplikasi yang menghitung — hitungan dari sumber luar (mis. AI) tidak
//    pernah dipakai mentah.
// Contoh: Terigu 5 ZAK @Rp167.621 (inkl PPN 11%), isi 4 pak/ZAK, 'pisah'
// -> HPP Rp37.752/pak, PPN masukan Rp83.056 (seluruh baris).

/// Perlakuan PPN per baris pembelian.
enum PurchaseTaxTreatment {
  /// PPN masuk ke modal (HPP = harga termasuk PPN).
  modal('modal'),

  /// HPP tanpa PPN; PPN masukan dicatat terpisah.
  pisah('pisah'),

  /// Barang tidak kena PPN — harga dipakai apa adanya.
  bebas('bebas');

  const PurchaseTaxTreatment(this.code);
  final String code;

  static PurchaseTaxTreatment? fromCode(String? code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// Hasil hitung satu baris pembelian.
typedef PurchaseLineResult = ({
  /// qty x harga faktur (sebelum diskon).
  int gross,

  /// gross - diskon (nilai baris di faktur, apa adanya).
  int net,

  /// Dasar Pengenaan Pajak (nilai tanpa PPN).
  int dpp,

  /// PPN yang terkandung/dikenakan pada baris ini (0 utk 'bebas').
  int tax,

  /// PPN masukan yang DICATAT (hanya perlakuan 'pisah', selain itu 0).
  int inputTax,

  /// HPP per 1 satuan DASAR (rupiah bulat). null bila qty/isi tidak valid.
  int? costPerBaseUnit,
});

/// Hitung satu baris. [qty] dalam satuan beli (boleh desimal), [unitPrice]
/// harga faktur per satuan beli, [discount] potongan rupiah total baris
/// (termasuk alokasi diskon faktur), [taxRate] persen (mis. 11),
/// [ratioToBase] isi satuan beli dalam satuan dasar (satuan dasar = 1).
PurchaseLineResult computePurchaseLine({
  required double qty,
  required int unitPrice,
  int discount = 0,
  required bool priceIncludesTax,
  required PurchaseTaxTreatment treatment,
  required double taxRate,
  required double ratioToBase,
}) {
  final gross = (qty * unitPrice).round();
  var net = gross - discount;
  if (net < 0) net = 0;
  final r = taxRate / 100;
  double dpp;
  double tax;
  if (treatment == PurchaseTaxTreatment.bebas || r <= 0) {
    dpp = net.toDouble();
    tax = 0;
  } else if (priceIncludesTax) {
    dpp = net / (1 + r);
    tax = net - dpp;
  } else {
    dpp = net.toDouble();
    tax = net * r;
  }
  final costTotal =
      treatment == PurchaseTaxTreatment.modal ? dpp + tax : dpp;
  int? costPerBase;
  if (qty > 0 && ratioToBase > 0) {
    costPerBase = (costTotal / qty / ratioToBase).round();
  }
  final taxInt = tax.round();
  return (
    gross: gross,
    net: net,
    dpp: dpp.round(),
    tax: taxInt,
    inputTax: treatment == PurchaseTaxTreatment.pisah ? taxInt : 0,
    costPerBaseUnit: costPerBase,
  );
}

/// Bagi diskon tingkat faktur [invoiceDiscount] ke baris secara
/// proporsional terhadap [lineNets]; sisa pembulatan ke baris TERAKHIR yang
/// bernilai > 0, supaya jumlahnya persis sama dgn diskon faktur.
List<int> allocateInvoiceDiscount(List<int> lineNets, int invoiceDiscount) {
  final total = lineNets.fold<int>(0, (s, v) => s + (v > 0 ? v : 0));
  if (invoiceDiscount <= 0 || total <= 0) {
    return List.filled(lineNets.length, 0);
  }
  final out = <int>[];
  var used = 0;
  var lastIdx = -1;
  for (var i = 0; i < lineNets.length; i++) {
    final v = lineNets[i] > 0 ? lineNets[i] : 0;
    final share = (invoiceDiscount * v / total).floor();
    out.add(share);
    used += share;
    if (v > 0) lastIdx = i;
  }
  if (lastIdx >= 0) out[lastIdx] += invoiceDiscount - used;
  return out;
}

/// Persentase perubahan HPP (baru vs lama). null bila HPP lama <= 0
/// (belum pernah diisi — tidak ada acuan).
double? costChangePercent(int oldCost, int newCost) {
  if (oldCost <= 0) return null;
  return (newCost - oldCost) / oldCost * 100;
}

/// true bila perubahan HPP melampaui ambang peringatan [thresholdPercent]
/// (pengaturan toko, default 30). HPP lama kosong -> tidak diperingatkan.
bool exceedsCostChangeThreshold(
    int oldCost, int newCost, double thresholdPercent) {
  final p = costChangePercent(oldCost, newCost);
  return p != null && p.abs() > thresholdPercent;
}
