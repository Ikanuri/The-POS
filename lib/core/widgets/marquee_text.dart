import 'dart:async';

import 'package:flutter/material.dart';

/// Teks satu baris yang BERJALAN kiri↔kanan bila tidak muat di lebarnya —
/// permintaan user (awalnya di cart bar kasir), menggantikan ellipsis +
/// layout yang melipat/bergeser. Dipakai bersama di beberapa layar (cart
/// bar, dashboard Laci Meja) — lihat dok masing-masing pemanggil utk
/// konteks kenapa dibutuhkan di situ.
///
/// Sengaja TIDAK memakai paket eksternal (app ini offline-first, dependency
/// baru = beban rilis) — cukup `AnimationController` + `Transform.translate`.
/// Kalau teks MUAT, widget ini berperilaku persis `Text` biasa (tidak ada
/// animasi yang jalan sia-sia & tidak membangunkan frame terus-menerus).
///
/// Jalannya DIBATASI [_maxCycles] putaran per putaran-nyala, lalu ISTIRAHAT
/// [_restPause] di awal teks, lalu OTOMATIS ULANG lagi — bukan berhenti
/// SELAMANYA. (Awalnya berhenti permanen setelah [_maxCycles], tapi user
/// laporan screenshot: nama yang dipilih beberapa detik sebelum layar
/// dilihat/di-screenshot terlihat "kepotong permanen" — kasir jarang
/// menonton terus-menerus tepat saat marquee jalan, jadi berhenti selamanya
/// terasa sama seperti bug pemotongan yang sudah diperbaiki sebelumnya.)
/// Dua alasan animasi tetap DIBATASI per putaran-nyala (bukan `repeat()`
/// tanpa henti), keduanya nyata:
///   1. Perangkat POS menyala seharian; animasi 60fps ABADI di bar bawah
///      membakar baterai tanpa guna. Jeda istirahat di antara putaran-nyala
///      menjaga rerata tetap hemat, sambil memastikan siapa pun yang lihat
///      layar akan kebagian nama bergerak dalam beberapa detik.
///   2. Animasi tanpa henti (tak pernah berhenti sama sekali) bikin
///      `tester.pumpAndSettle()` TIDAK PERNAH selesai — 10 test kasir yang
///      sudah ada langsung timeout. Dgn dibatasi per putaran-nyala + jeda,
///      pumpAndSettle tetap bisa dipakai asal tester tidak menunggu MELEWATI
///      jeda istirahat (yang memang didesain tak terbatas/berulang).
class MarqueeText extends StatefulWidget {
  const MarqueeText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // Durasi disetel ulang tiap kali overflow diukur (lihat `_sync`) —
    // makin panjang teksnya, makin lama satu putaran, supaya kecepatan
    // bacanya konsisten dan tidak "ngebut" utk nama yang sangat panjang.
    duration: const Duration(seconds: 3),
  );

  /// 4 = dua kali pergi-pulang per putaran-nyala; cukup utk membaca nama
  /// terpanjang sekalipun sebelum istirahat.
  static const _maxCycles = 4;

  /// Jeda antar putaran-nyala — cukup singkat supaya kasir yang lihat layar
  /// kapan pun tetap kebagian nama bergerak dalam beberapa detik, tapi tetap
  /// hemat baterai drpd `repeat()` abadi tanpa jeda sama sekali.
  static const _restPause = Duration(seconds: 3);

  /// TIDAK memakai `addStatusListener`: `repeat()` men-drive controller lewat
  /// simulasi internal dan TIDAK pernah memancarkan `completed`/`dismissed`,
  /// jadi listener status tak akan pernah terpanggil (sudah dicoba — animasi
  /// lanjut selamanya & pumpAndSettle tetap timeout).
  Timer? _stopTimer;
  Timer? _restTimer;
  double _lastOverflow = 0;

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    // Teks berganti (mis. pelanggan/produk lain dipilih) -> jalan lagi dari
    // awal.
    if (old.text != widget.text) {
      _stopTimer?.cancel();
      _stopTimer = null;
      _restTimer?.cancel();
      _restTimer = null;
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _restTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Jalankan/hentikan animasi sesuai apakah teks benar-benar meluber.
  void _sync(double overflow) {
    _lastOverflow = overflow;
    if (overflow <= 0) {
      _stopTimer?.cancel();
      _stopTimer = null;
      _restTimer?.cancel();
      _restTimer = null;
      if (_controller.isAnimating) _controller.stop();
      if (_controller.value != 0) _controller.value = 0;
      return;
    }
    // Sedang jalan ATAU sedang istirahat menunggu putaran-nyala berikutnya
    // (dijadwalkan sendiri oleh `_startCycle`) -> jangan diinterupsi.
    if (_controller.isAnimating || _restTimer != null) return;
    _startCycle(overflow);
  }

  /// Satu "putaran-nyala": [_maxCycles] kali pergi-pulang, lalu istirahat
  /// [_restPause] di awal teks, lalu panggil diri sendiri lagi — berulang
  /// terus selama widget masih hidup & teksnya masih meluber (BUKAN sekali
  /// lalu berhenti selamanya, lihat dokumentasi kelas ini).
  void _startCycle(double overflow) {
    // ~28 logical px per detik + jeda baca di tiap ujung (lihat kurva di
    // `_offsetFor`), diklem supaya nama pendek-tapi-meluber tidak berkedip
    // cepat & nama sangat panjang tidak jadi lambat menyiksa.
    final detik = (overflow / 28).clamp(2.0, 8.0);
    final durasi = Duration(milliseconds: (detik * 1000).round());
    _controller.duration = durasi;
    _controller.repeat(reverse: true);
    _stopTimer = Timer(durasi * _maxCycles, () {
      if (!mounted) return;
      _controller.stop();
      _controller.value = 0; // istirahat memperlihatkan awal nama
      _stopTimer = null;
      _restTimer = Timer(_restPause, () {
        if (!mounted) return;
        _restTimer = null;
        _startCycle(_lastOverflow);
      });
    });
  }

  /// Kurva "diam di ujung → geser → diam di ujung" (bukan geser konstan)
  /// supaya nama sempat terbaca utuh di kedua ujungnya.
  double _offsetFor(double t, double overflow) {
    const jeda = 0.18; // porsi waktu diam di tiap ujung
    if (t <= jeda) return 0;
    if (t >= 1 - jeda) return -overflow;
    return -overflow * ((t - jeda) / (1 - 2 * jeda));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Pengukuran overflow WAJIB memakai style yang PERSIS SAMA dgn yang
        // dipakai `Text` sungguhan di bawah — kalau tidak, painter bisa
        // keliru simpul "muat" padahal SEBENARNYA overflow, marquee tidak
        // pernah jalan, dan namanya malah kepotong permanen. Dua hal yang
        // WAJIB diikutkan (keduanya sudah pernah jadi bug NYATA yg
        // dilaporkan user):
        //   1. `textScaler` — `main.dart` menerapkan pengali skala font
        //      GLOBAL lewat `MediaQuery.textScaler`. Tanpa ini painter
        //      mengukur di skala 1.0 sementara teks dirender lebih besar.
        //   2. **`DefaultTextStyle` ambient (fontFamily!)** — `widget.style`
        //      SENGAJA tidak menyebut `fontFamily`, jadi `Text` mewarisi
        //      Hanken Grotesk dari tema (`GoogleFonts.hankenGroteskTextTheme`
        //      di `app_theme.dart`) sementara `TextPainter` yang diberi
        //      TextSpan style TANPA fontFamily memakai font DEFAULT ENGINE
        //      (Roboto) — dan Hanken Grotesk lebih LEBAR, jadi painter
        //      selalu under-measure. Efeknya persis laporan user: "Buk
        //      Khotimah" tampil "Buk" saja + ruang kosong lebar (bukan
        //      terpotong mepet), krn jatuh ke cabang `Text` biasa lalu
        //      teksnya WRAP di spasi & `maxLines: 1` cuma menyisakan kata
        //      pertama.
        final resolvedStyle =
            DefaultTextStyle.of(context).style.merge(widget.style);
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: resolvedStyle),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final overflow = painter.width - constraints.maxWidth;

        // Diukur saat layout; ubah state animasi SETELAH frame ini selesai
        // (mengubah controller di tengah build = exception).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync(overflow);
        });

        if (overflow <= 0) {
          // `softWrap: false` = jaring pengaman: kalau pengukuran di atas
          // MASIH meleset sedikit (mis. font fallback beda tipis), teks
          // terpotong MEPET di tengah karakter (nyaris tak kelihatan) —
          // BUKAN runtuh jadi kata pertama saja dgn ruang kosong lebar
          // (yang terlihat seperti data hilang, laporan user).
          return Text(widget.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: widget.style);
        }

        // Tinggi DIKUNCI ke tinggi teksnya sendiri: beberapa pemanggil
        // menaruh widget ini di dalam `Column`/`Row` tanpa batas tinggi, dan
        // `OverflowBox` tanpa batas tinggi di situ = "infinite size during
        // layout" (crash render).
        return SizedBox(
          height: painter.height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Transform.translate(
                offset: Offset(_offsetFor(_controller.value, overflow), 0),
                child: child,
              ),
              // `OverflowBox` — beri anak lebar tak terbatas supaya teksnya
              // dirender UTUH (bukan di-ellipsis dulu), baru digeser &
              // dipotong oleh `ClipRect` di atas.
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: double.infinity,
                minHeight: painter.height,
                maxHeight: painter.height,
                child: Text(widget.text,
                    maxLines: 1, softWrap: false, style: widget.style),
              ),
            ),
          ),
        );
      },
    );
  }
}
