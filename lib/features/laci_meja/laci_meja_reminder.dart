import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Item 52 susulan — pengingat "pelanggan ini masih punya urusan di Laci
/// Meja" (barang dititip/ketinggalan, pinjaman wadah, pre-order), ditampilkan
/// di modal checkout & cart bar.
///
/// Bentuknya SENGAJA meniru kartu pengingat hutang (kotak kecil, ikon,
/// satu baris teks) supaya kasir langsung paham ini peringatan sejenis —
/// tapi WARNANYA sengaja BEDA: dusty rose (`AppTheme.laciFg/laciBg`, warna
/// domain Laci Meja) alih-alih merah `errorContainer` milik hutang, supaya
/// dua peringatan itu tidak pernah tertukar maknanya kalau muncul bersamaan.
class LaciMejaReminder extends StatelessWidget {
  const LaciMejaReminder({super.key, required this.pending, this.margin});

  final ({int titip, int ketinggalan, int pinjaman, int preorder})? pending;
  final EdgeInsetsGeometry? margin;

  /// Ringkasan " · "-terpisah, hanya kategori yang memang ada isinya.
  ///
  /// `titip` dan `ketinggalan` WAJIB jadi klausa terpisah (bukan digabung
  /// jadi satu kata "dititip") — user melaporkan keterangan lama selalu
  /// menulis "dititip" walau barangnya sebenarnya `jenis='ketinggalan'`
  /// (ketinggalan tanpa sengaja, bukan dititip sengaja oleh pelanggan).
  static String? summaryOf(
      ({int titip, int ketinggalan, int pinjaman, int preorder})? p) {
    if (p == null) return null;
    final parts = <String>[
      if (p.titip > 0) '${p.titip} barang dititip',
      if (p.ketinggalan > 0) '${p.ketinggalan} barang ketinggalan',
      if (p.pinjaman > 0) '${p.pinjaman} pinjaman belum kembali',
      if (p.preorder > 0) '${p.preorder} pre-order menunggu',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Varian ringkas utk cart bar: satu baris kecil di atas Total, tanpa
  /// kotak berlatar penuh (ruang di cart bar sempit & sudah padat).
  static Widget bar(BuildContext context, String summary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 13, color: AppTheme.laciFg(isDark)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              summary,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.laciFg(isDark)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = summaryOf(pending);
    if (summary == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin ?? const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.laciBg(isDark),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, size: 16, color: AppTheme.laciFg(isDark)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Laci Meja: $summary',
              style: TextStyle(fontSize: 12, color: AppTheme.laciFg(isDark)),
            ),
          ),
        ],
      ),
    );
  }
}
