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

  int get subtotal => (price * qty).round();

  CartItem copyWith({
    double? qty,
    int? price,
    bool? priceOverridden,
    String? itemNote,
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
        itemNote: itemNote ?? this.itemNote,
        barcode: barcode,
      );
}
