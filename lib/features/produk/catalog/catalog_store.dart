import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import 'catalog_models.dart';

/// Penyimpanan katalog tersimpan. Disimpan sebagai JSON di tabel settings
/// (key `saved_catalogs`) — tanpa migrasi skema DB. Katalog umumnya sedikit
/// (sesekali untuk pengumuman harga), jadi blob JSON sudah memadai.
class CatalogStore extends StateNotifier<List<SavedCatalog>> {
  CatalogStore(this._db) : super(const []) {
    _load();
  }

  final AppDatabase _db;
  static const _key = 'saved_catalogs';

  Future<void> _load() async {
    final raw = await _db.getSetting(_key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .map(SavedCatalog.fromJson)
          .toList();
      // Terbaru di atas.
      list.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      state = list;
    } catch (_) {
      // Abaikan data rusak — jangan crash layar katalog.
    }
  }

  Future<void> _persist() async {
    await _db.setSetting(
        _key, jsonEncode(state.map((e) => e.toJson()).toList()));
  }

  Future<void> add(SavedCatalog catalog) async {
    state = [catalog, ...state];
    await _persist();
  }

  Future<void> update(SavedCatalog catalog) async {
    state = [
      for (final c in state)
        if (c.id == catalog.id) catalog else c,
    ]..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((c) => c.id != id).toList();
    await _persist();
  }
}

final catalogStoreProvider =
    StateNotifierProvider<CatalogStore, List<SavedCatalog>>((ref) {
  return CatalogStore(ref.watch(databaseProvider));
});

/// Katalog yang sedang diedit (null = membuat katalog baru). Diset saat menekan
/// "Edit" di daftar katalog, dibaca oleh layar kasir mode katalog saat menyimpan.
final catalogEditProvider = StateProvider<SavedCatalog?>((ref) => null);
