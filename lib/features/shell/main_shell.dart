import '../../core/widgets/scroll_edge_fade.dart';
import '../../core/theme/app_overlays.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';
import '../kasir/kasir_style.dart';
import '../../core/providers/laci_meja_provider.dart';
import '../../core/providers/license_provider.dart';
import '../../core/services/backup_reminder.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/app_nav_bar.dart';

class _TabItem {
  const _TabItem(this.path, this.label, this.kind);
  final String path;
  final String label;
  final AppIconKind kind;
}

const _allTabs = [
  _TabItem('/ringkasan', 'Ringkasan', AppIconKind.ringkasan),
  _TabItem('/kasir', 'Kasir', AppIconKind.kasir),
  _TabItem('/produk', 'Produk', AppIconKind.produk),
  _TabItem('/pelanggan', 'Pelanggan', AppIconKind.pelanggan),
  _TabItem('/laporan', 'Laporan', AppIconKind.laporan),
  _TabItem('/pengaturan', 'Pengaturan', AppIconKind.pengaturan),
];

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final _bottomBarKey = GlobalKey();
  OverlayEntry? _quickMenuEntry;

  @override
  void initState() {
    super.initState();
    // Item 13: pengingat backup berbasis "cek saat app dibuka" (sekali).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBackupReminder());
    // Item 25c: peringatan H-7 sebelum masa berlaku lisensi habis.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLicenseExpiry());
  }

  void _checkLicenseExpiry() {
    final days = ref.read(licenseProvider).daysUntilExpiry;
    if (days == null || days < 0 || days > 7) return;
    ScaffoldMessenger.of(context).showAppSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(days == 0
          ? 'Aktivasi berakhir hari ini — hubungi developer untuk perpanjang.'
          : 'Aktivasi akan berakhir dalam $days hari — hubungi developer '
              'untuk perpanjang.'),
    ));
  }

  Future<void> _checkBackupReminder() async {
    final status = await BackupReminder.load(ref.read(databaseProvider));
    if (!mounted || !status.overdue) return;
    final days = status.daysSince;
    ScaffoldMessenger.of(context).showAppSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(days == null
          ? 'Data belum pernah dicadangkan. Backup sekarang?'
          : 'Sudah $days hari belum backup. Cadangkan sekarang?'),
      action: SnackBarAction(
        label: 'Backup',
        onPressed: () => context.push('/pengaturan/backup'),
      ),
    ));
  }

  @override
  void dispose() {
    _quickMenuEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider);
    // Tab Laporan disembunyikan dari kasir.
    final tabs = device.canSeeReports
        ? _allTabs
        : _allTabs.where((t) => t.path != '/laporan').toList();

    final location = GoRouterState.of(context).matchedLocation;
    var selected = tabs.indexWhere((t) => location.startsWith(t.path));
    if (selected < 0) selected = 0;

    final kasirIndex = tabs.indexWhere((t) => t.path == '/kasir');
    final laciMejaCount = ref.watch(laciMejaOpenCountProvider).valueOrNull ?? 0;

    // Kasir gaya Baru: keyboard TIDAK mengecilkan layar - cart bar tetap di
    // bawah (tertutup keyboard), kolom cari tidak digeser. Mengecilkan body
    // membuat landing di-layout ulang tiap frame selama keyboard naik (terasa
    // lag di HP uji). Hanya tab Kasir persis ('/kasir'); sub-rute (bayar,
    // laci meja, dst.) tetap mengecil seperti biasa untuk kolom isiannya.
    final shellResize = shellResizesForKeyboard(
      onKasirTab: location == '/kasir',
      modernStyle: ref.watch(kasirStyleProvider) == KasirStyle.modern,
    );

    return Scaffold(
      resizeToAvoidBottomInset: shellResize,
      // Item 21 (Fase 1) — status sync dulu tampil sbg banner tunggal di
      // sini, di ATAS setiap layar tab (termasuk di atas toolbar/AppBar
      // masing-masing). Follow-up user: posisinya harus "inline" spt
      // notifikasi lain (di BAWAH header tiap tab, sejajar dgn `InlineBanner`
      // yg sudah ada) — jadi `SyncStatusBanner` sekarang dipasang LANGSUNG di
      // tiap layar tab (`RingkasanScreen`/`KasirScreen`/`ProdukListScreen`/
      // `PelangganListScreen`/`LaporanScreen`/`PengaturanScreen`), bukan di
      // sini lagi. `SyncScreen` sendiri (sub-halaman Pengaturan) TIDAK
      // dipasangi (sudah tampil penuh di badan layarnya sendiri).
      // Tepi bawah memudar ke latar (bukan terpotong tegas di atas nav);
      // tab Kasir punya cart bar melayang sendiri -> tanpa pemudaran.
      body: ScrollEdgeFade(
          bottom: location == '/kasir' ? 0 : 26, child: widget.child),
      bottomNavigationBar: Stack(
        key: _bottomBarKey,
        children: [
          AppNavBar(
            selected: selected,
            onSelect: (i) => context.go(tabs[i].path),
            items: [
              for (final t in tabs)
                AppNavItem(t.kind, t.label,
                    badge: t.path == '/kasir' ? laciMejaCount : 0),
            ],
          ),
          // Item 52 ("Laci Meja") — tekan-tahan tab Kasir (ala Telegram)
          // membuka menu cepat Kasir/Laci Meja. `translucent`: tap singkat
          // tetap sampai ke tab di baliknya; tahan = perilaku TAMBAHAN.
          // `LongPressGestureRecognizer` durasi custom (250 ms) — GestureDetector
          // biasa selalu 500 ms.
          if (kasirIndex >= 0)
            Positioned.fill(
              child: LayoutBuilder(builder: (context, constraints) {
                // Area tab Kasir = lebar pil (maks 440, margin 12) / jumlah tab.
                final barW = (constraints.maxWidth - 24).clamp(0.0, 440.0);
                final itemWidth = barW / tabs.length;
                final left = (constraints.maxWidth - barW) / 2 +
                    itemWidth * kasirIndex;
                return Stack(children: [
                  Positioned(
                    left: left,
                    width: itemWidth,
                    top: 4,
                    height: AppNavBar.height,
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.translucent,
                      gestures: {
                        LongPressGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                                LongPressGestureRecognizer>(
                          () => LongPressGestureRecognizer(
                              duration: const Duration(milliseconds: 250)),
                          (instance) {
                            instance.onLongPressStart = (details) =>
                                _showLaciMejaMenu(details.globalPosition);
                          },
                        ),
                      },
                    ),
                  ),
                ]);
              }),
            ),
        ],
      ),
    );
  }

  /// Redesain (permintaan user): menu cepat Kasir/Laci Meja SEKARANG
  /// - muncul DI ATAS tab Kasir (bukan showMenu bawaan yg posisinya dihitung
  //    dari titik jari & bisa nongol ke SAMPING);
  /// - HANYA ikon (tanpa label teks "Buka Kasir"/"Buka Laci Meja");
  /// - sudut rounded (bukan kotak persegi bawaan `PopupMenuItem`);
  /// - animasi muncul/hilang smooth (bukan langsung nongol/hilang rigid) —
  ///   lihat `_QuickMenuPopup`.
  /// Dibangun sbg `OverlayEntry` custom (bukan `showMenu`) supaya posisi
  /// horizontal/vertikalnya bisa dikontrol persis relatif thd bottom bar.
  void _showLaciMejaMenu(Offset globalPosition) {
    _quickMenuEntry?.remove();
    final laciMejaCount = ref.read(laciMejaOpenCountProvider).valueOrNull ?? 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final barBox = _bottomBarKey.currentContext!.findRenderObject() as RenderBox;
    final barTop = barBox.localToGlobal(Offset.zero).dy;

    const menuWidth = 108.0;
    const menuHeight = 52.0;
    final left = (globalPosition.dx - menuWidth / 2)
        .clamp(8.0, screenWidth - menuWidth - 8.0);

    void remove() {
      _quickMenuEntry?.remove();
      _quickMenuEntry = null;
    }

    void select(String? selection) {
      if (!mounted || selection == null) return;
      if (selection == 'kasir') {
        context.go('/kasir');
      } else if (selection == 'laci_meja') {
        context.push('/kasir/laci-meja');
      }
    }

    _quickMenuEntry = OverlayEntry(
      builder: (_) => _QuickMenuPopup(
        left: left,
        top: barTop - menuHeight - 8,
        menuHeight: menuHeight,
        cs: cs,
        isDark: isDark,
        laciMejaCount: laciMejaCount,
        onRemove: remove,
        onSelect: select,
      ),
    );
    Overlay.of(context).insert(_quickMenuEntry!);
  }
}

/// Bungkus animasi fade+scale utk menu cepat — permintaan user: transisi
/// muncul/hilang harus smooth, bukan langsung nongol/hilang tanpa animasi.
/// `onRemove` (lepas `OverlayEntry` dari overlay) dipanggil SETELAH animasi
/// keluar selesai, `onSelect` (navigasi) baru dipanggil setelah itu — supaya
/// urutan animasi-keluar lalu navigasi terasa natural, bukan navigasi duluan
/// baru overlay hilang mendadak.
class _QuickMenuPopup extends StatefulWidget {
  const _QuickMenuPopup({
    required this.left,
    required this.top,
    required this.menuHeight,
    required this.cs,
    required this.isDark,
    required this.laciMejaCount,
    required this.onRemove,
    required this.onSelect,
  });

  final double left;
  final double top;
  final double menuHeight;
  final ColorScheme cs;
  final bool isDark;
  final int laciMejaCount;
  final VoidCallback onRemove;
  final void Function(String? selection) onSelect;

  @override
  State<_QuickMenuPopup> createState() => _QuickMenuPopupState();
}

class _QuickMenuPopupState extends State<_QuickMenuPopup>
    with SingleTickerProviderStateMixin {
  // Ala popup Telegram: 150 ms + 16 ms per item (2 item), tumbuh dari titik
  // pemicu (tab di bawahnya), keluar lebih singkat.
  late final _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 182),
      reverseDuration: const Duration(milliseconds: 120));
  late final _scale = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.easeOutQuint,
      reverseCurve: AppMotion.easeIn.flipped);
  late final _fade =
      CurvedAnimation(parent: _controller, curve: AppMotion.easeOut);

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close(String? selection) async {
    await _controller.reverse();
    widget.onRemove();
    widget.onSelect(selection);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _close(null),
          ),
        ),
        Positioned(
          left: widget.left,
          top: widget.top,
          child: FadeTransition(
            key: const Key('quickMenuFade'),
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              alignment: Alignment.bottomCenter,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Material(
                  color: widget.cs.surfaceContainerHigh,
                  elevation: 8,
                  child: SizedBox(
                    height: widget.menuHeight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _QuickMenuIcon(
                          icon: Icons.point_of_sale_outlined,
                          color: widget.cs.primary,
                          tooltip: 'Buka Kasir',
                          onTap: () => _close('kasir'),
                        ),
                        Container(
                            width: 1,
                            height: 28,
                            color: widget.cs.outlineVariant),
                        _QuickMenuIcon(
                          icon: Icons.inbox_outlined,
                          color: AppTheme.laciFg(widget.isDark),
                          tooltip: 'Buka Laci Meja',
                          badgeCount: widget.laciMejaCount,
                          onTap: () => _close('laci_meja'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickMenuIcon extends StatelessWidget {
  const _QuickMenuIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon, color: color, size: 24);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: badgeCount > 0
              ? Badge(label: Text('$badgeCount'), child: child)
              : child,
        ),
      ),
    );
  }
}

/// Apakah `Scaffold` shell boleh mengecilkan body saat keyboard muncul. Normal
/// true; false HANYA di tab Kasir ('/kasir') bergaya Baru.
bool shellResizesForKeyboard({
  required bool onKasirTab,
  required bool modernStyle,
}) =>
    !(onKasirTab && modernStyle);
