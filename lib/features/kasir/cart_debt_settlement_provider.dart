import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu entri "Lunasi Hutang" DI KERANJANG — REDESAIN KEDUA (permintaan
/// user, gantikan toggle boolean tunggal dari `a254152`). Sekarang SATU
/// [DebtSettlementEntry] = SATU nota tempo/kurang_bayar SUMBER yang dipilih
/// kasir lewat sheet "Pilih Nota untuk Dilunasi" (lihat
/// `showDebtSettlementSheet` di `widgets/debt_settlement_sheet.dart`) — BUKAN
/// lagi satu entri agregat FIFO dari SELURUH hutang pelanggan. Kasir bisa
/// mencentang sebagian nota saja (partial per-nota, uncentang 1 dari N nota),
/// jadi daftar entri di [cartDebtSettlementProvider] SEKARANG BISA berisi
/// banyak entri sekaligus (dulu dibatasi maks 1 sejak `a254152`) — tiap
/// nota tercentang = satu entri terpisah, ditampilkan sbg baris terpisah di
/// keranjang (`_DebtSettlementEntryRow`, `cart_sheet.dart`).
///
/// [amount] SELALU = sisa hutang nota [invoiceId] itu SAAT dicentang (bukan
/// manual/parsial dari satu nota — user TIDAK diberi kalkulator, cuma
/// centang/uncentang per-nota di sheet). `saveTransactionWithDebtSettlements`
/// (backend, TIDAK berubah logikanya) tetap menerima grup
/// {customerName, amount, targets: [...] , method, methodName} — di sini
/// tiap entri dipetakan jadi SATU grup dgn SATU target (dirinya sendiri),
/// lihat `payment_screen.dart` `_debtSettlementEntries` mapping (TIDAK
/// perlu diubah — sudah generik menerima banyak target per grup, sekarang
/// kebetulan selalu 1).
@immutable
class DebtSettlementEntry {
  const DebtSettlementEntry({
    required this.id,
    required this.invoiceId,
    required this.invoiceLocalId,
    required this.invoiceDate,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.createdAt,
    this.method = 'tunai',
    this.methodName,
  });

  final String id;

  /// Nota SUMBER (tempo/kurang_bayar lama) yang dilunasi entri ini — BUKAN
  /// lagi agregat seluruh hutang pelanggan (beda dari desain `a254152`).
  final String invoiceId;
  final String invoiceLocalId;

  /// Tanggal nota sumber — dipakai baris ke-2 tampilan keranjang & struk
  /// (lihat dok `CLAUDE.md` §7.6, ditambahkan redesain ini krn struk lama
  /// belum menyimpan tanggal nota per-entri).
  final DateTime invoiceDate;

  final String customerId;
  final String customerName;

  /// Sisa hutang nota [invoiceId] SAAT dicentang di sheet pemilihan nota.
  final int amount;
  final DateTime createdAt;

  /// TIDAK ADA kalkulator metode terpisah saat entri ini dibuat (sheet
  /// pemilihan nota cuma checklist) — field ini diisi placeholder 'tunai',
  /// lalu DITIMPA dengan metode FINAL yang kasir pilih di layar Bayar tepat
  /// sebelum `saveTransactionWithDebtSettlements` dipanggil (lihat dok
  /// `payment_screen.dart` `_debtSettlementEntries`/pembangunan
  /// `debtSettlements`) — TIDAK diubah dari desain sebelumnya.
  final String method;

  /// Nama SPESIFIK metode (mis. "GoPay") — null utk Tunai/metode tanpa nama
  /// spesifik. Sama seperti [method], ditimpa saat checkout mengikuti
  /// metode final transaksi baru.
  final String? methodName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoiceId': invoiceId,
        'invoiceLocalId': invoiceLocalId,
        'invoiceDate': invoiceDate.millisecondsSinceEpoch,
        'customerId': customerId,
        'customerName': customerName,
        'amount': amount,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'method': method,
        'methodName': methodName,
      };

  factory DebtSettlementEntry.fromJson(Map<String, dynamic> json) =>
      DebtSettlementEntry(
        id: json['id'] as String,
        invoiceId: json['invoiceId'] as String,
        invoiceLocalId: json['invoiceLocalId'] as String,
        invoiceDate: DateTime.fromMillisecondsSinceEpoch(
            json['invoiceDate'] as int? ??
                json['createdAt'] as int? ??
                DateTime.now().millisecondsSinceEpoch),
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String,
        amount: (json['amount'] as num).toInt(),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        method: json['method'] as String? ?? 'tunai',
        methodName: json['methodName'] as String?,
      );
}

class CartDebtSettlementNotifier
    extends StateNotifier<List<DebtSettlementEntry>> {
  CartDebtSettlementNotifier(this.cartId) : super(const []) {
    _load();
  }

  /// Penanda slot keranjang — sama persis `cartProvider`/`cartPrabayarProvider`.
  final String cartId;

  static const _prefPrefix = 'cartdebtsettle_v1_';
  String get _prefKey => '$_prefPrefix$cartId';
  bool _loaded = false;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (state.isEmpty) {
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            super.state = decoded
                .map((e) =>
                    DebtSettlementEntry.fromJson(e as Map<String, dynamic>))
                .toList();
          }
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
  set state(List<DebtSettlementEntry> value) {
    super.state = value;
    if (_loaded) _persist();
  }

  /// Total seluruh entri — dipakai `payment_screen.dart`/`cart_sheet.dart`
  /// sbg tambahan total yang perlu diterima kasir dari pelanggan, DI LUAR
  /// total belanja baru.
  int get total => state.fold<int>(0, (s, e) => s + e.amount);

  void add(DebtSettlementEntry entry) {
    state = [...state, entry];
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
  }

  /// Hapus entri utk nota [invoiceId] (kalau ada) — dipakai sheet pemilihan
  /// nota saat kasir uncentang satu nota.
  void removeByInvoice(String invoiceId) {
    state = state.where((e) => e.invoiceId != invoiceId).toList();
  }

  /// Ganti seluruh isi (dipakai saat melanjutkan pesanan ditahan) — sejalan
  /// dgn `CartPrabayarNotifier.replaceAll`.
  void replaceAll(List<DebtSettlementEntry> entries) {
    state = entries;
  }

  void clear() {
    state = const [];
  }

  /// Bersihkan entri yatim — sejalan dgn
  /// `CartPrabayarNotifier.cleanupOrphanPrabayar`.
  static Future<void> cleanupOrphanDebtSettlements() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_prefPrefix)) continue;
      final cartId = key.substring(_prefPrefix.length);
      if (!prefs.containsKey('cart_v1_$cartId')) {
        await prefs.remove(key);
      }
    }
  }
}

/// Entri "Lunasi Hutang" per-slot keranjang. Sejalan dengan [cartProvider]/
/// `cartPrabayarProvider`.
final cartDebtSettlementProvider = StateNotifierProvider.family<
    CartDebtSettlementNotifier, List<DebtSettlementEntry>, String>(
  (ref, cartId) => CartDebtSettlementNotifier(cartId),
);
