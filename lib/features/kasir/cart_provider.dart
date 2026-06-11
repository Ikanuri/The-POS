import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  void clear() => state = [];

  int get totalAmount =>
      state.fold(0, (sum, item) => sum + item.subtotal);

  int get itemCount => state.fold(0, (sum, item) => sum + item.qty.ceil());
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);
