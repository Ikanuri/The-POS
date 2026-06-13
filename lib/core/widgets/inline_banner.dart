import 'dart:async';
import 'package:flutter/material.dart';

enum InlineBannerType { success, error, warning, info }

/// Mixin agar layar mudah memakai banner inline tanpa boilerplate.
/// Pakai: `with InlineBannerStateMixin<MyScreen>`, panggil [showBanner]/
/// [showError]/[showSuccess], lalu sisipkan [inlineBanner] di paling atas
/// body Column.
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

/// Banner animasi yang menyatu dengan konten halaman (bukan overlay).
/// Saat [message] non-null: muncul dengan AnimatedSize (push content down).
/// Auto-dismiss setelah [duration]. Tap ✕ untuk dismiss manual.
class InlineBanner extends StatefulWidget {
  const InlineBanner({
    super.key,
    this.message,
    this.type = InlineBannerType.info,
    this.duration = const Duration(seconds: 4),
    required this.onDismiss,
  });

  final String? message;
  final InlineBannerType type;
  final Duration duration;
  final VoidCallback onDismiss;

  @override
  State<InlineBanner> createState() => _InlineBannerState();
}

class _InlineBannerState extends State<InlineBanner> {
  Timer? _timer;

  @override
  void didUpdateWidget(InlineBanner old) {
    super.didUpdateWidget(old);
    if (widget.message != null && widget.message != old.message) {
      _timer?.cancel();
      _timer = Timer(widget.duration, () {
        if (mounted) widget.onDismiss();
      });
    } else if (widget.message == null) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final scheme = Theme.of(context).colorScheme;

    final (Color bg, Color fg, IconData ico) = switch (widget.type) {
      InlineBannerType.success => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.check_circle_outline,
        ),
      InlineBannerType.error => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_outline,
        ),
      InlineBannerType.warning => (
          const Color(0xFFFFEDD5),
          const Color(0xFF7C4A00),
          Icons.warning_amber_outlined,
        ),
      InlineBannerType.info => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          Icons.info_outline,
        ),
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: msg != null
          ? Container(
              width: double.infinity,
              color: bg,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(ico, size: 18, color: fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      msg,
                      style: TextStyle(color: fg, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close, size: 16, color: fg),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
