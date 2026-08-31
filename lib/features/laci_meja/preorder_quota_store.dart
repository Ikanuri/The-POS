import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';

/// Ambang kuota pre-order per produk (permintaan user): "kiriman normal dari
/// pangkalan itu 70 biji" — antrian yang melewati angka itu diberi garis
/// pembatas di dashboard supaya staf tahu sampai siapa yang bisa dilayani
/// dari kiriman berikutnya.
///
/// Disimpan sbg blob JSON di tabel settings (pola sama `saved_catalogs`) —
/// TANPA migrasi DB: ini konfigurasi operasional, bukan data transaksi, dan
/// jumlah produk yang perlu dibatasi selalu sedikit.
///
/// Produk yang TIDAK ada di map = kuota nonaktif. Menonaktifkan toggle
/// menghapus kuncinya, jadi tidak ada state "aktif tapi 0" yang ambigu.
class PreorderQuotaStore extends StateNotifier<Map<String, double>> {
  PreorderQuotaStore(this._db) : super(const {}) {
    _load();
  }

  final AppDatabase _db;
  static const _key = 'preorder_quota_thresholds';

  Future<void> _load() async {
    final raw = await _db.getSetting(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      state = {
        for (final entry in decoded.entries)
          if (entry.value is num && (entry.value as num) > 0)
            entry.key.toString(): (entry.value as num).toDouble(),
      };
    } catch (_) {
      // Abaikan data rusak — jangan bikin dashboard gagal render.
    }
  }

  Future<void> setThreshold(String productId, double threshold) async {
    state = {...state, productId: threshold};
    await _persist();
  }

  Future<void> clearThreshold(String productId) async {
    state = {...state}..remove(productId);
    await _persist();
  }

  Future<void> _persist() => _db.setSetting(_key, jsonEncode(state));
}

final preorderQuotaProvider =
    StateNotifierProvider<PreorderQuotaStore, Map<String, double>>(
        (ref) => PreorderQuotaStore(ref.watch(databaseProvider)));

/// Entri pre-order yang berada DI LUAR kuota produknya, dihitung dari antrian
/// yang MASIH TERBUKA saat ini — bukan posisi yang dibekukan sekali lalu
/// disimpan.
///
/// Ini inti permintaan user: "jika ada pre-order terbaru tiba-tiba dipenuhi
/// untuk alasan tertentu, padahal set line jumlah sudah ditetapkan, itu tetap
/// menyesuaikan dengan antrian". Karena hasilnya murni turunan dari daftar
/// entri terbuka (yang dipenuhi/dibatalkan otomatis hilang dari daftar),
/// garisnya bergeser sendiri tanpa perlu logika antre ulang.
///
/// [entries] HARUS sudah terurut FIFO (`createdAt` menaik) dan hanya berisi
/// entri terbuka — persis yang dikeluarkan `watchPreorderEntries`.
///
/// [takenQty] = sudah berapa yang DIPENUHI SEBAGIAN per entri (dari
/// `laciMejaTakenQtyProvider`). Kumulatifnya memakai SISA yang belum
/// dipenuhi (`qtyOrdered - taken`), bukan `qtyOrdered` mentah — kalau tidak,
/// entri yang sudah dipenuhi sebagian (mis. 4 dari 5) tetap membebani kuota
/// seolah-olah belum tersentuh sama sekali, dan entri di bawahnya tidak
/// pernah "naik" walau barangnya sudah sebagian besar keluar.
Set<String> preorderIdsBeyondQuota(
    List<PreorderEntry> entries, String productId, double threshold,
    {Map<String, double> takenQty = const {}}) {
  final out = <String>{};
  var running = 0.0;
  for (final e in entries) {
    if (e.productId != productId) continue;
    final sisa = (e.qtyOrdered - (takenQty[e.id] ?? 0)).clamp(0.0, e.qtyOrdered);
    running += sisa;
    if (running > threshold) out.add(e.id);
  }
  return out;
}
