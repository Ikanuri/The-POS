import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cart_provider.dart';

/// Metadata keranjang per-slot: pelanggan & pegawai yang melekat pada pesanan
/// yang sedang berlangsung. Dipisah dari daftar item agar tidak memaksa
/// refactor besar pada `cartProvider` (yang tetap `List<CartItem>`).
@immutable
class CartMeta {
  const CartMeta({
    this.customerId,
    this.customerName,
    this.employeeId,
    this.employeeName,
  });

  final String? customerId;
  final String? customerName;
  final String? employeeId;
  final String? employeeName;

  bool get isEmpty =>
      customerId == null &&
      customerName == null &&
      employeeId == null &&
      employeeName == null;

  bool get hasCustomer =>
      (customerName != null && customerName!.isNotEmpty);
  bool get hasEmployee =>
      (employeeName != null && employeeName!.isNotEmpty);

  CartMeta copyWith({
    Object? customerId = _unset,
    Object? customerName = _unset,
    Object? employeeId = _unset,
    Object? employeeName = _unset,
  }) =>
      CartMeta(
        customerId: identical(customerId, _unset)
            ? this.customerId
            : customerId as String?,
        customerName: identical(customerName, _unset)
            ? this.customerName
            : customerName as String?,
        employeeId: identical(employeeId, _unset)
            ? this.employeeId
            : employeeId as String?,
        employeeName: identical(employeeName, _unset)
            ? this.employeeName
            : employeeName as String?,
      );

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'customerName': customerName,
        'employeeId': employeeId,
        'employeeName': employeeName,
      };

  factory CartMeta.fromJson(Map<String, dynamic> json) => CartMeta(
        customerId: json['customerId'] as String?,
        customerName: json['customerName'] as String?,
        employeeId: json['employeeId'] as String?,
        employeeName: json['employeeName'] as String?,
      );
}

class CartMetaNotifier extends StateNotifier<CartMeta> {
  CartMetaNotifier(this.cartId) : super(const CartMeta()) {
    _load();
  }

  final String cartId;

  static const _prefPrefix = 'cartmeta_v1_';
  String get _prefKey => '$_prefPrefix$cartId';
  bool _loaded = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (state.isEmpty) {
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          super.state =
              CartMeta.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        } catch (_) {/* abaikan data rusak */}
      }
    }
    _loaded = true;
  }

  void _persist() {
    final snapshot = state;
    SharedPreferences.getInstance().then((prefs) {
      if (snapshot.isEmpty) {
        prefs.remove(_prefKey);
      } else {
        prefs.setString(_prefKey, jsonEncode(snapshot.toJson()));
      }
    });
  }

  @override
  set state(CartMeta value) {
    super.state = value;
    if (_loaded) _persist();
  }

  void setCustomer(String? id, String? name) {
    state = state.copyWith(customerId: id, customerName: name);
  }

  void clearCustomer() {
    state = state.copyWith(customerId: null, customerName: null);
  }

  void setEmployee(String? id, String? name) {
    state = state.copyWith(employeeId: id, employeeName: name);
  }

  void clearEmployee() {
    state = state.copyWith(employeeId: null, employeeName: null);
  }

  void replaceAll(CartMeta meta) {
    state = meta;
  }

  void clear() {
    state = const CartMeta();
  }

  /// Bersihkan metadata keranjang "tambah belanjaan" yatim (>24 jam) — selaras
  /// dengan pembersihan keranjang di [CartNotifier.cleanupOrphanCarts].
  static Future<void> cleanupOrphanMeta() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_prefPrefix)) continue;
      if (key == '$_prefPrefix$kMainCartId') continue;
      // Hapus meta bila keranjang pasangannya sudah tidak ada (sudah dibersihkan
      // oleh cleanupOrphanCarts yang berjalan lebih dulu).
      final cartId = key.substring(_prefPrefix.length);
      if (!prefs.containsKey('cart_v1_$cartId')) {
        await prefs.remove(key);
      }
    }
  }
}

/// Metadata keranjang per-slot. Sejalan dengan [cartProvider].
final cartMetaProvider =
    StateNotifierProvider.family<CartMetaNotifier, CartMeta, String>(
  (ref, cartId) => CartMetaNotifier(cartId),
);
