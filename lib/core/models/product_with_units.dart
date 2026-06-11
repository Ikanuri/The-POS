import '../database/app_database.dart';

/// Produk beserta varian (unit) dan barcode primary-nya.
class ProductWithUnits {
  ProductWithUnits({
    required this.product,
    required this.units,
    required this.barcodes,
  });

  final Product product;
  final List<ProductUnit> units;
  final List<ProductBarcode> barcodes;

  /// Nama grup bila ada.
  String? groupName;

  /// Stok per unit (diisi setelah query stok).
  Map<String, double> stockByUnitId = {};

  /// Harga jual base unit (diisi dari price_tiers minQty=1).
  Map<String, int> basePriceByUnitId = {};

  ProductUnit? get baseUnit =>
      units.where((u) => u.isBaseUnit).firstOrNull ?? units.firstOrNull;
}
