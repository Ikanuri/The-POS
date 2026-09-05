import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart' show PriceCategory;
import '../../core/models/cart_item.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/price_service.dart';

/// Fase C "Kategori Harga" — kategori AKTIF (toggle) di SATU keranjang
/// (`cartId`). Null = "Normal" (tidak ada toggle). Persist SharedPreferences
/// PERSIS pola `CartMetaNotifier` (`cart_meta_provider.dart`), key prefix
/// BEDA supaya tidak bentrok. HANYA relevan utk `kMainCartId` (mode Katalog/
/// Tambah Belanjaan tidak memakai provider ini sama sekali — lihat gerbang
/// di `cart_sheet.dart`).
class CartPriceCategoryNotifier extends StateNotifier<String?> {
  CartPriceCategoryNotifier(this.cartId) : super(null) {
    _load();
  }

  final String cartId;

  static const _prefPrefix = 'cartpricecat_v1_';
  String get _prefKey => '$_prefPrefix$cartId';
  bool _loaded = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (state == null) {
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        super.state = raw;
      }
    }
    _loaded = true;
  }

  void _persist() {
    final snapshot = state;
    SharedPreferences.getInstance().then((prefs) {
      if (snapshot == null) {
        prefs.remove(_prefKey);
      } else {
        prefs.setString(_prefKey, snapshot);
      }
    });
  }

  @override
  set state(String? value) {
    super.state = value;
    if (_loaded) _persist();
  }

  /// Ganti kategori aktif (null = kembali ke "Normal"). Re-price baris
  /// keranjang dilakukan TERPISAH oleh pemanggil (`cart_sheet.dart`) lewat
  /// [repriceCartForCategoryChange] SEBELUM/SESUDAH memanggil ini — notifier
  /// ini murni menyimpan id-nya, tidak menyentuh isi keranjang.
  void setCategory(String? categoryId) {
    state = categoryId;
  }

  void clear() {
    state = null;
  }
}

/// Kategori aktif per-slot keranjang. Lihat dok [CartPriceCategoryNotifier].
final cartPriceCategoryProvider =
    StateNotifierProvider.family<CartPriceCategoryNotifier, String?, String>(
  (ref, cartId) => CartPriceCategoryNotifier(cartId),
);

/// Gerbang izin toggle kategori harga — SAMA PERSIS berat/pola dgn
/// `canOverride` di `item_entry_sheet.dart::_load()` (mengubah harga jual =
/// setara override harga manual). Dipakai `cart_sheet.dart` (tampil/
/// sembunyikan baris chip toggle) — `item_entry_sheet.dart` sendiri sudah
/// punya `_canOverride`-nya sendiri (dihitung ulang lokal, tidak lewat
/// provider ini, supaya tidak mengubah pola yang sudah ada di sana).
final canOverrideHargaProvider = FutureProvider.autoDispose<bool>((ref) async {
  final device = ref.watch(deviceProvider);
  if (device.deviceRole != 'kasir') return true;
  final db = ref.watch(databaseProvider);
  return db.isPermissionEnabled('override_harga');
});

/// Daftar `PriceCategories` terdaftar — dipakai `cart_sheet.dart` utk
/// merender chip toggle (baris chip disembunyikan total bila kosong, lihat
/// gerbang di sana). SENGAJA `FutureProvider` (fetch sekali per kali sheet
/// dibuka), BUKAN `StreamProvider` reaktif — `CartSheet` dipakai di puluhan
/// test widget yang menutup `AppDatabase` di `tearDown` TANPA `drain()`
/// (gotcha CLAUDE.md: `StreamProvider` yg masih subscribe saat DB ditutup
/// bikin test HANG tanpa batas). Kategori TIDAK diedit dari alur kasir sama
/// sekali (CRUD-nya di layar Pengaturan -> Kategori Harga, terpisah) — sheet
/// dibuka ulang tiap kali kasir tap keranjang, jadi daftar tetap segar tanpa
/// perlu reaktif live di sini.
final priceCategoriesForToggleProvider =
    FutureProvider.autoDispose<List<PriceCategory>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.getAllPriceCategories();
});

/// Re-price massal saat toggle kategori berubah (dinyalakan/dimatikan/
/// diganti ke kategori lain) — dipanggil dari `cart_sheet.dart` SEBELUM
/// `cartPriceCategoryProvider` state-nya diganti. Aturan (briefing user,
/// urutan PERSIS):
/// - Baris `priceOverridden == true` TIDAK PERNAH disentuh, apa pun kondisinya
///   (manual override selalu menang, baik saat toggle ON/OFF/ganti).
/// - [newCategoryId] terisi & produk baris TERDAFTAR di kategori itu
///   (`PriceService.resolvePrice` balik `source == PriceSource.category`)
///   -> harga+HPP baris diganti ke hasil resolve kategori, `priceFromCategoryId`
///   diisi [newCategoryId].
/// - Selain itu (kategori dimatikan, ATAU produk baris TIDAK terdaftar di
///   kategori baru): baris yang SEBELUMNYA category-priced
///   (`priceFromCategoryId != null`) dikembalikan ke harga NORMAL (resolve
///   ulang TANPA `activeCategoryId` — prioritas customerGroup/qty-tier/base
///   biasa) & `priceFromCategoryId` dilepas ke null. Baris yang memang belum
///   pernah category-priced dibiarkan APA ADANYA (harga normal, tidak
///   berubah sama sekali — tidak ada alasan menyentuhnya).
Future<List<CartItem>> repriceCartForCategoryChange({
  required PriceService priceService,
  required List<CartItem> cart,
  required String? newCategoryId,
}) async {
  final result = <CartItem>[];
  for (final item in cart) {
    if (item.priceOverridden) {
      result.add(item);
      continue;
    }
    if (newCategoryId != null) {
      final resolved = await priceService.resolvePrice(
        productUnitId: item.productUnitId,
        qty: item.qty,
        activeCategoryId: newCategoryId,
      );
      if (resolved.source == PriceSource.category) {
        result.add(item.copyWith(
          price: resolved.price,
          costPrice: resolved.costPrice,
          priceFromCategoryId: newCategoryId,
        ));
        continue;
      }
    }
    // Kategori dimatikan, ATAU baris ini bukan anggota kategori baru.
    if (item.priceFromCategoryId != null) {
      final resolved = await priceService.resolvePrice(
        productUnitId: item.productUnitId,
        qty: item.qty,
      );
      result.add(item.copyWith(
        price: resolved.price,
        costPrice: resolved.costPrice,
        priceFromCategoryId: null,
      ));
    } else {
      result.add(item);
    }
  }
  return result;
}
