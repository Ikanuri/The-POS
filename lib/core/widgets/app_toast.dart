import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'app_notice_card.dart';

export 'app_notice_card.dart' show ToastTone;

class _ToastData {
  _ToastData({
    required this.id,
    this.message,
    this.content,
    required this.tone,
    this.actionLabel,
    this.onAction,
    required this.duration,
  });

  final int id;
  final String? message;

  /// Dipakai bila [message] tidak ada (isi SnackBar yang tak bisa diekstrak).
  final Widget? content;
  final ToastTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
}

/// Toast gaya baru: kartu putih membulat di BAGIAN ATAS layar (di bawah status
/// bar). API statis tanpa context; dirender oleh [AppToastHost] yang dipasang
/// sekali di `MaterialApp.builder`. Satu toast pada satu waktu — yang baru
/// menggantikan yang lama.
class AppToast {
  AppToast._();

  /// Diset true oleh [AppToastHost] selama terpasang. Bila false (mis. test
  /// dgn MaterialApp polos) `showAppSnackBar` jatuh ke SnackBar bawaan.
  static bool hostMounted = false;

  static final ValueNotifier<_ToastData?> _current = ValueNotifier(null);
  static int _seq = 0;

  static const defaultDuration = Duration(seconds: 3);
  static const actionDuration = Duration(seconds: 5);

  static void show({
    String? message,
    Widget? content,
    ToastTone tone = ToastTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    assert(message != null || content != null);
    HapticFeedback.selectionClick();
    _current.value = _ToastData(
      id: ++_seq,
      message: message,
      content: content,
      tone: tone,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration ??
          (actionLabel != null ? actionDuration : defaultDuration),
    );
  }

  static void hide() => _current.value = null;
}

/// Pasang SEKALI di atas `child` navigator (lihat `lib/main.dart`).
class AppToastHost extends StatefulWidget {
  const AppToastHost({super.key, required this.child});
  final Widget child;

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this);
  Timer? _timer;
  _ToastData? _shown;

  static const _exitDuration = Duration(milliseconds: 175);

  @override
  void initState() {
    super.initState();
    AppToast.hostMounted = true;
    AppToast._current.addListener(_onChanged);
    _ctl.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && AppToast._current.value == null) {
        if (mounted && _shown != null) setState(() => _shown = null);
      }
    });
    if (AppToast._current.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged());
    }
  }

  @override
  void dispose() {
    AppToast.hostMounted = false;
    AppToast._current.removeListener(_onChanged);
    // Toast lama tidak boleh "bocor" ke host berikutnya.
    AppToast._current.value = null;
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final data = AppToast._current.value;
    _timer?.cancel();
    if (data != null) {
      setState(() => _shown = data);
      _ctl.duration = AppMotion.dur(context, AppMotion.medium);
      _ctl.forward(from: 0);
      _timer = Timer(data.duration, () {
        if (AppToast._current.value?.id == data.id) AppToast.hide();
      });
    } else {
      _ctl.reverseDuration = AppMotion.dur(context, _exitDuration);
      _ctl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _shown;
    return Stack(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      children: [
        Positioned.fill(child: widget.child),
        if (data != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              minimum: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _animated(data),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _animated(_ToastData data) {
    final curved = CurvedAnimation(
      parent: _ctl,
      curve: AppMotion.easeOutQuint,
      reverseCurve: AppMotion.easeIn,
    );
    return FadeTransition(
      opacity: _ctl,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.7), end: Offset.zero)
            .animate(curved),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) {
            if (d.delta.dy < -2) AppToast.hide();
          },
          child: Semantics(
            liveRegion: true,
            container: true,
            child: _ToastCard(key: ValueKey(data.id), data: data),
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({super.key, required this.data});
  final _ToastData data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final style = ToastToneStyle.of(data.tone, isDark);
    final ink = isDark ? const Color(0xFFECE7DD) : const Color(0xFF2A2824);
    final textStyle = TextStyle(
      color: ink,
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );

    final body = data.message != null
        ? Text(data.message!,
            maxLines: 3, overflow: TextOverflow.ellipsis, style: textStyle)
        : DefaultTextStyle.merge(style: textStyle, child: data.content!);

    return Material(
      type: MaterialType.transparency,
      child: AppNoticeCard(
        key: const Key('app_toast'),
        tone: data.tone,
        trailing: data.actionLabel == null
            ? null
            : InkWell(
                key: const Key('app_toast_action'),
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  data.onAction?.call();
                  AppToast.hide();
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: style.bg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    data.actionLabel!,
                    style: TextStyle(
                      color: data.tone == ToastTone.info
                          ? AppTheme.accent
                          : style.fg,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
        child: body,
      ),
    );
  }
}
