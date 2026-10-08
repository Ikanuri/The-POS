import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gaya tampilan layar Kasir: [classic] = tampilan lama (header + daftar),
/// [modern] = tampilan baru ala katalog HTML (landing, kolom cari yang
/// berpindah, tombol aksi melayang). Kode gaya baru berada terpisah di
/// `kasir_modern.dart`; kedua gaya memakai logika kasir yang sama.
enum KasirStyle { classic, modern }

class KasirStyleNotifier extends StateNotifier<KasirStyle> {
  KasirStyleNotifier() : super(KasirStyle.classic) {
    _load();
  }

  static const prefKey = 'kasir_style';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = prefs.getString(prefKey) == 'modern'
        ? KasirStyle.modern
        : KasirStyle.classic;
  }

  Future<void> set(KasirStyle style) async {
    state = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefKey, style.name);
  }
}

final kasirStyleProvider = StateNotifierProvider<KasirStyleNotifier, KasirStyle>(
    (ref) => KasirStyleNotifier());
