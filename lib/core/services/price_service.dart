import '../database/app_database.dart';

/// Resolusi harga, prioritas tertinggi ke terendah:
/// 1. Kategori Harga aktif (`activeCategoryId`, Fase C — toggle di keranjang;
///    HANYA menang bila produk ini TERDAFTAR di kategori itu, lihat
///    `AppDatabase.getCategoryPriceFor`; kalau tidak terdaftar, lanjut ke
///    prioritas di bawah persis seolah `activeCategoryId` tidak diisi).
///    Catatan: manual override harga per-baris (`CartItem.priceOverridden`)
///    ada di LUAR fungsi ini — level pemanggil (`cart_sheet.dart`) yang
///    menjamin baris ter-override TIDAK PERNAH dikirim ke sini dgn
///    `activeCategoryId` terisi lagi (lihat `repriceCartForCategoryChange`).
/// 2. Customer group price (pelanggan terdaftar dengan group)
/// 3. Qty tier — minQty terbesar yang <= qty
/// 4. Fallback — tier minQty = 1
class PriceService {
  PriceService(this._db);

  final AppDatabase _db;

  Future<ResolvedPrice> resolvePrice({
    required String productUnitId,
    required double qty,
    String? customerGroupId,
    String? activeCategoryId,
  }) async {
    if (activeCategoryId != null) {
      final catPrice =
          await _db.getCategoryPriceFor(productUnitId, activeCategoryId);
      if (catPrice != null) {
        // HPP tetap dari tier qty yang berlaku — baris AltPrices kategori
        // tidak punya kolom cost sendiri (pola SAMA dgn cabang customerGroup
        // di bawah: harga jual dari sumber lain, HPP selalu dari tier qty
        // produk, supaya laba di laporan tidak melonjak palsu/costPrice 0).
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
            price: catPrice,
            costPrice: costTier?.costPrice ?? 0,
            source: PriceSource.category);
      }
    }

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

enum PriceSource { category, customerGroup, qtyTier, base, none }

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
