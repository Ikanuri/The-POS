import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_theme.dart';

/// Item 52 susulan — pengingat "pelanggan ini masih punya urusan di Laci
/// Meja" (barang dititip/ketinggalan, pinjaman wadah, pre-order), ditampilkan
/// di modal checkout & cart bar.
///
/// Bentuknya SENGAJA meniru kartu pengingat hutang (kotak kecil, ikon,
/// baris teks) supaya kasir langsung paham ini peringatan sejenis — tapi
/// WARNANYA sengaja BEDA: dusty rose (`AppTheme.laciFg/laciBg`, warna domain
/// Laci Meja) alih-alih merah `errorContainer` milik hutang, supaya dua
/// peringatan itu tidak pernah tertukar maknanya kalau muncul bersamaan.
class LaciMejaReminder extends StatelessWidget {
  const LaciMejaReminder({super.key, required this.pending, this.margin});

  final LaciMejaPending? pending;
  final EdgeInsetsGeometry? margin;

  /// Berapa produk pre-order yang dirinci sebelum sisanya diringkas jadi
  /// "+N lagi" — permintaan user: cart bar TIDAK BOLEH jadi sangat tinggi
  /// hanya karena satu pelanggan punya banyak pre-order sekaligus.
  static const _maxPreorderDetail = 2;

  /// SATU BARIS PER KATEGORI (permintaan user: "line 1 barang ketinggalan,
  /// line 2 pinjaman barang, line 3 transaksi pre-order") — bukan lagi satu
  /// string panjang digabung " · " yang sulit dibaca sekilas.
  ///
  /// `titip` dan `ketinggalan` tetap dipisah di dalam baris pertama (jenisnya
  /// beda maknanya — dititip sengaja vs ketinggalan tanpa sengaja).
  /// Baris pre-order SENGAJA menyebut nama produk + qty + jaminan (kategori
  /// lain cukup jumlah) — itu yang diminta user, supaya kasir tahu barang apa
  /// yang ditunggu tanpa membuka dashboard.
  static List<String> linesOf(LaciMejaPending? p) {
    if (p == null) return const [];
    final lines = <String>[];

    final titipParts = <String>[
      if (p.titip > 0) '${p.titip} barang dititip',
      if (p.ketinggalan > 0) '${p.ketinggalan} barang ketinggalan',
    ];
    if (titipParts.isNotEmpty) lines.add(titipParts.join(' · '));

    if (p.pinjaman > 0) lines.add('${p.pinjaman} pinjaman belum kembali');

    if (p.preorders.isNotEmpty) {
      final shown = p.preorders.take(_maxPreorderDetail).map((e) {
        final qty = _fmtQty(e.qty);
        final jaminan =
            e.depositQty > 0 ? ' (jaminan ${_fmtQty(e.depositQty)})' : '';
        return '$qty ${e.productName}$jaminan';
      }).toList();
      final sisa = p.preorders.length - shown.length;
      lines.add(
          'Pre-order: ${shown.join(', ')}${sisa > 0 ? ' +$sisa lagi' : ''}');
    }

    return lines;
  }

  static String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  /// Varian ringkas utk cart bar: baris-baris kecil di atas Total, tanpa
  /// kotak berlatar penuh (ruang di cart bar sempit & sudah padat).
  static Widget bar(BuildContext context, List<String> lines) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppTheme.laciFg(isDark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Ikon HANYA di baris pertama — baris berikutnya menjorok
                  // sejajar teks supaya kebaca sbg satu blok, bukan 3
                  // peringatan terpisah.
                  if (i == 0) ...[
                    Icon(Icons.inbox_outlined, size: 13, color: fg),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      lines[i],
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: fg),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = linesOf(pending);
    if (lines.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppTheme.laciFg(isDark);
    return Container(
      margin: margin ?? const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.laciBg(isDark),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.inbox_outlined, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < lines.length; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
                    child: Text(
                      i == 0 ? 'Laci Meja: ${lines[i]}' : lines[i],
                      style: TextStyle(fontSize: 12, color: fg),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
