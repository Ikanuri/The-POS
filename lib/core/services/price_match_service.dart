import 'dart:math';

import '../database/app_database.dart';
import 'price_sync_service.dart';

enum MatchType { barcode, sku, fuzzy }

class PriceMatchResult {
  const PriceMatchResult({
    required this.matched,
    required this.notFound,
    required this.ambiguous,
    required this.log,
  });
  final List<MatchedItem> matched;
  final List<PriceCatalogItem> notFound;
  final List<AmbiguousItem> ambiguous;
  final List<String> log;
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
    final log = <String>[];

    log.add('=== MATCH START: ${catalog.length} catalog items ===');

    final allProducts = await db.searchProducts('');
    log.add('Produk lokal aktif: ${allProducts.length}');

    final unitTypes = await db.getAllUnitTypes();
    final typeNameById = {for (final u in unitTypes) u.id: u.name};

    for (final item in catalog) {
      final result = await _tryMatch(db, item, allProducts, typeNameById, log);
      if (result != null) {
        matched.add(result);
      } else {
        final fuzzyResult = _tryFuzzyMatch(item, allProducts);
        if (fuzzyResult != null) {
          log.add('  → Fuzzy match: "${fuzzyResult.$1.name}" '
              '(${(fuzzyResult.$2 * 100).round()}%)');
          final units = await db.getProductUnits(fuzzyResult.$1.id);
          if (units.isNotEmpty) {
            final unit =
                _resolveUnit(units, typeNameById, item.unitTypeName);
            final tiers = await db.getPriceTiers(unit.id);
            log.add('    Tiers untuk unit ${_short(unit.id)}: '
                '${tiers.map((t) => 'minQty=${t.minQty} price=${t.price} id=${_short(t.id)}').join(' | ')}');
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
            log.add('  → Fuzzy match tapi tidak ada unit → notFound');
            notFound.add(item);
          }
        } else {
          log.add('  → Tidak cocok sama sekali → notFound');
          notFound.add(item);
        }
      }
    }

    log.add('=== MATCH DONE: ${matched.length} cocok, '
        '${notFound.length} baru, ${ambiguous.length} mirip ===');

    return PriceMatchResult(
      matched: matched,
      notFound: notFound,
      ambiguous: ambiguous,
      log: log,
    );
  }

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

  /// Seperti [_resolveUnit] tapi TANPA fallback ke base unit bila satuan yang
  /// diminta tidak ada — kembalikan null. Dipakai jalur auto-match SKU yang
  /// harus ketat (SKU sinyal lemah antar-toko; wajib satuannya benar-benar
  /// ada agar tidak salah tempel harga). Bila katalog tidak menyertakan nama
  /// satuan (`wantTypeName` kosong), tak bisa lebih ketat → pakai base unit.
  static ProductUnit? _resolveUnitStrict(
    List<ProductUnit> units,
    Map<int, String> typeNameById,
    String wantTypeName,
  ) {
    final want = wantTypeName.trim().toLowerCase();
    if (want.isEmpty) {
      return units.where((u) => u.isBaseUnit).firstOrNull ?? units.firstOrNull;
    }
    for (final u in units) {
      final tn =
          (u.unitTypeId != null ? typeNameById[u.unitTypeId!] : null) ?? '';
      if (tn.trim().toLowerCase() == want) return u;
    }
    return null;
  }

  static Future<MatchedItem?> _tryMatch(
    AppDatabase db,
    PriceCatalogItem item,
    List<Product> allProducts,
    Map<int, String> typeNameById,
    List<String> log,
  ) async {
    log.add('[${item.productName}] catalog: price=${item.price}, '
        'cost=${item.costPrice}, barcode=${item.barcode ?? "null"}, '
        'sku=${item.kodeProduk ?? "null"}, unit="${item.unitTypeName}"');

    // 1. Match by barcode
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
            final tierCount = tiers.where((t) => t.minQty == 1).length;
            log.add('  → Barcode match: unit=${_short(unit.id)}, '
                'product="${product.name}"');
            log.add('    Tiers minQty=1: $tierCount buah → '
                '${tiers.where((t) => t.minQty == 1).map((t) => 'id=${_short(t.id)} price=${t.price} cost=${t.costPrice}').join(' | ')}');
            final baseTier =
                tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
            log.add('    baseTier dipilih: id=${_short(baseTier?.id ?? "?")} '
                'price=${baseTier?.price ?? 0} cost=${baseTier?.costPrice ?? 0}');
            if (tierCount > 1) {
              log.add('    ⚠ DUPLIKAT TIER! $tierCount tier minQty=1 untuk unit ini');
            }
            return MatchedItem(
              catalogItem: item,
              localProductId: product.id,
              localProductUnitId: unit.id,
              localProductName: product.name,
              localPrice: baseTier?.price ?? 0,
              localCostPrice: baseTier?.costPrice ?? 0,
              matchType: MatchType.barcode,
            );
          } else {
            log.add('  → Barcode ditemukan tapi produk tidak di allProducts '
                '(inactive?) productId=${unit.productId}');
          }
        } else {
          log.add('  → Barcode ditemukan tapi unit hilang: ${bc.productUnitId}');
        }
      } else {
        log.add('  → Barcode "${item.barcode}" tidak ada di DB');
      }
    }

    // 2. Match by SKU — HANYA aman bila kode UNIK & satuan cocok.
    if (item.kodeProduk != null && item.kodeProduk!.isNotEmpty) {
      final skuLower = item.kodeProduk!.toLowerCase();
      final skuMatches = allProducts
          .where((p) => p.kodeProduk?.toLowerCase() == skuLower)
          .toList();

      if (skuMatches.length > 1) {
        // Tabrakan SKU: kode_produk tidak unik (mis. banyak produk berkode
        // nama satuan "Dos"/"Pak"/"Bal"). Ambil-pertama-sembarang dulu bikin
        // item nyasar ke produk tak berhubungan & harga saling-timpa tiap
        // sync (non-konvergen). Jangan tebak — biarkan fuzzy-nama fallback
        // yang tangani (masuk tab "Mirip" utk konfirmasi manual).
        log.add('  → SKU "${item.kodeProduk}" cocok ke ${skuMatches.length} '
            'produk (TABRAKAN, kode tidak unik) → tidak auto-match via SKU');
      } else if (skuMatches.length == 1) {
        final product = skuMatches.first;
        final units = await db.getProductUnits(product.id);
        if (units.isEmpty) {
          log.add('  → SKU match tapi tidak ada unit untuk product "${product.name}"');
        } else {
          // Perketat: satuan katalog HARUS ada di produk lokal. Cegah item
          // spt "76 12/bal" nyasar ke "Atira 2000" hanya karena kebetulan
          // berkode "bal" padahal tak punya satuan "Bal".
          final unit = _resolveUnitStrict(units, typeNameById, item.unitTypeName);
          if (unit == null) {
            log.add('  → SKU match "${product.name}" tapi satuan '
                '"${item.unitTypeName}" tidak ada di produk itu → tolak, '
                'coba fuzzy');
          } else {
            final tiers = await db.getPriceTiers(unit.id);
            final baseTier = tiers.where((t) => t.minQty == 1).firstOrNull ??
                tiers.firstOrNull;
            log.add('  → SKU match: unit=${_short(unit.id)}, '
                'product="${product.name}", ${units.length} units total');
            log.add('    baseTier dipilih: id=${_short(baseTier?.id ?? "?")} '
                'price=${baseTier?.price ?? 0}');
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
      } else {
        log.add('  → SKU "${item.kodeProduk}" tidak cocok');
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

  static String _short(String uuid) =>
      uuid.length > 8 ? uuid.substring(0, 8) : uuid;
}
