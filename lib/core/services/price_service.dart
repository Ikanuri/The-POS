import '../database/app_database.dart';

/// Resolusi harga, prioritas tertinggi ke terendah:
/// 1. Customer group price (pelanggan terdaftar dengan group)
/// 2. Qty tier — minQty terbesar yang <= qty
/// 3. Fallback — tier minQty = 1
class PriceService {
  PriceService(this._db);

  final AppDatabase _db;

  Future<ResolvedPrice> resolvePrice({
    required String productUnitId,
    required double qty,
    String? customerGroupId,
  }) async {
    if (customerGroupId != null) {
      final groupPrice =
          await _db.getCustomerGroupPrice(productUnitId, customerGroupId);
      if (groupPrice != null) {
        // Harga jual dari grup, tapi HPP tetap dari tier — harga grup tidak
        // punya kolom cost. Tanpa ini costAtSale tercatat 0 dan laba di
        // laporan melonjak palsu untuk penjualan harga-grup.
        final tiers = await _db.getPriceTiers(productUnitId); // minQty DESC
        PriceTier? costTier;
        for (final t in tiers) {
          if (t.minQty <= qty) {
            costTier = t;
            break;
          }
        }
        if (costTier == null && tiers.isNotEmpty) costTier = tiers.last;
        return ResolvedPrice(
            price: groupPrice.price,
            costPrice: costTier?.costPrice ?? 0,
            source: PriceSource.customerGroup);
      }
    }

    final tiers = await _db.getPriceTiers(productUnitId); // minQty DESC
    if (tiers.isEmpty) {
      return const ResolvedPrice(price: 0, source: PriceSource.none);
    }

    for (final tier in tiers) {
      if (tier.minQty <= qty) {
        return ResolvedPrice(
          price: tier.price,
          costPrice: tier.costPrice,
          source: tier.minQty > 1 ? PriceSource.qtyTier : PriceSource.base,
        );
      }
    }
    // qty di bawah semua tier (mis. 0.5 saat tier terkecil minQty=1):
    // pakai tier terkecil.
    final base = tiers.last;
    return ResolvedPrice(
        price: base.price, costPrice: base.costPrice, source: PriceSource.base);
  }
}

enum PriceSource { customerGroup, qtyTier, base, none }

class ResolvedPrice {
  const ResolvedPrice({
    required this.price,
    this.costPrice = 0,
    required this.source,
  });

  final int price;
  final int costPrice;
  final PriceSource source;
}
