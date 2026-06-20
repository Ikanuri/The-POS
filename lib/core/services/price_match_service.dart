import 'dart:math';

import '../database/app_database.dart';
import 'price_sync_service.dart';

enum MatchType { barcode, sku, fuzzy }

class PriceMatchResult {
  const PriceMatchResult({
    required this.matched,
    required this.notFound,
    required this.ambiguous,
  });
  final List<MatchedItem> matched;
  final List<PriceCatalogItem> notFound;
  final List<AmbiguousItem> ambiguous;
}

class MatchedItem {
  MatchedItem({
    required this.catalogItem,
    required this.localProductId,
    required this.localProductUnitId,
    required this.localProductName,
    required this.localPrice,
    required this.localCostPrice,
    required this.matchType,
    this.selected = true,
  });

  final PriceCatalogItem catalogItem;
  final String localProductId;
  final String localProductUnitId;
  final String localProductName;
  final int localPrice;
  final int localCostPrice;
  final MatchType matchType;
  bool selected;

  bool get priceChanged => catalogItem.price != localPrice;
  bool get costChanged => catalogItem.costPrice != localCostPrice;
  bool get hasChanges => priceChanged || costChanged;
}

class AmbiguousItem {
  AmbiguousItem({
    required this.catalogItem,
    required this.localProductId,
    required this.localProductUnitId,
    required this.localProductName,
    required this.localPrice,
    required this.localCostPrice,
    required this.similarity,
  });

  final PriceCatalogItem catalogItem;
  final String localProductId;
  final String localProductUnitId;
  final String localProductName;
  final int localPrice;
  final int localCostPrice;
  final double similarity;
}

class PriceMatchService {
  PriceMatchService._();

  static Future<PriceMatchResult> match({
    required AppDatabase db,
    required List<PriceCatalogItem> catalog,
  }) async {
    final matched = <MatchedItem>[];
    final notFound = <PriceCatalogItem>[];
    final ambiguous = <AmbiguousItem>[];

    final allProducts = await db.searchProducts('');
    // Peta unitTypeId → nama satuan, agar pencocokan bisa memilih unit yang
    // benar (mis. "Dus" vs "Pcs") alih-alih asal unit pertama.
    final unitTypes = await db.getAllUnitTypes();
    final typeNameById = {for (final u in unitTypes) u.id: u.name};

    for (final item in catalog) {
      final result = await _tryMatch(db, item, allProducts, typeNameById);
      if (result != null) {
        matched.add(result);
      } else {
        final fuzzyResult = _tryFuzzyMatch(item, allProducts);
        if (fuzzyResult != null) {
          final units = await db.getProductUnits(fuzzyResult.$1.id);
          if (units.isNotEmpty) {
            final unit =
                _resolveUnit(units, typeNameById, item.unitTypeName);
            final tiers = await db.getPriceTiers(unit.id);
            final baseTier =
                tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
            ambiguous.add(AmbiguousItem(
              catalogItem: item,
              localProductId: fuzzyResult.$1.id,
              localProductUnitId: unit.id,
              localProductName: fuzzyResult.$1.name,
              localPrice: baseTier?.price ?? 0,
              localCostPrice: baseTier?.costPrice ?? 0,
              similarity: fuzzyResult.$2,
            ));
          } else {
            notFound.add(item);
          }
        } else {
          notFound.add(item);
        }
      }
    }

    return PriceMatchResult(
      matched: matched,
      notFound: notFound,
      ambiguous: ambiguous,
    );
  }

  /// Pilih unit yang paling tepat untuk sebuah catalog item. Prioritas:
  /// 1) nama satuan sama (mis. "Dus"), 2) unit dasar, 3) unit pertama.
  static ProductUnit _resolveUnit(
    List<ProductUnit> units,
    Map<int, String> typeNameById,
    String wantTypeName,
  ) {
    final want = wantTypeName.trim().toLowerCase();
    if (want.isNotEmpty) {
      for (final u in units) {
        final tn =
            (u.unitTypeId != null ? typeNameById[u.unitTypeId!] : null) ?? '';
        if (tn.trim().toLowerCase() == want) return u;
      }
    }
    return units.where((u) => u.isBaseUnit).firstOrNull ?? units.first;
  }

  static Future<MatchedItem?> _tryMatch(
    AppDatabase db,
    PriceCatalogItem item,
    List<Product> allProducts,
    Map<int, String> typeNameById,
  ) async {
    // 1. Match by barcode → unit persis (barcode menempel di satu unit).
    if (item.barcode != null && item.barcode!.isNotEmpty) {
      final bc = await db.lookupBarcode(item.barcode!);
      if (bc != null) {
        final unit = await (db.select(db.productUnits)
              ..where((t) => t.id.equals(bc.productUnitId)))
            .getSingleOrNull();
        if (unit != null) {
          final product = allProducts.where((p) => p.id == unit.productId).firstOrNull;
          if (product != null) {
            final tiers = await db.getPriceTiers(unit.id);
            final baseTier =
                tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
            return MatchedItem(
              catalogItem: item,
              localProductId: product.id,
              localProductUnitId: unit.id,
              localProductName: product.name,
              localPrice: baseTier?.price ?? 0,
              localCostPrice: baseTier?.costPrice ?? 0,
              matchType: MatchType.barcode,
            );
          }
        }
      }
    }

    // 2. Match by SKU → produk, lalu unit yang cocok berdasarkan nama satuan.
    if (item.kodeProduk != null && item.kodeProduk!.isNotEmpty) {
      final skuLower = item.kodeProduk!.toLowerCase();
      final product = allProducts.where(
        (p) => p.kodeProduk?.toLowerCase() == skuLower,
      ).firstOrNull;
      if (product != null) {
        final units = await db.getProductUnits(product.id);
        if (units.isNotEmpty) {
          final unit = _resolveUnit(units, typeNameById, item.unitTypeName);
          final tiers = await db.getPriceTiers(unit.id);
          final baseTier =
              tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
          return MatchedItem(
            catalogItem: item,
            localProductId: product.id,
            localProductUnitId: unit.id,
            localProductName: product.name,
            localPrice: baseTier?.price ?? 0,
            localCostPrice: baseTier?.costPrice ?? 0,
            matchType: MatchType.sku,
          );
        }
      }
    }

    return null;
  }

  static (Product, double)? _tryFuzzyMatch(
    PriceCatalogItem item,
    List<Product> allProducts,
  ) {
    const threshold = 0.6;
    Product? bestProduct;
    double bestScore = 0;

    final itemName = item.productName.toLowerCase();

    for (final product in allProducts) {
      final localName = product.name.toLowerCase();
      final score = _similarity(itemName, localName);
      if (score > bestScore && score >= threshold) {
        bestScore = score;
        bestProduct = product;
      }
    }

    if (bestProduct != null) {
      return (bestProduct, bestScore);
    }
    return null;
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final distance = _levenshtein(a, b);
    final maxLen = max(a.length, b.length);
    return 1.0 - (distance / maxLen);
  }

  static int _levenshtein(String a, String b) {
    final n = a.length;
    final m = b.length;
    final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));

    for (var i = 0; i <= n; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      dp[0][j] = j;
    }

    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce(min);
      }
    }

    return dp[n][m];
  }
}
