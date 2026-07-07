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
    this.isVariant = false,
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
  final bool isVariant;

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
        isVariant: isVariant,
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
        'isVariant': isVariant,
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
        isVariant: json['isVariant'] as bool? ?? false,
      );
}
