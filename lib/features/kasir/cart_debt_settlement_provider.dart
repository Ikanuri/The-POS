import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart' show UnpaidTxEntry;

/// Rencana alokasi FIFO nota lama dari SATU nominal — algoritma PERSIS
/// [AppDatabase.settleMergedDebt] (nota terlama dulu, `sisa <= 0` dilewati,
/// tiap nota dicap `min(remaining, sisa)`), tapi PURE (tanpa DB/tulis apa
/// pun) — dipakai membekukan rencana ke [DebtSettlementEntry.targetInvoices]
/// SAAT entri dibuat (sekarang otomatis lewat toggle di `cart_sheet.dart`,
/// dulu lewat alur pilih pelanggan/nota manual — `debt_settlement_picker.
/// dart`, DIHAPUS total, redesain UX), supaya ringkasan yang kasir lihat
/// konsisten sampai checkout. [invoices] HARUS sudah terurut terlama dulu
/// (lihat `getUnpaidTxDetails`). Kelebihan di atas total sisa TIDAK
/// dialokasikan ke nota manapun di sini — itu jadi kembalian tunai saat
/// `settleMergedDebt` benar-benar dijalankan di checkout (lihat dok
/// `payment_screen.dart`), bukan overpay hutang. Dalam alur toggle otomatis
/// yang baru, [amount] SELALU = total hutang pelanggan sehingga secara
/// praktis tidak ada kelebihan (kecuali race jarang: hutang berubah di
/// antara baca total & baca daftar nota).
List<DebtSettlementTarget> planFifoSettlement(
  List<UnpaidTxEntry> invoices,
  int amount,
) {
  var remaining = amount;
  final out = <DebtSettlementTarget>[];
  for (final inv in invoices) {
    if (remaining <= 0) break;
    if (inv.sisa <= 0) continue;
    final applied = remaining < inv.sisa ? remaining : inv.sisa;
    out.add(DebtSettlementTarget(
      invoiceId: inv.id,
      invoiceLocalId: inv.localId,
      amount: applied,
    ));
    remaining -= applied;
  }
  return out;
}

/// Satu nota LAMA (tempo/kurang_bayar) yang ikut kena alokasi dari SATU
/// [DebtSettlementEntry] — bagian dari rencana FIFO yang dihitung SEKALI saat
/// entri dibuat (lihat `_pickDebtSettlement` di `cart_sheet.dart`). Disimpan
/// beku di sini (bukan dihitung ulang saat checkout) supaya tampilan
/// ringkasan di keranjang & struk konsisten dengan apa yang kasir lihat saat
/// mengonfirmasi nominal — kalaupun sisa nota berubah di antaranya (jarang,
/// single-device), `settleMergedDebt` saat checkout tetap yang menentukan
/// alokasi FINAL sungguhan (nota sudah lunas dilewati otomatis).
@immutable
class DebtSettlementTarget {
  const DebtSettlementTarget({
    required this.invoiceId,
    required this.invoiceLocalId,
    required this.amount,
  });

  final String invoiceId;
  final String invoiceLocalId;
  final int amount;

  Map<String, dynamic> toJson() => {
        'invoiceId': invoiceId,
        'invoiceLocalId': invoiceLocalId,
        'amount': amount,
      };

  factory DebtSettlementTarget.fromJson(Map<String, dynamic> json) =>
      DebtSettlementTarget(
        invoiceId: json['invoiceId'] as String,
        invoiceLocalId: json['invoiceLocalId'] as String,
        amount: (json['amount'] as num).toInt(),
      );
}

/// Fitur "Lunasi Hutang" — REDESAIN TOTAL (permintaan user, alasan: ikon
/// terpisah di footer `cart_sheet.dart` makan ruang & bisa MISCLICK pilih
/// hutang pelanggan LAIN, bukan pelanggan yang sedang diinput di cart bar).
/// SEKARANG murni toggle boolean: satu baris list di dalam keranjang itu
/// SENDIRI (bukan lagi ikon+picker terpisah, lihat `cart_sheet.dart`
/// `_DebtSettlementCartRow`) yang HANYA muncul kalau `CartMeta.customerId`
/// keranjang ini terisi DAN pelanggan itu punya hutang (`cartCustomerDebtProvider`
/// > 0). Tap pertama -> OTOMATIS membuat SATU entri senilai SELURUH hutang
/// pelanggan itu (bukan lagi manual pilih nota+nominal); tap lagi -> entri
/// itu dihapus. Karena itu daftar ini SEKARANG paling banyak berisi SATU
/// entri per cart (dulu bisa akumulatif banyak pelanggan lewat picker manual
/// yang sudah dihapus) — API list tetap dipertahankan (bukan diganti jadi
/// nullable tunggal) supaya format hold/resume JSON (`kasir_screen.dart`)
/// tidak perlu migrasi.
@immutable
class DebtSettlementEntry {
  const DebtSettlementEntry({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.targetInvoices,
    required this.createdAt,
    this.method = 'tunai',
    this.methodName,
  });

  final String id;
  final String customerId;
  final String customerName;
  final int amount;
  final List<DebtSettlementTarget> targetInvoices;
  final DateTime createdAt;

  /// Redesain toggle: TIDAK ADA lagi kalkulator terpisah tempat kasir
  /// memilih metode saat entri ini dibuat (dulu `showDebtPaymentSheet`) —
  /// field ini diisi placeholder 'tunai' saat entri otomatis dibuat
  /// (`_DebtSettlementCartRow` di `cart_sheet.dart`), lalu DITIMPA dengan
  /// metode FINAL yang kasir pilih di layar Bayar (`_selectedMethodType`)
  /// tepat sebelum `saveTransactionWithDebtSettlements` dipanggil (lihat dok
  /// `payment_screen.dart` `_debtSettlementEntries`/pembangunan
  /// `debtSettlements`) — representasi paling masuk akal karena kasir cuma
  /// menerima SATU nominal fisik gabungan (belanja + turut lunas hutang)
  /// dari pelanggan, jadi metodenya logis ikut metode transaksi baru itu
  /// sendiri, bukan dipilih terpisah.
  final String method;

  /// Nama SPESIFIK metode (mis. "GoPay") — null utk Tunai/metode tanpa nama
  /// spesifik. Sama seperti [method], ditimpa saat checkout mengikuti
  /// metode final transaksi baru.
  final String? methodName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'customerId': customerId,
        'customerName': customerName,
        'amount': amount,
        'targetInvoices': targetInvoices.map((t) => t.toJson()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'method': method,
        'methodName': methodName,
      };

  factory DebtSettlementEntry.fromJson(Map<String, dynamic> json) =>
      DebtSettlementEntry(
        id: json['id'] as String,
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String,
        amount: (json['amount'] as num).toInt(),
        targetInvoices: (json['targetInvoices'] as List? ?? const [])
            .map((e) =>
                DebtSettlementTarget.fromJson(e as Map<String, dynamic>))
            .toList(),
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

  /// Total seluruh entri — dipakai `payment_screen.dart` sbg tambahan total
  /// yang perlu diterima kasir dari pelanggan, DI LUAR total belanja baru.
  int get total => state.fold<int>(0, (s, e) => s + e.amount);

  void add(DebtSettlementEntry entry) {
    state = [...state, entry];
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
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
