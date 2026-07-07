import 'package:flutter/material.dart';

/// Toast ringan yang muncul di ATAS layar lalu hilang sendiri.
/// Dipakai untuk notifikasi yang tidak boleh menutupi tombol aksi di bawah
/// (mis. saat melanjutkan pesanan ditahan di kasir).
void showTopToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  Duration duration = const Duration(seconds: 2),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  final scheme = Theme.of(context).colorScheme;
  final topInset = MediaQuery.of(context).padding.top;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: topInset + 10,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: _TopToast(
          message: message,
          icon: icon,
          background: scheme.inverseSurface,
          foreground: scheme.onInverseSurface,
          duration: duration,
        ),
      ),
    ),
  );

  overlay.insert(entry);
  Future.delayed(duration + const Duration(milliseconds: 350), () {
    if (entry.mounted) entry.remove();
  });
}

class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.message,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.duration,
  });

  final String message;
  final IconData icon;
  final Color background;
  final Color foreground;
  final Duration duration;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, -0.6),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    Future.delayed(widget.duration, () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _ctrl,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: widget.background,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 18, color: widget.foreground),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color: widget.foreground,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
