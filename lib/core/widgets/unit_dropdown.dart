import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dropdown pemilih SATUAN bergaya kartu aksen — pola SAMA
/// `ProductPickerDropdown` (`features/laci_meja/product_picker_dropdown.
/// dart`), tapi generik atas TIPE key `T` (bisa `int` id `unit_types`,
/// bisa `String` nama satuan mentah) supaya dipakai lintas fitur: "Ganti
/// Satuan" Cek Stok, "Hitung Fisik" Stock Opname, & "Jenis Satuan" edit
/// produk.
///
/// Bug nyata dilaporkan user (screenshot): ketiga tempat itu dulu pakai
/// widget dropdown BAWAAN Flutter (`DropdownButton`/`DropdownButtonFormField`
/// TANPA `menuMaxHeight`, atau `PopupMenuButton` TANPA `constraints`) —
/// daftar `unit_types` toko real BISA 15-25 entri (Kg, Lusin, Ons, Pak,
/// Paket, Pcs, Pres, Rek, Ret, Roll, Sak, Slop, Tas, Toples, dst — lihat
/// `_kDefaultUnitTypes`), menunya lalu tumbuh nyaris SELURUH tinggi layar
/// & menimpa AppBar/tombol Simpan/baris produk lain di bawahnya —
/// jauh dari "custom design app ini", terlihat template Flutter polos.
///
/// Fix: `PopupMenuButton` dgn `constraints` (maxHeight dibatasi, Flutter
/// otomatis bikin scroll internal di atas itu — TIDAK PERNAH melebihi
/// layar lagi) + baris menu gaya sendiri (radio & tint terpilih, sama
/// `ProductPickerMenuRow`), BUKAN `PopupMenuItem`/`DropdownMenuItem` polos.
class UnitDropdown<T extends Object> extends StatelessWidget {
  const UnitDropdown({
    super.key,
    required this.entries,
    required this.selectedKey,
    required this.onSelected,
    this.formLabel,
    this.tooltip = 'Pilih satuan',
    this.enabled = true,
  });

  /// key (id `unit_types` ATAU nama satuan mentah) → nama tampil, URUT
  /// sesuai urutan yang mau ditampilkan (pemanggil yang menyusun
  /// urutannya, mis. satuan produk dulu lalu sisa nama umum).
  final Map<T, String> entries;

  /// Key yang sedang terpilih. Kalau tidak ada di [entries] (mis. produk
  /// belum pernah pilih), jatuh ke entry PERTAMA utk tampilan chip saja —
  /// pemanggil tetap sumber kebenaran lewat [onSelected].
  final T? selectedKey;

  final ValueChanged<T> onSelected;

  /// Diisi → tampil sbg field form (bungkus `InputDecorator`, label
  /// mengambang spt `DropdownButtonFormField` lama, dipakai "Jenis Satuan"
  /// edit produk). Null → tampil sbg chip ringkas inline (dipakai stepper
  /// Cek Stok / Hitung Fisik Opname).
  final String? formLabel;

  final String tooltip;

  /// false → tampil apa adanya (chip/field) TANPA bisa dibuka sama sekali
  /// (dipakai mode lihat-saja/read-only, mis. produk arsip).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurface;

    if (entries.isEmpty) {
      return formLabel == null
          ? const SizedBox.shrink()
          : InputDecorator(
              decoration: InputDecoration(
                  labelText: formLabel, isDense: true, enabled: false),
              child: const Text('—'),
            );
    }

    final fallbackKey = entries.containsKey(selectedKey)
        ? selectedKey as T
        : entries.keys.first;
    final displayName = entries[fallbackKey]!;

    if (!enabled) {
      return formLabel == null
          ? _chip(displayName)
          : _field(context, displayName);
    }

    return PopupMenuButton<T>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      offset: const Offset(0, 6),
      elevation: 6,
      color: scheme.surface,
      // Item sensitif (screenshot user): daftar unit_types toko real bisa
      // 15-25 entri — TANPA batas ini menu tumbuh nyaris seluruh tinggi
      // layar & menimpa konten lain. 320 cukup utk ~7 baris terlihat,
      // sisanya scroll (Flutter otomatis membungkus isi PopupMenuButton
      // dgn scroll view internal begitu melebihi constraints).
      constraints: const BoxConstraints(minWidth: 160, maxHeight: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.accent.withOpacity(0.25)),
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final e in entries.entries)
          PopupMenuItem<T>(
            value: e.key,
            padding: EdgeInsets.zero,
            height: 0,
            child: _UnitMenuRow(
              name: e.value,
              selected: e.key == fallbackKey,
              fg: fg,
            ),
          ),
      ],
      child:
          formLabel == null ? _chip(displayName) : _field(context, displayName),
    );
  }

  Widget _chip(String displayName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(displayName,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent)),
          const SizedBox(width: 3),
          Icon(Icons.expand_more_rounded,
              size: 16, color: AppTheme.accent.withOpacity(.75)),
        ],
      ),
    );
  }

  Widget _field(BuildContext context, String displayName) {
    return InputDecorator(
      decoration: InputDecoration(labelText: formLabel, isDense: true),
      isEmpty: false,
      child: Row(
        children: [
          Expanded(
              child: Text(displayName, style: const TextStyle(fontSize: 14.5))),
          Icon(Icons.expand_more_rounded,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Satu baris menu `UnitDropdown` — desain sendiri (radio + tint terpilih),
/// sama gaya `ProductPickerMenuRow` (laci_meja) supaya konsisten se-app.
class _UnitMenuRow extends StatelessWidget {
  const _UnitMenuRow(
      {required this.name, required this.selected, required this.fg});

  final String name;
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
        ],
      ),
    );
  }
}
