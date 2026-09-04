import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cart_provider.dart';

/// Fitur "Pra-Bayar" — kasir mengunci sebagian pembayaran dari keranjang
/// AKTIF (SEBELUM checkout beneran), sambil keranjang tetap 100% bisa diedit
/// bebas. Tiap kunci = satu [PrabayarEntry] (akumulatif, metode independen
/// per entri). Total terkunci vs total keranjang dihitung LIVE di UI (lihat
/// `cart_sheet.dart`) — provider ini murni menyimpan daftar entri per
/// `cartId`, tidak tahu apa-apa soal total keranjang.
///
/// Saat checkout BENERAN (`payment_screen.dart`), tiap entri jadi SATU baris
/// `TransactionPayments` dengan `paidAt` = [lockedAt] ENTRI ASLI (bukan waktu
/// checkout) — supaya jejak waktu kuncinya akurat.
@immutable
class PrabayarEntry {
  const PrabayarEntry({
    required this.id,
    required this.amount,
    required this.method,
    this.methodName,
    required this.lockedAt,
  });

  final String id;
  final int amount;

  /// `PaymentMethod.type` (mis. 'tunai', 'qris', 'transfer') — konsisten
  /// dengan cara `TransactionPayments.method` menyimpan metode di alur
  /// checkout/tambah-bayar yang sudah ada.
  final String method;

  /// Nama SPESIFIK metode (mis. "GoPay") — null untuk Tunai/metode tanpa
  /// nama spesifik. Lihat dok `showDebtPaymentSheet`.
  final String? methodName;

  /// Waktu kunci ASLI — dipertahankan apa adanya sampai checkout, jadi
  /// `TransactionPayments.paidAt` baris yang dihasilkan dari entri ini.
  final DateTime lockedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'method': method,
        'methodName': methodName,
        'lockedAt': lockedAt.millisecondsSinceEpoch,
      };

  factory PrabayarEntry.fromJson(Map<String, dynamic> json) => PrabayarEntry(
        id: json['id'] as String,
        amount: json['amount'] as int,
        method: json['method'] as String,
        methodName: json['methodName'] as String?,
        lockedAt:
            DateTime.fromMillisecondsSinceEpoch(json['lockedAt'] as int),
      );
}

class CartPrabayarNotifier extends StateNotifier<List<PrabayarEntry>> {
  CartPrabayarNotifier(this.cartId) : super(const []) {
    _load();
  }

  /// Penanda slot keranjang — SAMA persis dgn `cartProvider`/`cartMetaProvider`
  /// (`kMainCartId` untuk kasir biasa, atau id transaksi utk tambah
  /// belanjaan — walau fitur ini TIDAK dipakai di mode tambah belanjaan,
  /// lihat dok `payment_screen.dart`).
  final String cartId;

  static const _prefPrefix = 'cartprabayar_v1_';
  String get _prefKey => '$_prefPrefix$cartId';
  bool _loaded = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (state.isEmpty) {
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = (jsonDecode(raw) as List)
              .map((e) => PrabayarEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          super.state = list;
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
        prefs.setString(
            _prefKey, jsonEncode(snapshot.map((e) => e.toJson()).toList()));
      }
    });
  }

  @override
  set state(List<PrabayarEntry> value) {
    super.state = value;
    if (_loaded) _persist();
  }

  /// Total seluruh entri terkunci — dipakai `payment_screen.dart` sbg
  /// `lockedSum`.
  int get totalLocked => state.fold<int>(0, (s, e) => s + e.amount);

  void add(PrabayarEntry entry) {
    state = [...state, entry];
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
  }

  /// Ganti seluruh isi (dipakai saat melanjutkan pesanan ditahan / adopsi
  /// transfer QR).
  void replaceAll(List<PrabayarEntry> entries) {
    state = entries;
  }

  void clear() {
    state = const [];
  }

  /// Bersihkan entri Pra-Bayar yatim — sejalan dengan
  /// [CartNotifier.cleanupOrphanCarts]/`CartMetaNotifier.cleanupOrphanMeta`.
  static Future<void> cleanupOrphanPrabayar() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_prefPrefix)) continue;
      if (key == '$_prefPrefix$kMainCartId') continue;
      final cartId = key.substring(_prefPrefix.length);
      if (!prefs.containsKey('cart_v1_$cartId')) {
        await prefs.remove(key);
      }
    }
  }
}

/// Entri Pra-Bayar per-slot keranjang. Sejalan dengan [cartProvider]/
/// `cartMetaProvider`.
final cartPrabayarProvider = StateNotifierProvider.family<
    CartPrabayarNotifier, List<PrabayarEntry>, String>(
  (ref, cartId) => CartPrabayarNotifier(cartId),
);
