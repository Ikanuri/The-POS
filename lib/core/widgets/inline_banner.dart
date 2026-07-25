import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum InlineBannerType { success, error, warning, info }

/// Mixin agar layar mudah memakai banner mengambang tanpa boilerplate.
/// Pakai: `with InlineBannerStateMixin<MyScreen>`, panggil
/// [showBanner]/[showError]/[showSuccess], lalu sisipkan [inlineBanner]
/// di paling atas body Column (atau abaikan — overlay dikelola sendiri).
mixin InlineBannerStateMixin<T extends StatefulWidget> on State<T> {
  String? _ibMsg;
  InlineBannerType _ibType = InlineBannerType.info;

  void showBanner(String message,
      {InlineBannerType type = InlineBannerType.info}) {
    if (!mounted) return;
    setState(() {
      _ibMsg = message;
      _ibType = type;
    });
  }

  void showError(String message) =>
      showBanner(message, type: InlineBannerType.error);
  void showSuccess(String message) =>
      showBanner(message, type: InlineBannerType.success);

  void hideBanner() {
    if (mounted) setState(() => _ibMsg = null);
  }

  Widget inlineBanner() => InlineBanner(
        message: _ibMsg,
        type: _ibType,
        onDismiss: hideBanner,
      );
}

/// Banner mengambang berbentuk kartu (margin horizontal, sudut bulat,
/// shadow, accent bar vertikal). Saat [message] non-null: muncul dengan
/// AnimatedSize (push content down sedikit). Auto-dismiss setelah
/// [duration]. Tap ✕ untuk dismiss manual.
class InlineBanner extends StatefulWidget {
  const InlineBanner({
    super.key,
    this.message,
    this.type = InlineBannerType.info,
    this.duration = const Duration(seconds: 4),
    required this.onDismiss,
    this.linkText,
    this.onLinkTap,
  });

  final String? message;
  final InlineBannerType type;
  final Duration duration;
  final VoidCallback onDismiss;

  /// Potongan teks di dalam [message] yang dijadikan tautan (di-highlight &
  /// bisa diketuk). Harus PERSIS muncul di [message]; kalau tidak ditemukan,
  /// banner tetap tampil sebagai teks biasa (tidak pernah gagal/kosong).
  /// Butuh [onLinkTap] juga — salah satu saja tidak mengaktifkan tautan.
  final String? linkText;

  /// Aksi saat [linkText] diketuk. Selama ini di-set, banner TIDAK
  /// auto-dismiss: 4 detik jelas tidak cukup untuk membaca lalu mengetuk,
  /// dan banner yang hilang sendiri membuat aksinya tidak mungkin diraih.
  /// User menutupnya lewat ✕ (atau otomatis tergantikan pesan berikutnya).
  final VoidCallback? onLinkTap;

  @override
  State<InlineBanner> createState() => _InlineBannerState();
}

class _InlineBannerState extends State<InlineBanner> {
  Timer? _timer;

  /// Satu recognizer dipakai ulang (`onTap`-nya yang diganti tiap build) —
  /// bikin baru di build akan bocor karena tidak pernah di-dispose.
  final _linkRecognizer = TapGestureRecognizer();

  @override
  void didUpdateWidget(InlineBanner old) {
    super.didUpdateWidget(old);
    if (widget.message != null && widget.message != old.message) {
      _timer?.cancel();
      // Banner yang punya aksi tidak boleh hilang sendiri (lihat dok
      // [InlineBanner.onLinkTap]).
      if (widget.onLinkTap == null) {
        _timer = Timer(widget.duration, () {
          if (mounted) widget.onDismiss();
        });
      }
    } else if (widget.message == null) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _linkRecognizer.dispose();
    super.dispose();
  }

  /// Teks pesan — biasa, atau dengan satu potongan yang di-highlight & bisa
  /// diketuk kalau [InlineBanner.linkText] + [InlineBanner.onLinkTap] di-set.
  Widget _messageText(String msg, Color fg, Color accent) {
    final style = TextStyle(
      color: fg,
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.4,
    );
    final link = widget.linkText;
    final onTap = widget.onLinkTap;
    if (link == null || link.isEmpty || onTap == null) {
      return Text(msg, style: style);
    }
    final at = msg.indexOf(link);
    if (at < 0) return Text(msg, style: style);

    _linkRecognizer.onTap = onTap;
    return Text.rich(TextSpan(style: style, children: [
      TextSpan(text: msg.substring(0, at)),
      TextSpan(
        text: link,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.underline,
          decorationColor: accent,
        ),
        recognizer: _linkRecognizer,
      ),
      TextSpan(text: msg.substring(at + link.length)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (Color bg, Color fg, Color accent, IconData ico) =
        switch (widget.type) {
      // Sukses = HIJAU soft, Gagal = MERAH — pakai warna semantik yang sama
      // dengan "kembalian"/"hutang" di kasir (AppTheme.change*/debt*), sudah
      // theme-aware light & dark, agar konsisten di seluruh app.
      InlineBannerType.success => (
          AppTheme.changeBg(isDark),
          AppTheme.changeFg(isDark),
          AppTheme.changeFg(isDark),
          Icons.check_circle_rounded,
        ),
      InlineBannerType.error => (
          AppTheme.debtBg(isDark),
          AppTheme.debtFg(isDark),
          AppTheme.debtFg(isDark),
          Icons.error_rounded,
        ),
      // Warning: sediakan varian dark eksplisit (dulu hardcode terang saja →
      // kontras jelek di dark mode).
      InlineBannerType.warning => isDark
          ? (
              const Color(0x40F97316),
              const Color(0xFFFFD9A0),
              const Color(0xFFF97316),
              Icons.warning_rounded,
            )
          : (
              const Color(0xFFFFEDD5),
              const Color(0xFF7C4A00),
              const Color(0xFFF97316),
              Icons.warning_rounded,
            ),
      InlineBannerType.info => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          scheme.secondary,
          Icons.info_rounded,
        ),
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: msg != null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                elevation: 3,
                shadowColor: accent.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 3,
                        height: 34,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Icon(ico, size: 18, color: accent),
                      const SizedBox(width: 9),
                      Expanded(child: _messageText(msg, fg, accent)),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: Icon(Icons.close_rounded,
                            size: 16,
                            color: fg.withOpacity(0.55)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
