import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_style.dart';
import 'app_icons.dart';

class AppNavItem {
  const AppNavItem(this.kind, this.label, {this.badge = 0});
  final AppIconKind kind;
  final String label;

  /// >0 = tampilkan lencana hitungan.
  final int badge;
}

/// Bilah tab bawah MELAYANG ala Telegram: pil membulat penuh dengan margin di
/// semua sisi, indikator tab terpilih meluncur halus (320 ms easeOutQuint),
/// ikon garis (terpilih = duotone aksen) + label kecil, lencana beranimasi.
/// Tinggi 60dp, lebar maksimum 440dp di tengah.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<AppNavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  static const double height = 60;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final card = dark ? const Color(0xFF2A2623) : Colors.white;
    final inactive = dark ? const Color(0xFF8F887D) : const Color(0xFF8A8478);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 4, 12, 8 + bottom),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            key: const Key('app-nav-bar'),
            height: height,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(color: cs.outlineVariant, width: 0.75),
              boxShadow: AppStyle.floatShadow(dark),
            ),
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth / items.length;
              return Stack(
                children: [
                  // Indikator meluncur.
                  AnimatedPositioned(
                    key: const Key('app-nav-indicator'),
                    duration: AppMotion.dur(context, AppMotion.medium),
                    curve: AppMotion.easeOutQuint,
                    left: w * selected + 4,
                    top: 6,
                    width: w - 8,
                    height: height - 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(dark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular((height - 12) / 2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _NavCell(
                            item: items[i],
                            selected: i == selected,
                            inactive: inactive,
                            onTap: () {
                              if (i != selected) HapticFeedback.selectionClick();
                              onSelect(i);
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.inactive,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final Color inactive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : inactive;
    Widget icon = AppIcon(item.kind, color: color, filled: selected);
    if (item.badge > 0) {
      icon = Badge(
        label: Text('${item.badge}'),
        backgroundColor: const Color(0xFFC03A3A),
        textColor: Colors.white,
        child: icon,
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.06 : 1,
                duration: AppMotion.dur(context, AppMotion.base),
                curve: AppMotion.easeOutBack,
                child: icon,
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
