import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_motion.dart';
import '../theme/app_style.dart';

/// Perangkat grafik bersama — diadaptasi dari pola grafik statistik Telegram
/// (org.telegram.ui.Charts): 5 garis bantu angka-bulat dengan label SINGKAT di
/// atas garis (bukan lajur sumbu), skala yang bergerak halus saat data
/// berubah, batang terpilih menonjol sementara yang lain meredup, kartu
/// tooltip melayang yang pindah sisi di tengah, penanda titik berhalo, dan
/// haptik halus tiap pindah indeks. Lihat docs/DESAIN-REFERENSI-TELEGRAM.md §
/// Grafik.

/// Singkatan angka gaya Indonesia: 950, 1,5 rb, 250 rb, 1,2 jt, 3 M (miliar),
/// 2 T (triliun) — padanan `formatWholeNumber` Telegram (K/M/B).
String abbrevNumber(num v) {
  final neg = v < 0;
  var a = v.abs().toDouble();
  const units = ['', ' rb', ' jt', ' M', ' T'];
  var i = 0;
  while (a >= 1000 && i < units.length - 1) {
    a /= 1000;
    i++;
  }
  String t;
  if (i == 0) {
    t = a == a.roundToDouble() ? a.toInt().toString() : a.toStringAsFixed(1);
  } else {
    final r = (a * 10).floor() / 10; // 1 desimal, dipotong (bukan dibulatkan)
    t = r == r.roundToDouble()
        ? r.toInt().toString()
        : r.toStringAsFixed(1).replaceAll('.', ',');
  }
  return '${neg ? '-' : ''}$t${units[i]}';
}

/// Skala sumbu angka-bulat: 5 interval sama. Mengembalikan (batas atas, langkah).
/// Langkah dipilih dari {1, 2, 2,5, 5, 10} x 10^k agar label mudah dibaca
/// (aturan `ChartHorizontalLinesData` Telegram: step = ceil(max/5) dibulatkan).
({double max, double step}) niceAxis(num dataMax) {
  if (dataMax <= 0) return (max: 5, step: 1);
  final raw = dataMax / 5;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    final step = m * mag;
    if (step >= raw - 1e-9) return (max: step * 5, step: step);
  }
  return (max: 10 * mag * 5, step: 10 * mag);
}

/// Haptik halus tiap pindah indeks (Telegram: `runSmoothHaptic`).
void chartTick() => HapticFeedback.selectionClick();

/// Garis bantu + label singkat DI ATAS garis, rata kiri di dalam area grafik
/// (Telegram `drawHorizontalLines` + `drawSignaturesToHorizontalLines`).
class ChartGridPainter extends CustomPainter {
  ChartGridPainter({
    required this.maxValue,
    required this.step,
    required this.label,
    required this.lineColor,
    required this.textColor,
    this.top = 14,
    this.bottom = 22,
  });

  final double maxValue; // nilai di tepi atas area plot (animasi)
  final double step;
  final String Function(num) label;
  final Color lineColor;
  final Color textColor;
  final double top;
  final double bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final plotH = size.height - top - bottom;
    if (plotH <= 0 || maxValue <= 0 || step <= 0) return;
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 5; i++) {
      final v = step * i;
      final y = size.height - bottom - plotH * (v / maxValue);
      if (y < top - 1) continue;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      if (i == 0) continue;
      final tp = TextPainter(
        text: TextSpan(
            text: label(v), style: TextStyle(fontSize: 11, color: textColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height - 1));
    }
  }

  @override
  bool shouldRepaint(ChartGridPainter oldDelegate) =>
      oldDelegate.maxValue != maxValue ||
      oldDelegate.step != step ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.textColor != textColor;
}

/// Kartu tooltip gaya Telegram: judul tebal + baris berwarna, bayangan lembut.
class ChartTooltipCard extends StatelessWidget {
  const ChartTooltipCard({super.key, required this.title, required this.rows});

  final String title;
  final List<({Color color, String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2623) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant, width: 0.75),
        boxShadow: AppStyle.floatShadow(dark),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          for (final r in rows) ...[
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: r.color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              if (r.label.isNotEmpty)
                Text('${r.label}  ',
                    style:
                        TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              Text(r.value,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: r.color)),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Satu kelompok batang (satu tanggal/kategori) pada [AppBarChart].
class BarGroup {
  const BarGroup({
    required this.xLabel,
    required this.title,
    required this.values,
  });

  /// Label sumbu-X singkat (mis. "12/10").
  final String xLabel;

  /// Judul tooltip (mis. "Senin, 12 Okt").
  final String title;

  /// Satu nilai per seri.
  final List<double> values;
}

class BarSeries {
  const BarSeries(this.label, this.color);
  final String label;
  final Color color;
}

/// Diagram batang gaya Telegram: garis bantu + label singkat, batang membulat,
/// sentuh/geser memilih kelompok (yang lain meredup), tooltip melayang, haptik.
class AppBarChart extends StatefulWidget {
  const AppBarChart({
    super.key,
    required this.groups,
    required this.series,
    required this.valueLabel,
    this.axisLabel = abbrevNumber,
    this.height = 150,
  });

  final List<BarGroup> groups;
  final List<BarSeries> series;
  final String Function(num) valueLabel;
  final String Function(num) axisLabel;
  final double height;

  @override
  State<AppBarChart> createState() => _AppBarChartState();
}

class _AppBarChartState extends State<AppBarChart>
    with SingleTickerProviderStateMixin {
  static const _top = 14.0;
  static const _bottom = 22.0;

  late final AnimationController _sel =
      AnimationController(vsync: this, duration: AppMotion.base);
  int? _selected;
  bool _downWasSelected = false;

  @override
  void dispose() {
    _sel.dispose();
    super.dispose();
  }

  int? _indexAt(double dx, double width) {
    final n = widget.groups.length;
    if (n == 0 || width <= 0) return null;
    return (dx / width * n).floor().clamp(0, n - 1);
  }

  void _select(int? i) {
    if (i == _selected) return;
    if (i != null) chartTick();
    setState(() => _selected = i);
    if (i == null) {
      _sel.reverse();
    } else {
      _sel.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = widget.groups;
    final n = groups.length;
    final dataMax = groups.fold<double>(
        0, (m, g) => g.values.fold(m, (a, b) => math.max(a, b)));
    final axis = niceAxis(dataMax);

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Sentuh = pilih seketika; ketuk lagi pada yang SAMA = batalkan.
          onTapDown: (d) {
            final i = _indexAt(d.localPosition.dx, w);
            _downWasSelected = i == _selected;
            if (!_downWasSelected) _select(i);
          },
          onTap: () {
            if (_downWasSelected) _select(null);
          },
          onHorizontalDragUpdate: (d) =>
              _select(_indexAt(d.localPosition.dx, w)),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: axis.max),
            duration: AppMotion.dur(context, const Duration(milliseconds: 400)),
            curve: Curves.fastOutSlowIn,
            builder: (context, maxAnim, _) => AnimatedBuilder(
              animation: _sel,
              builder: (context, _) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: ChartGridPainter(
                          maxValue: maxAnim,
                          step: axis.step,
                          label: widget.axisLabel,
                          lineColor: cs.outlineVariant.withOpacity(0.6),
                          textColor: cs.onSurfaceVariant.withOpacity(0.85),
                          top: _top,
                          bottom: _bottom,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _BarsPainter(
                          groups: groups,
                          series: widget.series,
                          maxValue: maxAnim,
                          selected: _selected,
                          dim: _sel.value,
                          labelColor: cs.onSurfaceVariant,
                          top: _top,
                          bottom: _bottom,
                        ),
                      ),
                    ),
                    if (_selected != null && _selected! < n)
                      _tooltip(context, w, n),
                  ],
                );
              },
            ),
          ),
        );
      }),
    );
  }

  Widget _tooltip(BuildContext context, double w, int n) {
    final g = widget.groups[_selected!];
    final cx = (_selected! + 0.5) / n * w;
    // Pindah sisi di tengah (Telegram `moveLegend`): kartu tidak menutupi batang.
    final right = cx > w / 2;
    return Positioned(
      top: 0,
      left: right ? null : math.min(cx + 8, w - 20),
      right: right ? math.min(w - cx + 8, w - 20) : null,
      child: IgnorePointer(
        child: Opacity(
          opacity: _sel.value,
          child: ChartTooltipCard(
            key: const Key('chart-tooltip'),
            title: g.title,
            rows: [
              for (var i = 0; i < widget.series.length; i++)
                (
                  color: widget.series[i].color,
                  label: widget.series.length > 1 ? widget.series[i].label : '',
                  value: widget.valueLabel(g.values[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.groups,
    required this.series,
    required this.maxValue,
    required this.selected,
    required this.dim,
    required this.labelColor,
    required this.top,
    required this.bottom,
  });

  final List<BarGroup> groups;
  final List<BarSeries> series;
  final double maxValue;
  final int? selected;
  final double dim; // 0..1 kekuatan peredupan non-terpilih
  final Color labelColor;
  final double top;
  final double bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final n = groups.length;
    if (n == 0 || maxValue <= 0) return;
    final plotH = size.height - top - bottom;
    final slot = size.width / n;
    final s = series.length;
    final gap = slot * 0.18;
    final barW = ((slot - gap) / s).clamp(1.0, 28.0);
    final groupW = barW * s;
    for (var i = 0; i < n; i++) {
      final x0 = slot * i + (slot - groupW) / 2;
      final isSel = selected == i;
      for (var k = 0; k < s; k++) {
        final v = groups[i].values[k];
        final h = (v / maxValue * plotH).clamp(v > 0 ? 2.0 : 0.0, plotH);
        var color = series[k].color;
        if (selected != null && !isSel) {
          color = color.withOpacity(1 - 0.68 * dim);
        }
        final r = Radius.circular(math.min(barW / 2, 5));
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x0 + k * barW, size.height - bottom - h,
                math.max(1, barW - (s > 1 ? 1 : 0)), h),
            topLeft: r,
            topRight: r,
          ),
          Paint()..color = color,
        );
      }
    }
    // Label X: <= ~6, memudar di tepi.
    final every = math.max(1, (n / 6).ceil());
    for (var i = 0; i < n; i += every) {
      final tp = TextPainter(
        text: TextSpan(
            text: groups[i].xLabel,
            style: TextStyle(fontSize: 10, color: labelColor)),
        textDirection: TextDirection.ltr,
      )..layout();
      final cx = slot * (i + 0.5);
      final x = (cx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x, size.height - bottom + 5));
    }
  }

  @override
  bool shouldRepaint(_BarsPainter oldDelegate) =>
      oldDelegate.groups != groups ||
      oldDelegate.maxValue != maxValue ||
      oldDelegate.selected != selected ||
      oldDelegate.dim != dim ||
      oldDelegate.labelColor != labelColor;
}

/// Irisan untuk [AppDonut].
class DonutSlice {
  const DonutSlice(this.label, this.value, this.color, this.onColor);
  final String label;
  final num value;
  final Color color;
  final Color onColor;
}

/// Donat bersama: sentuh irisan = irisan membesar + angka tengah berganti
/// (nama & persen), haptik tiap pindah; legenda di sisi kanan. Menggantikan
/// lima donat serupa yang tersebar di tab Laporan.
class AppDonut extends StatefulWidget {
  const AppDonut({
    super.key,
    required this.slices,
    this.size = 150,
    this.valueLabel,
    this.showLegend = true,
  });

  final List<DonutSlice> slices;

  /// false = hanya donat (dipakai bila daftar rincian sudah ada di bawahnya).
  final bool showLegend;
  final double size;

  /// Bila diberi, legenda menampilkan nilai di kanan tiap baris.
  final String Function(num)? valueLabel;

  @override
  State<AppDonut> createState() => _AppDonutState();
}

class _AppDonutState extends State<AppDonut> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slices = widget.slices;
    final total = slices.fold<double>(0, (a, s) => a + s.value.toDouble());
    final ring = widget.size * 0.18;
    final center = widget.size * 0.22;

    final sections = <PieChartSectionData>[];
    for (var i = 0; i < slices.length; i++) {
      final pct = total > 0 ? slices[i].value / total * 100 : 0.0;
      final small = pct < 8;
      final sel = _touched == i;
      sections.add(PieChartSectionData(
        value: slices[i].value.toDouble(),
        color: slices[i].color,
        title: total > 0 && !sel ? '${pct.round()}%' : '',
        radius: sel ? ring + 5 : ring,
        titlePositionPercentageOffset: small ? 1.4 : 0.5,
        titleStyle: TextStyle(
          fontSize: small ? 9 : 10.5,
          fontWeight: FontWeight.w700,
          color: small ? cs.onSurface : slices[i].onColor,
        ),
      ));
    }

    final sel = _touched != null && _touched! < slices.length
        ? slices[_touched!]
        : null;
    final selPct = sel != null && total > 0 ? sel.value / total * 100 : null;

    return Row(
      mainAxisAlignment: widget.showLegend
          ? MainAxisAlignment.start
          : MainAxisAlignment.center,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: center + 4,
                  sectionsSpace: 2,
                  sections: sections,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, resp) {
                      if (!event.isInterestedForInteractions) return;
                      final i = resp?.touchedSection?.touchedSectionIndex;
                      final next = (i == null || i < 0) ? null : i;
                      if (next != _touched) {
                        if (next != null) chartTick();
                        setState(() => _touched = next);
                      }
                    },
                  ),
                ),
                swapAnimationDuration:
                    AppMotion.dur(context, const Duration(milliseconds: 250)),
                swapAnimationCurve: Curves.fastOutSlowIn,
              ),
              IgnorePointer(
                child: sel == null
                    ? const SizedBox.shrink()
                    : SizedBox(
                        width: center * 1.7,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                '${selPct!.toStringAsFixed(selPct >= 10 ? 0 : 1)}%',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            Text(sel.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 9.5, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (widget.showLegend) const SizedBox(width: 14),
        if (widget.showLegend)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < slices.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: AnimatedOpacity(
                      duration: AppMotion.dur(context, AppMotion.fast),
                      opacity: _touched == null || _touched == i ? 1 : 0.45,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: slices[i].color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(slices[i].label,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: _touched == i
                                        ? FontWeight.w700
                                        : FontWeight.w400),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (widget.valueLabel != null)
                            Text(widget.valueLabel!(slices[i].value),
                                style: TextStyle(
                                    fontSize: 11, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
