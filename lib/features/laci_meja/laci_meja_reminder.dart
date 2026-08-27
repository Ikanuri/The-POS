import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  ///
  /// Susulan (permintaan user) — baris pre-order kini menerima [pending]
  /// LENGKAP (bukan lagi `List<String>` hasil [linesOf]) supaya tiap produk
  /// pre-order yang py `transactionId` bisa DIKLIK, merujuk balik ke nota
  /// ASLI tempat pre-order itu dicatat (berguna kalau kasir/owner sewaktu-
  /// waktu ingin cek momen nota asli, mis. pre-order tanpa DP dari beberapa
  /// hari lalu). Baris titip/ketinggalan/pinjaman TETAP teks polos (lewat
  /// [linesOf], tidak berubah).
  static Widget bar(BuildContext context, LaciMejaPending? pending) {
    if (pending == null) return const SizedBox.shrink();
    final plainLines = linesOf((
      titip: pending.titip,
      ketinggalan: pending.ketinggalan,
      pinjaman: pending.pinjaman,
      preorders: const [],
    ));
    if (plainLines.isEmpty && pending.preorders.isEmpty) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = AppTheme.laciFg(isDark);
    final rows = <Widget>[
      for (final line in plainLines)
        Text(
          line,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
        ),
      if (pending.preorders.isNotEmpty)
        _preorderRefsRow(context, pending.preorders, fg),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++)
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
                  Flexible(child: rows[i]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Baris pre-order di cart bar — `Wrap` (bukan `Text.rich` bersambung)
  /// krn tiap produk yang py `transactionId` perlu jadi target tap SENDIRI
  /// (`InkWell`, bukan `TapGestureRecognizer` manual — `InkWell` dibuang
  /// otomatis lewat siklus widget biasa, tidak perlu di-dispose manual spt
  /// recognizer di widget stateless/statis begini).
  static Widget _preorderRefsRow(
      BuildContext context, List<PreorderPendingLine> preorders, Color fg) {
    final shown = preorders.take(_maxPreorderDetail).toList();
    final sisa = preorders.length - shown.length;
    final plainStyle =
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Pre-order: ', style: plainStyle),
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) Text(', ', style: plainStyle),
          _preorderChip(context, shown[i], fg, plainStyle),
        ],
        if (sisa > 0) Text(' +$sisa lagi', style: plainStyle),
      ],
    );
  }

  static String _preorderLabel(PreorderPendingLine e) {
    final qty = _fmtQty(e.qty);
    final jaminan =
        e.depositQty > 0 ? ' (jaminan ${_fmtQty(e.depositQty)})' : '';
    return '$qty ${e.productName}$jaminan';
  }

  static Widget _preorderChip(BuildContext context, PreorderPendingLine e,
      Color fg, TextStyle plainStyle) {
    final label = _preorderLabel(e);
    // Nullable `transactionId` (titip wadah tanpa beli apa pun) -> tidak ada
    // nota utk dirujuk, tampil sbg teks biasa spt sebelumnya.
    if (e.transactionId == null) return Text(label, style: plainStyle);
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => context.push('/kasir/struk/${e.transactionId}'),
      child: Text(
        label,
        style: plainStyle.copyWith(
            fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
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
