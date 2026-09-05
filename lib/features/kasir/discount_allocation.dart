import '../../core/models/cart_item.dart';

/// Arah pembulatan hasil diskon % — dipakai mode "Diskon %" di dialog
/// "Ubah Total" (`_editTotal`, payment_screen.dart).
enum RoundDirection { up, down, nearest }

/// Hasil hitung diskon % : nominal diskon MENTAH (sebelum dibulatkan) dan
/// total AKHIR setelah dibulatkan ke kelipatan [multiple] sesuai arah.
class PercentDiscountResult {
  const PercentDiscountResult({
    required this.rawDiscount,
    required this.roundedTotal,
  });

  /// Nominal diskon sebelum pembulatan (cartTotal * percent / 100, dibulatkan
  /// ke rupiah terdekat) — murni untuk ditampilkan sbg pembanding di preview,
  /// TIDAK dipakai sbg hasil akhir.
  final int rawDiscount;

  /// Total AKHIR (cartTotal - diskon, sudah dibulatkan) — inilah yang
  /// dipakai sbg `_totalOverride`.
  final int roundedTotal;
}

/// Hitung total setelah diskon [percent]% dari [cartTotal], dibulatkan ke
/// kelipatan [multiple] rupiah sesuai [direction]. [percent] dalam rentang
/// 0-100 (di luar itu di-clamp). [multiple] <= 1 berarti tanpa pembulatan
/// (total mentah dipakai apa adanya).
///
/// PENTING: [cartTotal] harus total keranjang APA ADANYA (bukan total yang
/// sudah pernah di-override sebelumnya) — supaya diskon % konsisten & tidak
/// "menumpuk" kalau dialog "Ubah Total" dibuka berkali-kali.
///
/// Hasil akhir DI-CLAMP ke rentang [0, cartTotal] — pembulatan "Naik" dgn
/// kelipatan kasar + persen kecil bisa secara teori mendorong total di atas
/// cartTotal asli (jadi bukan diskon lagi, tapi surcharge) atau di bawah 0;
/// keduanya tidak masuk akal utk fitur "diskon" jadi dibatasi.
PercentDiscountResult applyPercentDiscount({
  required int cartTotal,
  required double percent,
  required int multiple,
  required RoundDirection direction,
}) {
  final clampedPercent = percent.clamp(0, 100);
  final rawDiscount = (cartTotal * clampedPercent / 100).round();
  final rawTotal = cartTotal - rawDiscount;

  int roundedTotal;
  if (multiple <= 1) {
    roundedTotal = rawTotal;
  } else {
    switch (direction) {
      case RoundDirection.up:
        roundedTotal = ((rawTotal + multiple - 1) ~/ multiple) * multiple;
        break;
      case RoundDirection.down:
        roundedTotal = (rawTotal ~/ multiple) * multiple;
        break;
      case RoundDirection.nearest:
        roundedTotal = ((rawTotal + (multiple ~/ 2)) ~/ multiple) * multiple;
        break;
    }
  }
  roundedTotal = roundedTotal.clamp(0, cartTotal);
  return PercentDiscountResult(rawDiscount: rawDiscount, roundedTotal: roundedTotal);
}

/// Satu baris hasil alokasi total ke item keranjang — dipakai untuk membangun
/// `TransactionItemsCompanion` saat menyimpan transaksi / tambah-belanjaan.
class AllocatedCartLine {
  const AllocatedCartLine({
    required this.item,
    required this.effectiveQty,
    required this.subtotal,
    required this.unitPrice,
    required this.priceOverridden,
  });

  final CartItem item;
  final double effectiveQty;
  final int subtotal;
  final int unitPrice;
  final bool priceOverridden;
}

/// Alokasikan [total] (bisa berbeda dari [cartTotal] karena diskon manual /
/// pembulatan yang diterapkan di layar bayar) secara proporsional ke tiap
/// baris item keranjang, sehingga Σsubtotal persis == [total] — struk &
/// laporan tetap konsisten. Baris dengan qty efektif 0 (induk placeholder
/// varian) dilewati. Baris TERAKHIR (qty efektif > 0) menyerap sisa
/// pembulatan agar tidak ada rupiah yang hilang/lebih akibat pembulatan
/// per-baris.
///
/// Bila [cartTotal] <= 0 atau [total] == [cartTotal], tidak ada diskon —
/// subtotal & harga per unit sama seperti harga asli tiap baris. HPP
/// (costPrice) tidak pernah diutak-atik oleh alokasi ini → laba tetap
/// akurat terlepas dari diskon manual.
List<AllocatedCartLine> allocateCartTotal({
  required List<CartItem> items,
  required double Function(CartItem item) effectiveQtyOf,
  required int total,
  required int cartTotal,
}) {
  final discountFactor = cartTotal > 0 ? total / cartTotal : 1.0;
  final applyDiscount = discountFactor != 1.0;

  final lines = items.where((item) => effectiveQtyOf(item) > 0).map((item) {
    final eq = effectiveQtyOf(item);
    return (item: item, eq: eq, base: (item.price * eq).round());
  }).toList();

  var lastQtyIdx = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].eq > 0) lastQtyIdx = i;
  }

  final result = <AllocatedCartLine>[];
  var allocated = 0;
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    int sub;
    if (!applyDiscount) {
      sub = l.base;
    } else if (i == lastQtyIdx) {
      sub = total - allocated; // baris terakhir menyerap sisa pembulatan
    } else {
      sub = (l.base * discountFactor).round();
      allocated += sub;
    }
    final unitPrice =
        (applyDiscount && l.eq > 0) ? (sub / l.eq).round() : l.item.price;
    result.add(AllocatedCartLine(
      item: l.item,
      effectiveQty: l.eq,
      subtotal: sub,
      unitPrice: unitPrice,
      priceOverridden: l.item.priceOverridden || applyDiscount,
    ));
  }
  return result;
}
