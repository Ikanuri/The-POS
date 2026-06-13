import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/cart_item.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addItem(CartItem item) {
    final idx = state.indexWhere(
        (c) => c.productUnitId == item.productUnitId);
    if (idx >= 0) {
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx)
            state[i].copyWith(qty: state[i].qty + item.qty)
          else
            state[i],
      ];
    } else {
      state = [...state, item];
    }
  }

  void setQty(String productUnitId, double qty) {
    if (qty <= 0) {
      removeItem(productUnitId);
      return;
    }
    state = [
      for (final c in state)
        if (c.productUnitId == productUnitId) c.copyWith(qty: qty) else c,
    ];
  }

  /// Ubah effective qty sebuah item.
  /// Untuk item induk: stored qty = effectiveQty + totalVariantQty.
  /// Saat effectiveQty = 0 dan ada varian, induk tetap di cart sebagai placeholder.
  void setEffectiveQty(String productUnitId, double effectiveQty) {
    final idx = state.indexWhere((c) => c.productUnitId == productUnitId);
    if (idx < 0) return;
    final item = state[idx];
    if (item.isVariant) {
      setQty(productUnitId, effectiveQty);
      return;
    }
    final variantTotal = state
        .where((c) => c.isVariant && c.parentProductId == item.productId)
        .fold(0.0, (s, c) => s + c.qty);
    final newStored = effectiveQty + variantTotal;
    if (newStored <= 0) {
      removeItem(productUnitId);
    } else {
      setQty(productUnitId, newStored);
    }
  }

  /// Effective qty untuk sebuah item.
  /// Induk: storedQty − totalVariantQty (min 0). Varian: storedQty.
  double effectiveQtyFor(CartItem item) {
    if (item.isVariant) return item.qty;
    final variantTotal = state
        .where((c) => c.isVariant && c.parentProductId == item.productId)
        .fold(0.0, (s, c) => s + c.qty);
    return (item.qty - variantTotal).clamp(0.0, double.infinity);
  }

  void removeItem(String productUnitId) {
    state = state.where((c) => c.productUnitId != productUnitId).toList();
  }

  void removeItemByIndex(int index) {
    final s = [...state];
    s.removeAt(index);
    state = s;
  }

  void overridePrice(String productUnitId, int newPrice) {
    state = [
      for (final c in state)
        if (c.productUnitId == productUnitId)
          c.copyWith(price: newPrice, priceOverridden: true)
        else
          c,
    ];
  }

  void setNote(String productUnitId, String? note) {
    state = [
      for (final c in state)
        if (c.productUnitId == productUnitId) c.copyWith(itemNote: note) else c,
    ];
  }

  /// Set / ganti item berdasarkan productUnitId (dipakai modal edit item).
  /// Berbeda dari [addItem] yang menambah qty; ini menimpa.
  void setItem(CartItem item) {
    final idx = state.indexWhere((c) => c.productUnitId == item.productUnitId);
    if (item.qty <= 0) {
      if (idx >= 0) removeItem(item.productUnitId);
      return;
    }
    if (idx >= 0) {
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx) item else state[i],
      ];
    } else {
      state = [...state, item];
    }
  }

  /// Total qty semua satuan milik satu produk (untuk badge counter di katalog).
  double qtyForProduct(String productId) => state
      .where((c) => c.productId == productId)
      .fold(0.0, (s, c) => s + c.qty);

  /// Qty untuk satu satuan tertentu.
  double qtyForUnit(String productUnitId) => state
      .where((c) => c.productUnitId == productUnitId)
      .fold(0.0, (s, c) => s + c.qty);

  void clear() => state = [];

  /// Ganti seluruh isi keranjang (dipakai saat melanjutkan pesanan ditahan).
  void replaceAll(List<CartItem> items) => state = items;

  int get totalAmount => state.fold(0, (sum, item) {
    final effQty = effectiveQtyFor(item);
    return sum + (item.price * effQty).round();
  });

  int get itemCount => state.fold(0, (sum, item) {
    return sum + effectiveQtyFor(item).ceil();
  });
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);

/// Susun keranjang: induk diikuti varian-variannya (tampilan bersarang).
List<CartItem> orderCartItems(List<CartItem> cart) {
  final out = <CartItem>[];
  for (final it in cart) {
    if (!it.isVariant) {
      out.add(it);
      for (final c in cart) {
        if (c.isVariant && c.parentProductId == it.productId) out.add(c);
      }
    }
  }
  for (final it in cart) {
    if (it.isVariant && !out.contains(it)) out.add(it);
  }
  return out;
}

/// Pilihan tampilan katalog kasir (grid/list) yang disimpan ke prefs
/// sehingga tidak ter-reset saat aplikasi dibuka ulang.
class KasirGridNotifier extends StateNotifier<bool> {
  KasirGridNotifier() : super(true) {
    _load();
  }

  static const _prefKey = 'kasir_grid_view';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_prefKey) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, state);
  }
}

final kasirGridProvider =
    StateNotifierProvider<KasirGridNotifier, bool>((ref) => KasirGridNotifier());
