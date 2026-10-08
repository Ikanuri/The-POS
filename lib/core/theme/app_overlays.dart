import 'package:flutter/material.dart';

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
