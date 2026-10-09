import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_toast.dart';
import 'app_motion.dart';

/// Lembar bawah (bottom sheet) dengan animasi baku app: naik cepat lalu
/// mendarat halus (easeOutQuint, [AppMotion.medium]); turun lebih singkat.
/// Parameternya SAMA dgn `showModalBottomSheet` — pemanggil lama cukup ganti
/// nama. [sheetAnimationStyle] eksplisit menimpa bawaan. Pengguna yang
/// mematikan animasi di sistem mendapat durasi nol.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  double scrollControlDisabledMaxHeightRatio = 9.0 / 16.0,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
}) {
  final style = sheetAnimationStyle ??
      AnimationStyle(
        duration: AppMotion.dur(context, AppMotion.medium),
        reverseDuration: AppMotion.dur(context, AppMotion.base),
        curve: AppMotion.easeOutQuint,
        reverseCurve: AppMotion.easeIn,
      );
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    scrollControlDisabledMaxHeightRatio: scrollControlDisabledMaxHeightRatio,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    transitionAnimationController: transitionAnimationController,
    anchorPoint: anchorPoint,
    sheetAnimationStyle: style,
  );
}

/// Dialog dengan animasi baku app: memudar masuk sambil membesar halus
/// (0,94 -> 1, easeOutQuint); keluar lebih singkat. Parameternya SAMA dgn
/// `showDialog`.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(AppDialogRoute<T>(
    context: context,
    builder: builder,
    barrierColor:
        barrierColor ?? Theme.of(context).dialogTheme.barrierColor ?? Colors.black54,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    settings: routeSettings,
    themes: themes,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior:
        traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
  ));
}

/// Rute dialog dgn transisi app (lihat [showAppDialog]).
class AppDialogRoute<T> extends DialogRoute<T> {
  AppDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierColor,
    super.barrierDismissible,
    super.barrierLabel,
    super.useSafeArea,
    super.settings,
    super.anchorPoint,
    super.traversalEdgeBehavior,
  }) : _reduced = AppMotion.reduced(context);

  final bool _reduced;

  @override
  Duration get transitionDuration =>
      _reduced ? Duration.zero : AppMotion.medium;

  @override
  Duration get reverseTransitionDuration =>
      _reduced ? Duration.zero : AppMotion.fast;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (_reduced) return child;
    final eased = CurvedAnimation(
      parent: animation,
      curve: AppMotion.easeOutQuint,
      reverseCurve: AppMotion.easeIn,
    );
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: AppMotion.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(eased),
        child: child,
      ),
    );
  }
}

/// Notifikasi "toast" app. Bila [AppToastHost] terpasang (app sungguhan) isi
/// [SnackBar] diterjemahkan ke [AppToast] — kartu gaya baru di ATAS layar;
/// bila tidak (mis. test dgn MaterialApp polos) jatuh ke SnackBar bawaan
/// dgn animasi baku (muncul 260 ms easeOutQuint, keluar 175 ms). Pemanggil
/// lama cukup ganti `showSnackBar` → `showAppSnackBar`. Tak ada nilai
/// kembalian: toast ditutup lewat [AppToast.hide].
extension AppSnackBarX on ScaffoldMessengerState {
  void showAppSnackBar(SnackBar snackBar) {
    if (AppToast.hostMounted) {
      _showAsToast(snackBar);
      return;
    }
    HapticFeedback.selectionClick();
    showSnackBar(
      snackBar,
      snackBarAnimationStyle: AnimationStyle(
        duration: AppMotion.dur(context, AppMotion.medium),
        reverseDuration:
            AppMotion.dur(context, const Duration(milliseconds: 175)),
        curve: AppMotion.easeOutQuint,
        reverseCurve: AppMotion.easeIn,
      ),
    );
  }

  void _showAsToast(SnackBar snackBar) {
    final texts = <String>[];
    final icons = <IconData>[];
    _collectContent(snackBar.content, texts, icons);
    final message = texts.where((t) => t.trim().isNotEmpty).join(' ');

    var tone = ToastTone.info;
    final bg = snackBar.backgroundColor;
    if (bg != null) {
      if (bg == Theme.of(context).colorScheme.error || _isReddish(bg)) {
        tone = ToastTone.error;
      } else if (_isGreenish(bg)) {
        tone = ToastTone.success;
      }
    }
    if (tone == ToastTone.info) {
      for (final i in icons) {
        if (i == Icons.check_circle ||
            i == Icons.check_circle_rounded ||
            i == Icons.check_circle_outline ||
            i == Icons.check_rounded ||
            i == Icons.check) {
          tone = ToastTone.success;
          break;
        }
        if (i == Icons.error ||
            i == Icons.error_rounded ||
            i == Icons.error_outline ||
            i == Icons.warning_rounded ||
            i == Icons.warning_amber_rounded) {
          tone = ToastTone.error;
          break;
        }
      }
    }

    final action = snackBar.action;
    // SnackBar bawaan 4 dtk = "tidak diatur" -> pakai bawaan toast.
    final d = snackBar.duration;
    AppToast.show(
      message: message.isEmpty ? null : message,
      content: message.isEmpty ? snackBar.content : null,
      tone: tone,
      actionLabel: action?.label,
      onAction: action?.onPressed,
      duration: d == const Duration(seconds: 4) ? null : d,
    );
  }

  static bool _isReddish(Color c) => c.red >= 180 && c.green <= 80 && c.blue <= 80;
  static bool _isGreenish(Color c) => c.green >= 120 && c.red <= 90 && c.blue <= 120;

  /// Kumpulkan teks & ikon dari pohon sederhana (Text/Row/Column/Expanded/
  /// Flexible/Padding/Icon). Aman: widget lain diabaikan.
  static void _collectContent(Widget w, List<String> texts, List<IconData> icons) {
    if (w is Text) {
      final t = w.data ?? w.textSpan?.toPlainText();
      if (t != null) texts.add(t);
    } else if (w is Icon) {
      if (w.icon != null) icons.add(w.icon!);
    } else if (w is Row) {
      for (final c in w.children) {
        _collectContent(c, texts, icons);
      }
    } else if (w is Column) {
      for (final c in w.children) {
        _collectContent(c, texts, icons);
      }
    } else if (w is Expanded) {
      _collectContent(w.child, texts, icons);
    } else if (w is Flexible) {
      _collectContent(w.child, texts, icons);
    } else if (w is Padding && w.child != null) {
      _collectContent(w.child!, texts, icons);
    }
  }
}
