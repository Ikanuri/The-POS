import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Field pencarian yang bisa MELEBAR/MENGECIL (permintaan user — screenshot
/// dashboard/riwayat Laci Meja: kotak pencarian full-width memakan tempat
/// baris filter di bawahnya, terlalu sempit/terpotong di HP 360-400dp).
///
/// PERILAKU direplikasi dari pola yang SUDAH ADA di `_KasirTopbar`
/// (`lib/features/kasir/kasir_screen.dart`, sekitar baris 2270-2520):
/// collapsed = ikon kaca pembesar, tap/dapat fokus → melebar jadi field
/// penuh, kehilangan fokus (tap di luar) ATAU tombol x saat kosong →
/// mengecil lagi. Teks yang sudah diketik TIDAK ikut hilang saat
/// mengecil — cuma lebar VISUAL yang berubah, filter tetap aktif.
///
/// IMPLEMENTASI TEKNIS widget INI SENDIRI tetap sederhana (BUKAN
/// `Stack`+`AnimatedPositioned` di dalam sini) — cuma `if (expanded) ...
/// else ...` biasa yang merender collapsed (ikon 36×36) atau `TextField`
/// penuh, mengikuti lebar yang DIBERI PEMANGGIL (controlled component,
/// status dipegang PEMANGGIL lewat `expanded`/`onExpandedChanged`, lihat
/// juga dok field itu). Susulan (poin 1c, `laci_meja_dashboard_screen.dart`):
/// tab Pre-order sekarang PUNYA baris tombol (Kuota+Salin) yang perlu
/// ditimpa begitu field ini melebar — mekanisme `Stack`+`AnimatedPositioned`
/// utk itu ada di PEMANGGIL (dashboard screen), BUKAN di sini, supaya
/// `riwayat_laci_meja_screen.dart` (yang tidak py tombol di sebelahnya)
/// tetap bisa pakai widget ini apa adanya tanpa ikut kena kerumitan itu.
/// Satu widget ini dipakai ULANG di `laci_meja_dashboard_screen.dart` (tab
/// Pre-order) DAN `riwayat_laci_meja_screen.dart` — sengaja disatukan
/// (bukan diduplikasi 2x) krn perilaku intinya identik, cuma `hintText` &
/// callback yang beda per layar.
class LaciMejaExpandableSearch extends StatefulWidget {
  const LaciMejaExpandableSearch({
    super.key,
    required this.hintText,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onChanged,
  });

  final String hintText;

  /// Status expanded SAAT INI — dipegang PEMANGGIL (controlled component),
  /// supaya pemanggil bisa ikut menyembunyikan/menampilkan widget lain di
  /// sebelahnya (mis. baris filter) begitu status ini berubah.
  final bool expanded;

  /// Dipanggil begitu widget ini INGIN status expanded berubah (tap ikon
  /// utk melebar, kehilangan fokus/tombol x utk mengecil) — pemanggil WAJIB
  /// menyimpan nilai baru & meneruskannya balik lewat [expanded] di build
  /// berikutnya, kalau tidak widget ini tidak akan pernah melebar/mengecil.
  final ValueChanged<bool> onExpandedChanged;

  final ValueChanged<String> onChanged;

  @override
  State<LaciMejaExpandableSearch> createState() =>
      _LaciMejaExpandableSearchState();
}

class _LaciMejaExpandableSearchState extends State<LaciMejaExpandableSearch> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  /// Mengikuti fokus field SUNGGUHAN (bukan `setState` internal) — begitu
  /// field dapat fokus atau kehilangan fokus (tap di luar), status expanded
  /// diteruskan ke pemanggil. Pola sama persis `_KasirTopbarState.
  /// _onFocusChange`.
  void _onFocusChange() {
    if (_focus.hasFocus != widget.expanded) {
      widget.onExpandedChanged(_focus.hasFocus);
    }
  }

  /// Tap ikon collapsed → minta pemanggil melebar. Fokus SUNGGUHAN baru
  /// didapat lewat `autofocus: true` di `TextField` setelah widget ini
  /// benar-benar dibangun ulang dalam status expanded (`_focus` belum
  /// attached ke widget apa pun selagi masih collapsed, jadi
  /// `requestFocus()` di sini belum tentu berefek).
  void _expand() => widget.onExpandedChanged(true);

  /// Tombol x di ujung field (hanya tampil saat expanded): kosong → mengecil
  /// (unfocus, teks tetap seperti apa adanya/kosong); ada isi → hapus semua
  /// karakter TAPI tetap expanded (tidak mengecil).
  void _onClearOrShrink() {
    if (_ctrl.text.isEmpty) {
      _focus.unfocus();
    } else {
      _ctrl.clear();
      widget.onChanged('');
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.expanded) {
      return _CollapsedSearchButton(onTap: _expand);
    }
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      autofocus: true,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: IconButton(
          icon: const Icon(Icons.close, size: 16),
          visualDensity: VisualDensity.compact,
          onPressed: _onClearOrShrink,
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      ),
      onChanged: (v) {
        widget.onChanged(v);
        // Rebuild lokal semata utk memunculkan/menyembunyikan tombol clear
        // (state pencariannya sendiri hidup di pemanggil, bukan di sini).
        setState(() {});
      },
      onTapOutside: (_) => _focus.unfocus(),
    );
  }
}

/// Ikon collapsed — gaya SAMA dgn tombol ikon lain di baris atas dashboard
/// (kategori, Kuota/Salin Laporan). Ukuran 36×36 PERSIS `_CategoryIconBtn`
/// (permintaan user, redesain: field cari jadi satu ikon sebesar kotak
/// kategori, bukan lagi kotak lebar `Expanded`) — border aksen tipis, biar
/// tetap satu keluarga tombol ikon, bukan style baru.
class _CollapsedSearchButton extends StatelessWidget {
  const _CollapsedSearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'Cari',
      icon: const Icon(Icons.search, size: 18),
      visualDensity: VisualDensity.compact,
      alignment: Alignment.center,
      style: IconButton.styleFrom(
        foregroundColor: AppTheme.accent,
        side: BorderSide(color: AppTheme.accent.withOpacity(0.5)),
        minimumSize: const Size(36, 36),
        maximumSize: const Size(36, 36),
        alignment: Alignment.center,
      ),
    );
  }
}
