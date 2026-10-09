import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Meter frame kecil (diagnostik): tiap 2 detik menampilkan jumlah frame,
/// rata-rata & terburuk waktu BUILD dan RASTER (ms) serta persen frame patah
/// (total > anggaran frame ~16,7 ms). Hanya dipasang saat saklar `meter`
/// menyala, jadi tidak membebani build normal.
class FrameMeter extends StatefulWidget {
  const FrameMeter({super.key});

  @override
  State<FrameMeter> createState() => _FrameMeterState();
}

class _FrameMeterState extends State<FrameMeter> {
  final List<FrameTiming> _buf = [];
  Timer? _timer;
  String _text = 'mengukur…';

  void _onTimings(List<FrameTiming> t) => _buf.addAll(t);

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final frames = List<FrameTiming>.of(_buf);
    _buf.clear();
    if (frames.isEmpty) {
      setState(() => _text = 'diam (0 frame)');
      return;
    }
    double ms(Duration d) => d.inMicroseconds / 1000.0;
    final build = frames.map((f) => ms(f.buildDuration)).toList();
    final raster = frames.map((f) => ms(f.rasterDuration)).toList();
    final total = frames.map((f) => ms(f.totalSpan)).toList();
    double avg(List<double> l) => l.reduce((a, b) => a + b) / l.length;
    double mx(List<double> l) => l.reduce((a, b) => a > b ? a : b);
    final jank = total.where((t) => t > 16.7).length * 100 / frames.length;
    setState(() => _text = '${frames.length} frm/2s\n'
        'build  ${avg(build).toStringAsFixed(1)} / ${mx(build).toStringAsFixed(0)} ms\n'
        'raster ${avg(raster).toStringAsFixed(1)} / ${mx(raster).toStringAsFixed(0)} ms\n'
        'patah  ${jank.toStringAsFixed(0)}%');
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xCC000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            height: 1.25,
            fontFamily: 'monospace',
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
