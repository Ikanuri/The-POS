import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_theme.dart';

/// Pemilih nilai bergaya "revolver" (seperti stepper qty di Kasir): angka
/// besar di dalam pil, geser KIRI untuk menaikkan & KANAN untuk menurunkan;
/// angka berputar (meluncur) tiap pindah langkah + haptik halus. Tap di kiri/
/// kanan pil = geser satu langkah (aksesibilitas / tanpa geser).
class RevolverPicker extends StatefulWidget {
  const RevolverPicker({
    super.key,
    required this.count,
    required this.index,
    required this.labelOf,
    required this.onChanged,
    this.pxPerStep = 22,
    this.width = 128,
  });

  final int count;
  final int index;
  final String Function(int index) labelOf;
  final ValueChanged<int> onChanged;

  /// Jarak geser (px) per satu langkah.
  final double pxPerStep;
  final double width;

  @override
  State<RevolverPicker> createState() => _RevolverPickerState();
}

class _RevolverPickerState extends State<RevolverPicker> {
  double _acc = 0;
  int _dir = 1; // arah putaran terakhir (1 = naik)

  void _go(int to) {
    final t = to.clamp(0, widget.count - 1);
    if (t == widget.index) return;
    _dir = t > widget.index ? 1 : -1;
    HapticFeedback.selectionClick();
    widget.onChanged(t);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final on = widget.index > 0;
    return GestureDetector(
      key: const Key('revolver-picker'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _acc = 0,
      onHorizontalDragUpdate: (d) {
        // Geser kiri (delta negatif) = naik, seperti revolver qty.
        _acc -= d.delta.dx;
        while (_acc >= widget.pxPerStep) {
          _acc -= widget.pxPerStep;
          _go(widget.index + 1);
        }
        while (_acc <= -widget.pxPerStep) {
          _acc += widget.pxPerStep;
          _go(widget.index - 1);
        }
      },
      child: Container(
        width: widget.width,
        height: 44,
        decoration: BoxDecoration(
          color: on
              ? AppTheme.accent.withOpacity(dark ? 0.22 : 0.12)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: on ? AppTheme.accent.withOpacity(0.5) : cs.outlineVariant,
              width: 0.75),
        ),
        child: Row(
          children: [
            _Edge(
                key: const Key('revolver-prev'),
                icon: Icons.chevron_left_rounded,
                enabled: widget.index > 0,
                onTap: () => _go(widget.index - 1)),
            Expanded(
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: AppMotion.dur(context, AppMotion.fast),
                  transitionBuilder: (child, anim) {
                    final incoming = child.key == ValueKey(widget.index);
                    final from = Offset(incoming ? _dir * 0.6 : -_dir * 0.6, 0);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position:
                            Tween(begin: from, end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    );
                  },
                  child: Center(
                    key: ValueKey(widget.index),
                    child: Text(
                      widget.labelOf(widget.index),
                      style: AppTheme.numStyle(context,
                          size: 15.5,
                          weight: FontWeight.w600,
                          color: on ? AppTheme.accent : cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
            _Edge(
                key: const Key('revolver-next'),
                icon: Icons.chevron_right_rounded,
                enabled: widget.index < widget.count - 1,
                onTap: () => _go(widget.index + 1)),
          ],
        ),
      ),
    );
  }
}

class _Edge extends StatelessWidget {
  const _Edge(
      {super.key,
      required this.icon,
      required this.enabled,
      required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: enabled ? onTap : null,
        radius: 20,
        child: SizedBox(
          width: 30,
          height: 44,
          child: Icon(icon,
              size: 20,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withOpacity(enabled ? 0.9 : 0.25)),
        ),
      );
}
