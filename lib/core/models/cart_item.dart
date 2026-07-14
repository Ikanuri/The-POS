import 'package:flutter/foundation.dart';

@immutable
class CartItem {
  const CartItem({
    required this.productId,
    required this.productUnitId,
    required this.productName,
    required this.unitName,
    required this.qty,
    required this.price,
    required this.originalPrice,
    required this.costPrice,
    this.priceOverridden = false,
    this.itemNote,
    this.barcode,
    this.parentProductId,
    this.parentProductUnitId,
    this.isVariant = false,
    this.checked = false,
  });

  final String productId;
  final String productUnitId;
  final String productName;
  final String unitName;
  final double qty;
  final int price;
  final int originalPrice;
  final int costPrice;
  final bool priceOverridden;
  final String? itemNote;
  final String? barcode;

  /// Bila item ini varian (produk anak), berisi id produk induk agar di
  /// keranjang & struk tampil bersarang di bawah induknya.
  final String? parentProductId;

  /// Item 16: id SATUAN induk spesifik tempat varian ini menempel. Lebih
  /// presisi dari [parentProductId] — bila satu produk punya >1 baris satuan
  /// non-varian di keranjang (mis. Dus + Pcs), varian tahu menempel ke baris
  /// satuan yang MANA. Null pada data lama (dipersist sebelum Item 16) →
  /// fallback ke [parentProductId] di [belongsToParent].
  final String? parentProductUnitId;
  final bool isVariant;

  /// Checklist verifikasi barang sebelum bayar (mis. cek fisik sambil
  /// packing) — independen dari qty/harga. Diteruskan jadi nilai awal
  /// `checkedItemIds` transaksi saat checkout, lalu Struk melanjutkan
  /// checklist ini dari titik yang sama (lihat `receipt_screen.dart`).
  final bool checked;

  /// True bila varian ini menempel ke baris satuan induk [parentLine].
  /// Prioritas [parentProductUnitId] (presisi per-satuan); fallback ke
  /// [parentProductId] untuk data lama yang belum punya id satuan induk.
  bool belongsToParent(CartItem parentLine) {
    if (!isVariant || parentLine.isVariant) return false;
    if (parentProductUnitId != null) {
      return parentProductUnitId == parentLine.productUnitId;
    }
    return parentProductId == parentLine.productId;
  }

  int get subtotal => (price * qty).round();

  /// Sentinel agar [copyWith] bisa membedakan "tidak diubah" (parameter
  /// dihilangkan) dari "set ke null" (hapus catatan). Tanpa ini, mengirim
  /// `itemNote: null` tak bisa menghapus catatan yang sudah ada.
  static const Object _unset = Object();

  CartItem copyWith({
    double? qty,
    int? price,
    bool? priceOverridden,
    Object? itemNote = _unset,
    bool? checked,
  }) =>
      CartItem(
        productId: productId,
        productUnitId: productUnitId,
        productName: productName,
        unitName: unitName,
        qty: qty ?? this.qty,
        price: price ?? this.price,
        originalPrice: originalPrice,
        costPrice: costPrice,
        priceOverridden: priceOverridden ?? this.priceOverridden,
        itemNote: identical(itemNote, _unset)
            ? this.itemNote
            : itemNote as String?,
        barcode: barcode,
        parentProductId: parentProductId,
        parentProductUnitId: parentProductUnitId,
        isVariant: isVariant,
        checked: checked ?? this.checked,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productUnitId': productUnitId,
        'productName': productName,
        'unitName': unitName,
        'qty': qty,
        'price': price,
        'originalPrice': originalPrice,
        'costPrice': costPrice,
        'priceOverridden': priceOverridden,
        'itemNote': itemNote,
        'barcode': barcode,
        'parentProductId': parentProductId,
        'parentProductUnitId': parentProductUnitId,
        'isVariant': isVariant,
        'checked': checked,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: json['productId'] as String,
        productUnitId: json['productUnitId'] as String,
        productName: json['productName'] as String,
        unitName: json['unitName'] as String,
        qty: (json['qty'] as num).toDouble(),
        price: json['price'] as int,
        originalPrice: json['originalPrice'] as int,
        costPrice: json['costPrice'] as int,
        priceOverridden: json['priceOverridden'] as bool? ?? false,
        itemNote: json['itemNote'] as String?,
        barcode: json['barcode'] as String?,
        parentProductId: json['parentProductId'] as String?,
        parentProductUnitId: json['parentProductUnitId'] as String?,
        isVariant: json['isVariant'] as bool? ?? false,
        checked: json['checked'] as bool? ?? false,
      );
}
