import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/cart_item.dart';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addItem(CartItem item) {
    final idx = state.indexWhere(
        (c) => c.productUnitId == item.productUnitId && !c.priceOverridden);
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

  void removeItem(String productUnitId) {
    state = state.where((c) => c.productUnitId != productUnitId).toList();
  }

  void removeItemByIndex(int index) {
    final s = [...state];
    s.removeAt(index);
    state = s;
  }

  void overridePrice(int index, int newPrice) {
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index)
          state[i].copyWith(price: newPrice, priceOverridden: true)
        else
          state[i],
    ];
  }

  void setNote(int index, String? note) {
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index) state[i].copyWith(itemNote: note) else state[i],
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

  int get totalAmount =>
      state.fold(0, (sum, item) => sum + item.subtotal);

  int get itemCount => state.fold(0, (sum, item) => sum + item.qty.ceil());
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);

/// Nama pelanggan yang di-prefill di layar pembayaran
/// (di-set oleh aksi "Tambah Item" pada riwayat transaksi).
final prefillCustomerProvider = StateProvider<String?>((ref) => null);

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
