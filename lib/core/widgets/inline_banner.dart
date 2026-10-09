import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import 'app_notice_card.dart';

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

/// Banner inline berbentuk kartu gaya baru (putih membulat, bayangan hangat,
/// ikon bulat beraksen di kiri). Saat [message] non-null: muncul dengan
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
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tone = switch (widget.type) {
      InlineBannerType.success => ToastTone.success,
      InlineBannerType.error => ToastTone.error,
      InlineBannerType.warning => ToastTone.warning,
      InlineBannerType.info => ToastTone.info,
    };
    final style = ToastToneStyle.of(tone, isDark);
    final ink = isDark ? const Color(0xFFECE7DD) : const Color(0xFF2A2824);

    return AnimatedSize(
      duration: AppMotion.dur(context, AppMotion.medium),
      curve: AppMotion.easeOutQuint,
      alignment: Alignment.topCenter,
      child: msg != null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(msg),
                tween: Tween(begin: 0, end: 1),
                duration: AppMotion.dur(context, AppMotion.medium),
                curve: AppMotion.easeOutQuint,
                builder: (context, t, child) => Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.translate(
                      offset: Offset(0, (1 - t) * -10), child: child),
                ),
                child: AppNoticeCard(
                  tone: tone,
                  trailing: InkResponse(
                    onTap: widget.onDismiss,
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded,
                          size: 16, color: ink.withOpacity(0.5)),
                    ),
                  ),
                  child: _messageText(msg, ink, style.fg),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
