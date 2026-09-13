import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fitur "Pelunasi Pre-order" DI KERANJANG — arsitektur IDENTIK dgn
/// `CartDebtSettlementNotifier`/[DebtSettlementEntry] (`cart_debt_settlement_
/// provider.dart`, baca dok di sana dulu), cuma sumbernya beda: bukan nota
/// tempo/kurang_bayar, tapi SATU entri `PreorderEntries` (DP/jaminan yang
/// dikunci Rp 0 saat checkout, `getPreorderDepositOwed`) yang dipilih kasir
/// lewat sheet "Pilih Pre-order untuk Dilunasi"
/// (`preorder_settlement_sheet.dart`). Satu [PreorderSettlementEntry] = satu
/// baris nota pre-order sumber — TIDAK menduplikasi produk pre-order itu ke
/// daftar item keranjang, murni baris pelunasan tambahan (pola sama persis
/// hutang: uangnya masuk ke nota LAMA lewat `collectPreorderDeposit`, BUKAN
/// jadi omzet nota BARU — lihat dok `AppDatabase.saveTransactionWithDebtSettlements`
/// param `preorderSettlements`).
///
/// Beda dari hutang: tidak ada "satu nota, banyak nominal" — tiap pre-order
/// SATU produk spesifik dgn SATU DP, jadi [productName] disimpan supaya baris
/// keranjang bisa menunjukkan pre-order produk APA yang sedang dilunasi
/// (hutang tidak perlu ini, "Nota X" sudah cukup jelas).
@immutable
class PreorderSettlementEntry {
  const PreorderSettlementEntry({
    required this.id,
    required this.preorderEntryId,
    required this.invoiceId,
    required this.invoiceLocalId,
    required this.invoiceDate,
    required this.customerId,
    required this.customerName,
    required this.productName,
    required this.amount,
    required this.createdAt,
    this.method = 'tunai',
    this.methodName,
    this.fulfillOnSettle = false,
  });

  final String id;

  /// Baris `PreorderEntries` sumber — dipakai `collectPreorderDeposit` saat
  /// checkout (lihat dok param `preorderSettlements`).
  final String preorderEntryId;

  /// Nota SUMBER (nota yang menyimpan baris item pre-order Rp 0 ini) —
  /// dipakai hyperlink "tap ke nota asal" di struk, pola sama
  /// `DebtSettlementEntry.invoiceId`.
  final String invoiceId;
  final String invoiceLocalId;
  final DateTime invoiceDate;

  final String customerId;
  final String customerName;

  /// Nama produk pre-order (mis. "Galon Aqua") — dipakai baris keranjang
  /// supaya kasir tahu pre-order APA yang sedang dilunasi (beda dari
  /// hutang, yang cukup "Nota X" tanpa perlu nama produk).
  final String productName;

  /// DP/jaminan yang MASIH terhutang, DIBEKUKAN saat dicentang di sheet
  /// (`getPreorderDepositOwed` SAAT itu) — sama pola dgn
  /// `DebtSettlementEntry.amount`.
  final int amount;
  final DateTime createdAt;

  /// TIDAK ADA kalkulator metode terpisah saat entri ini dibuat — placeholder
  /// 'tunai', DITIMPA metode FINAL kasir di layar Bayar sebelum
  /// `saveTransactionWithDebtSettlements` dipanggil (lihat dok
  /// `payment_screen.dart` `_preorderSettlementEntries`) — pola sama persis
  /// `DebtSettlementEntry.method`.
  final String method;
  final String? methodName;

  /// Item 66 (susulan, opsional — permintaan user) — kalau true, SELAIN
  /// mengumpulkan DP via `collectPreorderDeposit`, checkout JUGA langsung
  /// memenuhi (`fulfillPreorderEntry`, qty PENUH — bukan partial, keputusan
  /// "paling simpel & aman") pre-order ini dalam transaksi atomik yang
  /// sama. Default false — pelunasan TANPA fulfill tetap jalur utama;
  /// toggle ini per-baris di sheet "Pilih Pre-order untuk Dilunasi", TIDAK
  /// menyentuh alur dashboard Laci Meja/tombol "Penuhi" struk (#18) sama
  /// sekali.
  final bool fulfillOnSettle;

  Map<String, dynamic> toJson() => {
        'id': id,
        'preorderEntryId': preorderEntryId,
        'invoiceId': invoiceId,
        'invoiceLocalId': invoiceLocalId,
        'invoiceDate': invoiceDate.millisecondsSinceEpoch,
        'customerId': customerId,
        'customerName': customerName,
        'productName': productName,
        'amount': amount,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'method': method,
        'methodName': methodName,
        'fulfillOnSettle': fulfillOnSettle,
      };

  factory PreorderSettlementEntry.fromJson(Map<String, dynamic> json) =>
      PreorderSettlementEntry(
        id: json['id'] as String,
        preorderEntryId: json['preorderEntryId'] as String,
        invoiceId: json['invoiceId'] as String,
        invoiceLocalId: json['invoiceLocalId'] as String,
        invoiceDate: DateTime.fromMillisecondsSinceEpoch(
            json['invoiceDate'] as int? ??
                json['createdAt'] as int? ??
                DateTime.now().millisecondsSinceEpoch),
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String,
        productName: json['productName'] as String? ?? '',
        amount: (json['amount'] as num).toInt(),
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        method: json['method'] as String? ?? 'tunai',
        methodName: json['methodName'] as String?,
        fulfillOnSettle: json['fulfillOnSettle'] as bool? ?? false,
      );
}

class CartPreorderSettlementNotifier
    extends StateNotifier<List<PreorderSettlementEntry>> {
  CartPreorderSettlementNotifier(this.cartId) : super(const []) {
    _load();
  }

  /// Penanda slot keranjang — sama persis `cartProvider`/
  /// `cartDebtSettlementProvider`.
  final String cartId;

  static const _prefPrefix = 'cartpreordersettle_v1_';
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
                .map((e) => PreorderSettlementEntry.fromJson(
                    e as Map<String, dynamic>))
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
  set state(List<PreorderSettlementEntry> value) {
    super.state = value;
    if (_loaded) _persist();
  }

  /// Total seluruh entri — dipakai `payment_screen.dart`/`cart_sheet.dart`
  /// sbg tambahan total yang perlu diterima kasir dari pelanggan, DI LUAR
  /// total belanja baru.
  int get total => state.fold<int>(0, (s, e) => s + e.amount);

  void add(PreorderSettlementEntry entry) {
    state = [...state, entry];
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
  }

  /// Hapus entri utk pre-order [preorderEntryId] (kalau ada) — dipakai sheet
  /// pemilihan pre-order saat kasir uncentang satu baris.
  void removeByPreorderEntry(String preorderEntryId) {
    state = state.where((e) => e.preorderEntryId != preorderEntryId).toList();
  }

  /// Item 66 — ubah toggle "Sekaligus penuhi" utk entri [id] yang SUDAH ada
  /// di keranjang (dipanggil dari sheet saat kasir tap toggle per-baris).
  void setFulfillOnSettle(String id, bool value) {
    state = [
      for (final e in state)
        if (e.id == id)
          PreorderSettlementEntry(
            id: e.id,
            preorderEntryId: e.preorderEntryId,
            invoiceId: e.invoiceId,
            invoiceLocalId: e.invoiceLocalId,
            invoiceDate: e.invoiceDate,
            customerId: e.customerId,
            customerName: e.customerName,
            productName: e.productName,
            amount: e.amount,
            createdAt: e.createdAt,
            method: e.method,
            methodName: e.methodName,
            fulfillOnSettle: value,
          )
        else
          e,
    ];
  }

  /// Ganti seluruh isi (dipakai saat melanjutkan pesanan ditahan) — sejalan
  /// dgn `CartDebtSettlementNotifier.replaceAll`.
  void replaceAll(List<PreorderSettlementEntry> entries) {
    state = entries;
  }

  void clear() {
    state = const [];
  }

  /// Bersihkan entri yatim — sejalan dgn
  /// `CartDebtSettlementNotifier.cleanupOrphanDebtSettlements`.
  static Future<void> cleanupOrphanPreorderSettlements() async {
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

/// Entri "Pelunasi Pre-order" per-slot keranjang. Sejalan dengan
/// [cartDebtSettlementProvider].
final cartPreorderSettlementProvider = StateNotifierProvider.family<
    CartPreorderSettlementNotifier, List<PreorderSettlementEntry>, String>(
  (ref, cartId) => CartPreorderSettlementNotifier(cartId),
);
