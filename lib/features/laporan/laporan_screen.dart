import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../shell/sync_status_banner.dart';
import 'report_export.dart';
import 'tabs/ringkasan_tab.dart';
import 'tabs/produk_tab.dart';
import 'tabs/pelanggan_tab.dart';
import 'tabs/transaksi_tab.dart';
import 'tabs/hutang_tab.dart';
import 'tabs/stok_tab.dart';
import 'tabs/pengeluaran_tab.dart';
import 'tabs/arus_kas_tab.dart';

final dateRangeProvider = StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, now.day),
    end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
  );
});

class LaporanScreen extends ConsumerStatefulWidget {
  const LaporanScreen({super.key});

  @override
  ConsumerState<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends ConsumerState<LaporanScreen>
    with SingleTickerProviderStateMixin {
  // Item 49d — "Pengeluaran", lalu "Arus Kas", ditambah di PALING AKHIR
  // (bukan disisipkan di tengah) supaya index tab 0-3 yg SUDAH dipakai
  // `ReportTab.values[index]` tetap sama persis, tak perlu ubah pemetaan
  // lama. "Hutang"/"Stok"/"Pengeluaran"/"Arus Kas" (index 4-7) sekarang
  // SEMUA punya padanan `ReportTab` juga (permintaan user: tambahkan
  // ekspor PDF/Excel ke tab yang belum punya) — lihat `report_export.dart`.
  late final TabController _tabController =
      TabController(length: 8, vsync: this);
  final _exportButtonKey = GlobalKey();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(dateRangeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              '${_fmt(range.start)} – ${_fmt(range.end)}',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => _pickRange(context, range),
          ),
          IconButton(
            key: _exportButtonKey,
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export tab ini',
            onPressed: () => _showExportMenu(range),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          // Permintaan user (screenshot beranotasi panah ke-2) — gap yang
          // dimaksud SEJAK AWAL bukan jarak vertikal ke kartu KPI (2
          // percobaan sebelumnya salah sasaran), tapi jarak HORIZONTAL di
          // KIRI tab "Ringkasan" itu sendiri. Akar: `TabBar(isScrollable:
          // true)` Material 3 defaultnya `TabAlignment.startOffset` — inset
          // ~52dp di depan tab pertama (dirancang utk sejajar dgn leading
          // icon/drawer, TIDAK relevan di sini krn AppBar ini tanpa leading
          // icon). `TabAlignment.start` menempelkan tab pertama flush ke
          // kiri (sejajar judul "Laporan" di atasnya).
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Ringkasan'),
            Tab(text: 'Produk'),
            Tab(text: 'Pelanggan'),
            Tab(text: 'Transaksi'),
            Tab(text: 'Hutang'),
            Tab(text: 'Stok'),
            Tab(text: 'Pengeluaran'),
            Tab(text: 'Arus Kas'),
          ],
        ),
      ),
      body: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                RingkasanTab(range: range),
                ProdukTab(range: range),
                PelangganTab(range: range),
                TransaksiTab(range: range),
                const HutangTab(),
                const StokTab(),
                PengeluaranTab(range: range),
                ArusKasTab(range: range),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _tabName(int i) => const [
        'Ringkasan',
        'Produk',
        'Pelanggan',
        'Transaksi',
        'Hutang',
        'Stok',
        'Pengeluaran',
        'Arus Kas',
      ][i];

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';

  /// Dropdown ekspor custom (bukan `PopupMenuButton` bawaan) — 2 chip
  /// PDF/Excel, tiap chip py 2 zona tap independen (badan chip = unduh ke
  /// HP, ikon share = bagikan langsung tanpa nangkring lokal). `showMenu`
  /// dgn `PopupMenuItem(enabled: false, ...)` supaya `InkWell` bawaan item
  /// tidak ikut menelan tap — chip sendiri yang pop() dgn nilai
  /// `(aksi, format)`, baru dieksekusi SETELAH menu tertutup.
  Future<void> _showExportMenu(DateTimeRange range) async {
    final box =
        _exportButtonKey.currentContext!.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<(String action, String format)>(
      context: context,
      position: position,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        PopupMenuItem<(String action, String format)>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _ExportChipsPanel(tabName: _tabName(_tabController.index)),
        ),
      ],
    );
    if (result == null || !mounted) return;
    final (action, format) = result;
    if (action == 'share') {
      await _share(range, format);
    } else {
      await _export(range, format);
    }
  }

  Future<void> _export(DateTimeRange range, String format) async {
    final device = ref.read(deviceProvider);
    final tab = ReportTab.values[_tabController.index];
    // Indikasi proses untuk ekspor yang melibatkan tangkapan grafik.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 1),
        content: Text('Menyiapkan laporan ${_tabName(_tabController.index)}…'),
      ));
    await exportReport(
      context: context,
      ref: ref,
      range: range,
      tab: tab,
      format: format,
      storeName: device.storeName,
    );
  }

  Future<void> _share(DateTimeRange range, String format) async {
    final device = ref.read(deviceProvider);
    final tab = ReportTab.values[_tabController.index];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 1),
        content: Text('Menyiapkan laporan ${_tabName(_tabController.index)}…'),
      ));
    await shareReport(
      context: context,
      ref: ref,
      range: range,
      tab: tab,
      format: format,
      storeName: device.storeName,
    );
  }

  Future<void> _pickRange(BuildContext context, DateTimeRange current) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: current,
    );
    if (picked != null) {
      ref.read(dateRangeProvider.notifier).state = DateTimeRange(
        start:
            DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
      );
    }
  }
}

/// Panel dropdown ekspor custom (permintaan user: "bukan default template
/// flutter") — dua chip berdampingan (PDF badge merah, Excel badge hijau),
/// masing-masing punya 2 zona tap terpisah lihat `_ExportFormatChip`.
class _ExportChipsPanel extends StatelessWidget {
  const _ExportChipsPanel({required this.tabName});
  final String tabName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              'Export $tabName',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 6),
          const _ExportFormatChip(
            format: 'pdf',
            badgeColor: Color(0xFFDC3545),
            icon: Icons.picture_as_pdf_rounded,
            label: 'PDF',
          ),
          const SizedBox(height: 8),
          const _ExportFormatChip(
            format: 'xlsx',
            badgeColor: Color(0xFF1D6F42),
            icon: Icons.grid_on_rounded,
            label: 'Excel',
          ),
        ],
      ),
    );
  }
}

/// Satu chip format ekspor (PDF ATAU Excel) dgn 2 zona tap independen:
/// - Badan chip (badge + label) → unduh ke penyimpanan HP (`FilePicker.
///   saveFile`, perilaku lama).
/// - Ikon share (dipisah garis vertikal tipis) → bagikan langsung lewat
///   share sheet OS, TANPA nangkring di penyimpanan lokal dulu.
///
/// Keduanya pop() menu dgn `(aksi, format)` — `LaporanScreen._showExportMenu`
/// yang mengeksekusi aksi SETELAH menu tertutup, chip ini murni UI +
/// pemilihan aksi (mudah diuji tanpa menyentuh plugin native sungguhan).
class _ExportFormatChip extends StatelessWidget {
  const _ExportFormatChip({
    required this.format,
    required this.badgeColor,
    required this.icon,
    required this.label,
  });

  final String format;
  final Color badgeColor;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 230,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: InkWell(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(12)),
              onTap: () =>
                  Navigator.of(context).pop(('download', format)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 17, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          Text('Unduh ke HP',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 34, color: scheme.outlineVariant),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(12)),
              onTap: () => Navigator.of(context).pop(('share', format)),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.ios_share_rounded,
                    size: 18, color: scheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
