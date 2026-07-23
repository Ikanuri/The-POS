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
    this.reservedLocalId,
  });

  final String? customerId;
  final String? customerName;
  final String? employeeId;
  final String? employeeName;

  /// Item 55 — nomor nota (`local_id`) di-reserve LEBIH AWAL, sejak
  /// keranjang mulai diisi/ditahan (bukan cuma saat checkout) — supaya
  /// nomor "urutan pelanggan yang harus dilayani" tampil stabil di cart bar
  /// & kartu pesanan tertahan, dan ikut terbawa utuh saat transfer via QR
  /// (Item 56). Diisi lewat `AppDatabase.reserveLocalId`; saat checkout
  /// SUNGGUHAN, dipakai LANGSUNG sbg `local_id` transaksi (bukan generate
  /// baru) — lihat `payment_screen.dart`.
  final String? reservedLocalId;

  bool get isEmpty =>
      customerId == null &&
      customerName == null &&
      employeeId == null &&
      employeeName == null &&
      reservedLocalId == null;

  bool get hasCustomer =>
      (customerName != null && customerName!.isNotEmpty);
  bool get hasEmployee =>
      (employeeName != null && employeeName!.isNotEmpty);

  /// Segmen terakhir `local_id` (mis. "K1-20260723-0017" → "17") untuk
  /// ditampilkan ringkas sbg "#17" — lihat dok `reservedLocalId`.
  String? get displayOrderNumber {
    final id = reservedLocalId;
    if (id == null) return null;
    final seg = id.split('-').last;
    final n = int.tryParse(seg);
    return n == null ? seg : n.toString();
  }

  CartMeta copyWith({
    Object? customerId = _unset,
    Object? customerName = _unset,
    Object? employeeId = _unset,
    Object? employeeName = _unset,
    Object? reservedLocalId = _unset,
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
        reservedLocalId: identical(reservedLocalId, _unset)
            ? this.reservedLocalId
            : reservedLocalId as String?,
      );

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'customerName': customerName,
        'employeeId': employeeId,
        'employeeName': employeeName,
        'reservedLocalId': reservedLocalId,
      };

  factory CartMeta.fromJson(Map<String, dynamic> json) => CartMeta(
        customerId: json['customerId'] as String?,
        customerName: json['customerName'] as String?,
        employeeId: json['employeeId'] as String?,
        employeeName: json['employeeName'] as String?,
        reservedLocalId: json['reservedLocalId'] as String?,
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

  /// Item 55/56 — set nomor nota LANGSUNG (dari transfer QR, bukan hasil
  /// reservasi lokal) — lihat dok `CartMeta.reservedLocalId`.
  void setReservedLocalId(String? id) {
    state = state.copyWith(reservedLocalId: id);
  }

  bool _reserving = false;

  /// Item 55 — reserve nomor nota SEKALI saat keranjang pertama kali terisi
  /// (no-op kalau sudah punya, atau sedang dalam proses reserve — dipanggil
  /// berulang tiap build widget cart bar, guard `_reserving` mencegah
  /// panggilan DB dobel sebelum yang pertama selesai).
  Future<void> ensureReservedLocalId(
      Future<String> Function() reserve) async {
    if (state.reservedLocalId != null || _reserving) return;
    _reserving = true;
    try {
      final id = await reserve();
      if (mounted && state.reservedLocalId == null) {
        state = state.copyWith(reservedLocalId: id);
      }
    } finally {
      _reserving = false;
    }
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
