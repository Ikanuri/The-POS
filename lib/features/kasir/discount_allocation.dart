import '../../core/models/cart_item.dart';

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
