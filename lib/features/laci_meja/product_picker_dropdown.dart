import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/marquee_text.dart';

/// Dropdown pemilih produk bergaya kartu aksen (permintaan user eksplisit
/// "bukan default flutter" — bukan `PopupMenuItem` polos + `ListTile`
/// bawaan, tapi kartu aksen dgn indikator radio & badge). SATU pola dipakai
/// ULANG di SEMUA tempat pemilih/filter produk pre-order (permintaan user
/// eksplisit "opsi dropdown design anda kemarin itu sudah paling pas" —
/// bukan varian desain baru per tempat):
/// - Pemilih produk jaminan di `_PreorderStatsLine`
///   (`laci_meja_dashboard_screen.dart`) — badge "N jaminan".
/// - Filter produk tab Pre-order dashboard (dulu baris `ChoiceChip`
///   di-scroll horizontal) — badge kuota "maks N" (kalau ada), plus opsi
///   "Semua Produk".
/// - Filter produk tab Pre-order `riwayat_laci_meja_screen.dart` (dulu
///   `ChoiceChip` juga) — tanpa badge, plus opsi "Semua Produk".
///
/// Tetap pakai mekanisme `PopupMenuButton` (posisi/dismiss/keyboard sudah
/// teruji Flutter sendiri), yang di-custom total cuma tampilannya (chip +
/// isi menu).
class ProductPickerDropdown extends StatelessWidget {
  const ProductPickerDropdown({
    super.key,
    required this.entries,
    required this.selectedId,
    required this.onSelected,
    this.allLabel,
    this.icon = Icons.inventory_2_outlined,
    this.tooltip = 'Pilih produk',
  });

  /// id produk -> (nama tampil, teks badge opsional di kanan tiap baris
  /// menu — mis. "N jaminan"/"maks N"; null = baris itu tanpa badge).
  final Map<String, ({String name, String? badge})> entries;

  /// Produk yang sedang dipilih. null berarti opsi "Semua" SEDANG dipilih
  /// (hanya valid kalau [allLabel] diisi) — kalau [allLabel] null & value-
  /// nya bukan salah satu key [entries], chip jatuh ke entry PERTAMA
  /// (dipakai pemilih jaminan yang selalu punya 1 produk terpilih).
  final String? selectedId;

  /// Dipanggil dgn id produk yang dipilih, atau null kalau opsi "Semua"
  /// yang dipilih (hanya bisa terjadi kalau [allLabel] diisi).
  final ValueChanged<String?> onSelected;

  /// Diisi -> dropdown dapat opsi tambahan "Semua Produk" di baris paling
  /// atas (dipakai filter, [selectedId] null = opsi ini yang aktif). Null
  /// -> tanpa opsi "semua" (dipakai pemilih jaminan, selalu ada 1 produk
  /// terpilih, tidak ada makna "semua produk sekaligus").
  final String? allLabel;

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppTheme.laciFg(isDark);

    final showingAll = allLabel != null && selectedId == null;
    final fallbackId =
        entries.containsKey(selectedId) ? selectedId! : entries.keys.first;
    final displayName = showingAll ? allLabel! : entries[fallbackId]!.name;
    // >1 pilihan produk ATAU ada opsi "Semua" tambahan -> layak jadi
    // dropdown (bisa dipilih). Kalau cuma 1 produk & tanpa opsi "semua",
    // chip cuma tampilan (tidak ada apa pun utk dipilih).
    final hasOthers = entries.length > 1 || allLabel != null;

    final chip = Container(
      padding: EdgeInsets.fromLTRB(8, 4, hasOthers ? 4 : 8, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withOpacity(0.14),
            AppTheme.accent.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.accent),
          const SizedBox(width: 4),
          // Nama produk dibatasi lebarnya & dibuat berjalan (marquee) kalau
          // kepanjangan — dulu chip ini bisa melebar tak terbatas & mendorong
          // widget lain di sebelahnya keluar layar tanpa tanda ada konten
          // terpotong.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: MarqueeText(
              text: displayName,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
          if (hasOthers) ...[
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 16, color: AppTheme.accent),
          ],
        ],
      ),
    );

    if (!hasOthers) return chip;

    return PopupMenuButton<String>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 6),
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.accent.withOpacity(0.25)),
      ),
      constraints: const BoxConstraints(minWidth: 180),
      // BUG YANG SUDAH DIPERBAIKI saat implementasi: `PopupMenuButton<T>`
      // (Flutter SDK) memperlakukan HASIL RUTE `null` sbg "menu ditutup
      // TANPA memilih apa pun" (panggil `onCanceled`, BUKAN `onSelected`) —
      // lihat `_PopupMenuButtonState.showButtonMenu()`. Kalau opsi "Semua"
      // dipasang literal `PopupMenuItem<String?>(value: null)`, MEMILIH
      // baris itu TIDAK PERNAH memanggil `onSelected` sama sekali (bug
      // ketemu via widget test, `product_picker_dropdown_test.dart`) —
      // jadi opsi "Semua" tidak bisa dipilih sama sekali. Fix: PopupMenuButton
      // generik `<String>` (non-nullable) pakai SENTINEL string
      // [_allSentinel] utk baris "Semua", dipetakan balik ke `null` di
      // sini SEBELUM diteruskan ke [onSelected] milik pemanggil.
      onSelected: (value) =>
          onSelected(value == _allSentinel ? null : value),
      itemBuilder: (context) => [
        if (allLabel != null)
          PopupMenuItem<String>(
            value: _allSentinel,
            padding: EdgeInsets.zero,
            height: 0,
            child: ProductPickerMenuRow(
              name: allLabel!,
              badge: null,
              selected: showingAll,
              fg: fg,
            ),
          ),
        for (final e in entries.entries)
          PopupMenuItem<String>(
            value: e.key,
            padding: EdgeInsets.zero,
            height: 0,
            child: ProductPickerMenuRow(
              name: e.value.name,
              badge: e.value.badge,
              selected: !showingAll && e.key == fallbackId,
              fg: fg,
            ),
          ),
      ],
      child: chip,
    );
  }
}

/// Nilai sentinel utk baris "Semua" di menu — lihat komentar bug fix di
/// atas. Awalan+akhiran garis-bawah ganda supaya PRAKTIS MUSTAHIL
/// bentrok dgn `productId` sungguhan mana pun (UUID/kode produk toko).
const String _allSentinel = '__laci_meja_semua_produk__';

/// Satu baris pilihan di dropdown `ProductPickerDropdown` — desain sendiri:
/// indikator radio (bukan cuma teks polos), nama produk, badge opsional
/// bulat beraksen. Baris yang sedang dipilih diberi tint latar supaya
/// langsung kelihatan tanpa perlu baca radio-nya.
class ProductPickerMenuRow extends StatelessWidget {
  const ProductPickerMenuRow({
    super.key,
    required this.name,
    required this.badge,
    required this.selected,
    required this.fg,
  });

  final String name;
  final String? badge;
  final bool selected;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      color: selected ? AppTheme.accent.withOpacity(0.1) : null,
      child: Row(
        children: [
          Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? AppTheme.accent : fg.withOpacity(0.35)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: fg)),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent)),
            ),
          ],
        ],
      ),
    );
  }
}
