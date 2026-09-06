import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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

/// Fitur "kembalian sudah diambil" — SATU entri riwayat = satu kali kasir
/// mencentang "sudah diambil" (lihat `_PrabayarFooterSummary` di
/// `cart_sheet.dart`). Sejalan dgn pola [PrabayarEntry] di atas: riwayat
/// (bukan cuma akumulator scalar) supaya misclick centang bisa
/// dibatalkan/di-undo satu-per-satu lewat `removeChangeTaken` — lihat
/// `_showChangeTakenList` di `cart_sheet.dart`.
@immutable
class ChangeTakenEntry {
  const ChangeTakenEntry({
    required this.id,
    required this.amount,
    required this.takenAt,
  });

  final String id;
  final int amount;

  /// Waktu kembalian ini ditandai sudah diambil.
  final DateTime takenAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'takenAt': takenAt.millisecondsSinceEpoch,
      };

  factory ChangeTakenEntry.fromJson(Map<String, dynamic> json) =>
      ChangeTakenEntry(
        id: json['id'] as String,
        amount: json['amount'] as int,
        takenAt:
            DateTime.fromMillisecondsSinceEpoch(json['takenAt'] as int),
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

  /// Fitur "kembalian sudah diambil" — RIWAYAT (BUKAN boolean sekali pakai
  /// atau scalar akumulator murni: kembalian bisa muncul & diambil
  /// berkali-kali dalam satu sesi keranjang, mis. add→kembalian
  /// muncul→diambil→kurangi lagi→kembalian baru muncul→diambil lagi, DAN
  /// tiap kemunculan bisa dibatalkan/di-undo satu-per-satu kalau kasir
  /// misclick centang — lihat [removeChangeTaken]). Dipakai di mana pun
  /// total Pra-Bayar mentah dulunya dipakai utk hitung Sisa/Kembalian —
  /// lihat `poolAvailable` di bawah & pemakaiannya di
  /// `cart_sheet.dart`/`payment_screen.dart`. TIDAK bagian dari `state`
  /// (yang tetap `List<PrabayarEntry>`, supaya seluruh call site lama
  /// tidak perlu berubah) — reaktivitas rebuild dipicu lewat re-assign
  /// `state` (list baru, isi sama) tiap kali riwayat ini berubah, lihat
  /// [recordChangeTaken]/[removeChangeTaken].
  List<ChangeTakenEntry> _changeTakenEntries = [];

  /// Total (SUM) seluruh entri riwayat — API getter dipertahankan SAMA
  /// persis (nama & tipe) dgn versi scalar lama supaya seluruh call site
  /// existing (`cart_sheet.dart`/`payment_screen.dart`) tidak perlu berubah.
  int get changeTakenTotal =>
      _changeTakenEntries.fold<int>(0, (s, e) => s + e.amount);

  /// Riwayat entri "kembalian sudah diambil" — dipakai UI baru
  /// `_showChangeTakenList` (`cart_sheet.dart`) utk menampilkan & menghapus
  /// per-entri (undo misclick centang).
  List<ChangeTakenEntry> get changeTakenEntries =>
      List.unmodifiable(_changeTakenEntries);

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (state.isEmpty && _changeTakenEntries.isEmpty) {
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          // Format lama (kompatibel mundur): list bare entri Pra-Bayar,
          // tanpa `changeTakenTotal`/`changeTakenEntries` sama sekali
          // (fitur ini belum ada saat data itu ditulis) — fallback kosong.
          if (decoded is List) {
            super.state = decoded
                .map((e) => PrabayarEntry.fromJson(e as Map<String, dynamic>))
                .toList();
          } else if (decoded is Map<String, dynamic>) {
            final entriesRaw = decoded['entries'] as List? ?? const [];
            super.state = entriesRaw
                .map((e) => PrabayarEntry.fromJson(e as Map<String, dynamic>))
                .toList();
            final changeTakenEntriesRaw =
                decoded['changeTakenEntries'] as List?;
            if (changeTakenEntriesRaw != null) {
              // Format baru (riwayat).
              _changeTakenEntries = changeTakenEntriesRaw
                  .map((e) =>
                      ChangeTakenEntry.fromJson(e as Map<String, dynamic>))
                  .toList();
            } else {
              // Format transisi lama (rilis "kembalian sudah diambil"
              // pertama, SEBELUM jadi riwayat): cuma int `changeTakenTotal`
              // — baca sbg SATU entri sintetis (amount = nilai lama,
              // takenAt = waktu baca/sekarang, karena waktu asli tidak
              // pernah disimpan) supaya tidak hilang saat resume.
              final legacyTotal =
                  (decoded['changeTakenTotal'] as num?)?.toInt() ?? 0;
              _changeTakenEntries = legacyTotal > 0
                  ? [
                      ChangeTakenEntry(
                        id: const Uuid().v4(),
                        amount: legacyTotal,
                        takenAt: DateTime.now(),
                      ),
                    ]
                  : [];
            }
          }
        } catch (_) {/* abaikan data rusak */}
      }
    }
    _loaded = true;
  }

  void _persist() {
    final snapshot = state;
    final changeTaken = List<ChangeTakenEntry>.of(_changeTakenEntries);
    SharedPreferences.getInstance().then((prefs) {
      if (snapshot.isEmpty && changeTaken.isEmpty) {
        prefs.remove(_prefKey);
      } else {
        prefs.setString(
            _prefKey,
            jsonEncode({
              'entries': snapshot.map((e) => e.toJson()).toList(),
              'changeTakenEntries':
                  changeTaken.map((e) => e.toJson()).toList(),
            }));
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

  /// Pool Pra-Bayar yang MASIH tersedia sbg kredit — total terkunci DIKURANGI
  /// yang sudah fisik diambil balik sbg kembalian ([changeTakenTotal]).
  /// SEMUA hitungan Sisa/Kembalian LIVE (`cart_sheet.dart`) & keputusan
  /// checkout final (`payment_screen.dart`) HARUS pakai ini, bukan
  /// [totalLocked] mentah — kalau tidak, kembalian yang sudah diserahkan
  /// akan dihitung ulang seakan masih tersedia utk ditarik/dipakai lagi.
  int get poolAvailable => totalLocked - changeTakenTotal;

  void add(PrabayarEntry entry) {
    state = [...state, entry];
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
  }

  /// Ganti seluruh isi (dipakai saat melanjutkan pesanan ditahan / adopsi
  /// transfer QR). [changeTakenTotal] (int, format payload `held_order`
  /// yang sudah ada — TIDAK diubah, di luar cakupan riwayat ini) ikut
  /// dipulihkan sbg SATU entri sintetis (default 0 = tidak ada entri) —
  /// siklus hidupnya SAMA dgn entri Pra-Bayar sendiri (lihat dok
  /// `kasir_screen.dart` `_parseHeldPayload`/`_resumeHeld`).
  void replaceAll(List<PrabayarEntry> entries, {int changeTakenTotal = 0}) {
    _changeTakenEntries = changeTakenTotal > 0
        ? [
            ChangeTakenEntry(
              id: const Uuid().v4(),
              amount: changeTakenTotal,
              takenAt: DateTime.now(),
            ),
          ]
        : [];
    state = entries;
  }

  /// Tandai [amount] dari pool Pra-Bayar sbg SUDAH fisik diserahkan balik ke
  /// pelanggan (checkbox "Kembalian sudah diambil" di `cart_sheet.dart`) —
  /// tambah SATU entri riwayat baru, bisa dipanggil berkali-kali dalam satu
  /// sesi keranjang. API (nama & signature) dipertahankan SAMA persis —
  /// hanya isinya yang berubah dari increment scalar jadi tambah entri.
  void recordChangeTaken(int amount) {
    if (amount <= 0) return;
    _changeTakenEntries = [
      ..._changeTakenEntries,
      ChangeTakenEntry(
        id: const Uuid().v4(),
        amount: amount,
        takenAt: DateTime.now(),
      ),
    ];
    // `state` (List<PrabayarEntry>) sendiri tidak berubah ISI — re-assign
    // list BARU (isi sama) murni utk memicu notify ke watcher
    // `cartPrabayarProvider` (mis. footer keranjang) supaya langsung
    // recompute & SEKALIGUS memicu `_persist()` (lihat setter `state` di
    // atas) menyimpan riwayat yang baru saja berubah.
    state = List.of(state);
  }

  /// Batalkan/undo SATU entri riwayat "kembalian sudah diambil" (mis. kasir
  /// misclick centang) — `changeTakenTotal`/`poolAvailable` otomatis
  /// recompute (SUM dari sisa list) begitu entri ini hilang, footer
  /// Sisa/Kembalian langsung ikut berubah lewat watcher yang sama dgn
  /// [recordChangeTaken]. Dipakai `_showChangeTakenList` (`cart_sheet.dart`).
  void removeChangeTaken(String id) {
    _changeTakenEntries =
        _changeTakenEntries.where((e) => e.id != id).toList();
    state = List.of(state);
  }

  void clear() {
    _changeTakenEntries = [];
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
