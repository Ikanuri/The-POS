import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/cart_item.dart';

/// Cart ID keranjang utama kasir. Keranjang "tambah belanjaan" memakai id
/// transaksi sehingga terpisah total dari keranjang utama.
const kMainCartId = 'main';

/// Cart ID khusus mode katalog — keranjang terpisah agar pesanan utama kasir
/// tetap aman saat membuat katalog (lihat KasirScreen.catalogMode).
const kCatalogCartId = 'catalog';

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier(this.cartId) : super([]) {
    _load();
  }

  /// Penanda slot keranjang. 'main' = kasir biasa; selain itu = id transaksi
  /// untuk fitur tambah belanjaan.
  final String cartId;

  static const _prefPrefix = 'cart_v1_';
  String get _prefKey => '$_prefPrefix$cartId';

  bool _loaded = false;

  /// productUnitId item terakhir yang ditambahkan/disentuh — dipakai cart bar
  /// untuk menampilkan ringkasan "produk terakhir". Tidak dipersistensi
  /// terpisah; diturunkan dari item terakhir saat load/replace.
  String? lastTouchedUnitId;

  /// Item yang paling baru disentuh (atau null bila keranjang kosong / item
  /// sudah dihapus). Lewati induk placeholder (effective qty 0 dengan varian).
  CartItem? get lastTouchedItem {
    if (lastTouchedUnitId == null) return null;
    for (final c in state) {
      if (c.productUnitId == lastTouchedUnitId) return c;
    }
    return null;
  }

  /// Muat keranjang dari penyimpanan lokal (survive app kill / restart).
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Jangan timpa bila pengguna sudah berinteraksi sebelum load selesai.
    if (state.isEmpty) {
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = (jsonDecode(raw) as List)
              .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
              .toList();
          super.state = list;
          if (list.isNotEmpty) lastTouchedUnitId = list.last.productUnitId;
        } catch (_) {/* abaikan data rusak */}
      }
    }
    _loaded = true;
    // Catat waktu akses terakhir untuk pembersihan keranjang yatim.
    await prefs.setInt('${_prefKey}_ts', DateTime.now().millisecondsSinceEpoch);
  }

  void _persist() {
    final snapshot = state;
    SharedPreferences.getInstance().then((prefs) {
      if (snapshot.isEmpty) {
        prefs.remove(_prefKey);
        prefs.remove('${_prefKey}_ts');
      } else {
        prefs.setString(
            _prefKey, jsonEncode(snapshot.map((c) => c.toJson()).toList()));
        prefs.setInt(
            '${_prefKey}_ts', DateTime.now().millisecondsSinceEpoch);
      }
    });
  }

  @override
  set state(List<CartItem> value) {
    super.state = value;
    if (_loaded) _persist();
  }

  /// Bersihkan keranjang "tambah belanjaan" yatim (>24 jam, bukan keranjang
  /// utama) yang tidak pernah diselesaikan. Dipanggil sekali saat app init.
  static Future<void> cleanupOrphanCarts() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    const maxAge = 24 * 60 * 60 * 1000;
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_prefPrefix) || key.endsWith('_ts')) continue;
      if (key == '$_prefPrefix$kMainCartId') continue; // jangan hapus utama
      // Draft katalog bukan keranjang yatim — biarkan bertahan > 24 jam.
      if (key == '$_prefPrefix$kCatalogCartId') continue;
      final ts = prefs.getInt('${key}_ts') ?? 0;
      if (now - ts > maxAge) {
        await prefs.remove(key);
        await prefs.remove('${key}_ts');
      }
    }
  }

  void addItem(CartItem item) {
    // Catat sebagai item terakhir disentuh untuk ringkasan cart bar. Induk
    // placeholder (qty 0) tetap dicatat lalu segera ditimpa oleh add varian
    // yang menyusul, sehingga hasil akhirnya item nyata.
    lastTouchedUnitId = item.productUnitId;
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
    // Saat menambah varian (baru maupun akumulasi), naikkan storedQty induk
    // sebesar qty yang ditambahkan. Ini menjaga invariant
    //   storedQty induk = effectiveBase + Σ(qty varian)
    // sehingga qty dasar induk tidak "tertelan" saat varian ditambah —
    // campur qty dasar + varian tetap akurat. Induk wajib sudah ada di cart
    // (dipasang lebih dulu oleh _ensureParentInCart sebagai placeholder qty 0).
    if (item.isVariant && item.parentProductId != null) {
      final pIdx = state.indexWhere(
          (c) => !c.isVariant && c.productId == item.parentProductId);
      if (pIdx >= 0) {
        state = [
          for (var i = 0; i < state.length; i++)
            if (i == pIdx)
              state[i].copyWith(qty: state[i].qty + item.qty)
            else
              state[i],
        ];
      }
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
    lastTouchedUnitId = productUnitId;
    final item = state[idx];
    if (item.isVariant) {
      _setVariantQty(item, effectiveQty);
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

  /// Ubah qty sebuah varian ke [newQty] sambil mempertahankan qty dasar
  /// (effective base) induknya. Selisihnya diteruskan ke storedQty induk
  /// agar invariant storedQty = base + Σvarian tetap utuh. Bila newQty <= 0,
  /// varian dihapus (dan induk ikut disesuaikan via [removeItem]).
  void _setVariantQty(CartItem variant, double newQty) {
    if (newQty <= 0) {
      removeItem(variant.productUnitId);
      return;
    }
    final delta = newQty - variant.qty;
    state = [
      for (final c in state)
        if (c.productUnitId == variant.productUnitId)
          c.copyWith(qty: newQty)
        else if (!c.isVariant && c.productId == variant.parentProductId)
          c.copyWith(qty: (c.qty + delta).clamp(0.0, double.infinity))
        else
          c,
    ];
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
    // Bila yang dihapus adalah varian, perbarui storedQty induk agar konsisten.
    CartItem? removed;
    for (final c in state) {
      if (c.productUnitId == productUnitId) {
        removed = c;
        break;
      }
    }
    if (removed != null && removed.isVariant && removed.parentProductId != null) {
      CartItem? parent;
      for (final c in state) {
        if (!c.isVariant && c.productId == removed.parentProductId) {
          parent = c;
          break;
        }
      }
      if (parent != null) {
        // Sisa varian lain yang masih ada (selain yang dihapus).
        final remainingVariantTotal = state
            .where((c) =>
                c.isVariant &&
                c.parentProductId == removed!.parentProductId &&
                c.productUnitId != productUnitId)
            .fold(0.0, (s, c) => s + c.qty);
        // Effective qty induk = storedQty - Σ(semua varian saat ini).
        final allVariantTotal = state
            .where((c) =>
                c.isVariant && c.parentProductId == removed!.parentProductId)
            .fold(0.0, (s, c) => s + c.qty);
        final parentEffective =
            (parent.qty - allVariantTotal).clamp(0.0, double.infinity);
        final newParentStored = parentEffective + remainingVariantTotal;
        if (newParentStored <= 0) {
          // Tidak ada base qty dan tidak ada varian lain → hapus induk juga.
          state = state
              .where((c) =>
                  c.productUnitId != productUnitId &&
                  c.productUnitId != parent!.productUnitId)
              .toList();
          return;
        }
        state = state
            .where((c) => c.productUnitId != productUnitId)
            .map((c) => c.productUnitId == parent!.productUnitId
                ? c.copyWith(qty: newParentStored)
                : c)
            .toList();
        return;
      }
    }
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
    lastTouchedUnitId = item.productUnitId;
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

  void clear() {
    lastTouchedUnitId = null;
    state = [];
  }

  /// Ganti seluruh isi keranjang (dipakai saat melanjutkan pesanan ditahan).
  void replaceAll(List<CartItem> items) {
    lastTouchedUnitId = items.isNotEmpty ? items.last.productUnitId : null;
    state = items;
  }

  int get totalAmount => state.fold(0, (sum, item) {
    final effQty = effectiveQtyFor(item);
    return sum + (item.price * effQty).round();
  });

  int get itemCount => state.fold(0, (sum, item) {
    return sum + effectiveQtyFor(item).ceil();
  });
}

/// Keranjang per-slot. `cartProvider(kMainCartId)` = kasir biasa;
/// `cartProvider(txId)` = keranjang tambah belanjaan untuk transaksi itu.
final cartProvider =
    StateNotifierProvider.family<CartNotifier, List<CartItem>, String>(
  (ref, cartId) => CartNotifier(cartId),
);

/// Total belanja dari daftar item lepas (di luar notifier) dengan invariant
/// induk-varian: storedQty induk = base + Σ(varian), jadi qty efektif induk
/// harus dikurangi total varian agar varian tidak terhitung dua kali.
/// Dipakai mis. kartu pesanan ditahan.
int cartTotalOf(List<CartItem> items) {
  var sum = 0;
  for (final it in items) {
    final double eff;
    if (it.isVariant) {
      eff = it.qty;
    } else {
      final variantTotal = items
          .where((c) => c.isVariant && c.parentProductId == it.productId)
          .fold(0.0, (s, c) => s + c.qty);
      eff = (it.qty - variantTotal).clamp(0.0, double.infinity);
    }
    sum += (it.price * eff).round();
  }
  return sum;
}

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
