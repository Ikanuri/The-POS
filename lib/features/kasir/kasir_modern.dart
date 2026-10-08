part of 'kasir_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kasir gaya BARU (terinspirasi katalog HTML). Berkas ini `part` dari
// kasir_screen.dart supaya memakai logika kasir yang SAMA persis (scanner
// HID/kamera, quick-add, revolver, select-all pencarian, dst.) tanpa
// menduplikasinya; hanya TATA LETAK & tampilan yang berbeda dari Klasik.
// ─────────────────────────────────────────────────────────────────────────────

extension _KasirModernX on _KasirScreenState {
  /// Antrian pesanan ditahan (tombol pojok). Sementara memakai panel antrian
  /// yang sama dengan Klasik di dalam lembar bawah.
  void _openHeldSheet() {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: _HeldInlinePanel(
          onResume: (o) {
            Navigator.of(sheetCtx).pop();
            _onHeldCardTap(o);
          },
          busy: _isSwitchingHeld,
          onClose: () => Navigator.of(sheetCtx).pop(),
        ),
      ),
    );
  }

  Widget _buildModern(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cart = ref.watch(cartProvider(_cartId));
    final cartNotifier = ref.read(cartProvider(_cartId).notifier);
    final cartMeta = ref.watch(cartMetaProvider(_cartId));
    final query = ref.watch(_kasirSearchProvider(_cartId));
    final isGrid = ref.watch(kasirGridProvider);
    final selectedGroup = ref.watch(_kasirSelectedGroupProvider);
    final showAll = ref.watch(_kasirShowAllProvider(_cartId));
    final isLanding = query.isEmpty && selectedGroup == null && !showAll;
    final productsAsync =
        ref.watch(_kasirProductsProvider((query, selectedGroup)));

    void goHome() {
      _searchCtrl.clear();
      ref.read(_kasirSearchProvider(_cartId).notifier).state = '';
      ref.read(_kasirSelectedGroupProvider.notifier).state = null;
      ref.read(_kasirShowAllProvider(_cartId).notifier).state = false;
      _searchFocus.unfocus();
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _ModernBlobs(strong: isLanding)),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _ModernSearchStage(
                  isLanding: isLanding,
                  ctrl: _searchCtrl,
                  focus: _searchFocus,
                  onChanged: (v) => ref
                      .read(_kasirSearchProvider(_cartId).notifier)
                      .state = v,
                  onScan: _openScanner,
                ),
                if (!isLanding)
                  _KasirCategoryChipRow(showHome: true, onHome: goHome),
                Expanded(
                  // Tap/scroll di bawah kolom cari keluar dari fokus cari
                  // (teks tetap) — sama dengan Klasik; Listener (bukan
                  // GestureDetector) agar tap tetap sampai ke kartu produk.
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) {
                      if (_skipNextSearchCollapse) {
                        _skipNextSearchCollapse = false;
                        return;
                      }
                      _searchFocus.unfocus();
                    },
                    child: NotificationListener<ScrollStartNotification>(
                      onNotification: (_) {
                        _searchFocus.unfocus();
                        return false;
                      },
                      child: Column(
                        children: [
                          const SyncStatusBanner(),
                          InlineBanner(
                            message: _bannerMsg,
                            type: _bannerType,
                            duration: _bannerDuration,
                            onDismiss: () => _clearBanner(),
                          ),
                          Expanded(
                            child: isLanding
                                ? Padding(
                                    // Lorong untuk rail tombol pojok: tombol
                                    // "+" produk tidak tertutup.
                                    padding: const EdgeInsets.only(right: 64),
                                    child: _ModernLanding(
                                      cartId: _cartId,
                                      onShowAll: () => ref
                                          .read(_kasirShowAllProvider(_cartId)
                                              .notifier)
                                          .state = true,
                                      tileBuilder: (p) => _ProductListTile(
                                        product: p,
                                        cartId: _cartId,
                                        onTapBody: () => _openEntry(p),
                                        onQuickAdd: _quickAdd,
                                        onOpenEntry: () => _openEntry(p),
                                        onBeforeTap: _markSkipSearchCollapse,
                                        onAfterQtyChange:
                                            _highlightSearchIfActive,
                                      ),
                                    ),
                                  )
                                : _buildProductResults(
                                    context, productsAsync, query, isGrid),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: _ModernFab(
              isLanding: isLanding,
              isGrid: isGrid,
              dark: Theme.of(context).brightness == Brightness.dark,
              onToggleGrid: () => ref.read(kasirGridProvider.notifier).toggle(),
              onToggleTheme: () => ref.read(themeModeProvider.notifier).set(
                  Theme.of(context).brightness == Brightness.dark
                      ? ThemeMode.light
                      : ThemeMode.dark),
              actions: [
                _FabAction(
                  key: 'history',
                  icon: Icons.history_rounded,
                  label: 'Riwayat Transaksi',
                  onTap: () => showAppSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const TxHistorySheet(),
                  ),
                ),
                _FabAction(
                  key: 'held',
                  icon: Icons.pause_circle_outline_rounded,
                  label: 'Antrian Pesanan',
                  badge: ref.watch(_heldCountProvider).valueOrNull ?? 0,
                  onTap: _openHeldSheet,
                ),
                _FabAction(
                  key: 'paste',
                  icon: Icons.content_paste_go_rounded,
                  label: 'Tempel Pesanan',
                  onTap: () => showAppSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => PasteOrderSheet(cartId: _cartId),
                  ),
                ),
                _FabAction(
                  key: 'sync',
                  icon: Icons.sync_rounded,
                  label: 'Sync LAN',
                  onTap: () => showQuickSyncDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: cs.surface,
      bottomNavigationBar: cart.isEmpty
          ? null
          : _buildCartBottom(context, cart, cartNotifier, cartMeta),
    );
  }
}

/// Blob hangat di latar (meniru `.blobs` katalog HTML): dua gradien radial
/// di sudut kiri-atas & kanan-atas; meredup saat bukan landing.
class _ModernBlobs extends StatelessWidget {
  const _ModernBlobs({required this.strong});
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final b1 = dark ? const Color(0x6B96482E) : const Color(0x8CF2B8A0);
    final b2 = dark ? const Color(0x4D82642C) : const Color(0x80F6D9A8);
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: AppMotion.dur(context, AppMotion.page),
        opacity: strong ? 1 : 0.5,
        child: Stack(
          children: [
            Positioned(
              left: -130,
              top: -130,
              child: _blob(b1, 260),
            ),
            Positioned(
              right: -120,
              top: -110,
              child: _blob(b2, 240),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(Color c, double size) => Container(
        width: size * 2,
        height: size * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
              colors: [c, c.withOpacity(0)], stops: const [0, 0.7]),
        ),
      );
}

/// Sapaan + kolom cari. Di landing sapaan (dengan stiker) tampil di atas
/// kolom cari; begitu pengguna mengetik/memilih kategori, sapaan menciut dan
/// kolom cari naik ke atas (satu TextField yang sama — fokus & kursor aman).
class _ModernSearchStage extends ConsumerStatefulWidget {
  const _ModernSearchStage({
    required this.isLanding,
    required this.ctrl,
    required this.focus,
    required this.onChanged,
    required this.onScan,
  });

  final bool isLanding;
  final TextEditingController ctrl;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onScan;

  @override
  ConsumerState<_ModernSearchStage> createState() => _ModernSearchStageState();
}

class _ModernSearchStageState extends ConsumerState<_ModernSearchStage> {
  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocus);
    super.dispose();
  }

  /// Fokus ulang dengan teks lama -> select-all (ketik langsung menimpa),
  /// sama dengan `_KasirTopbarState`. Post-frame agar tidak ditimpa cursor
  /// bawaan TextField.
  void _onFocus() {
    if (widget.focus.hasFocus && widget.ctrl.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.focus.hasFocus) return;
        final len = widget.ctrl.text.length;
        if (len == 0) return;
        widget.ctrl.selection = TextSelection(baseOffset: 0, extentOffset: len);
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sticker =
        ref.watch(kasirStickerProvider(KasirStickerSlot.landing)).valueOrNull;
    final dur = AppMotion.dur(context, AppMotion.page);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: widget.isLanding ? 1.0 : 0.0),
          duration: dur,
          curve: AppMotion.easeOutQuint,
          builder: (context, f, child) {
            if (f <= 0.001) return const SizedBox(width: double.infinity);
            return ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: f,
                child: Opacity(opacity: f.clamp(0.0, 1.0), child: child),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              children: [
                if (sticker != null) ...[
                  AppSticker(key: const Key('landing-sticker'), json: sticker),
                  const SizedBox(height: 8),
                ],
                Text(
                  'Mau jual apa hari ini?',
                  textAlign: TextAlign.center,
                  style: AppTheme.numStyle(context, size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scan barang, ketik nama, atau pilih kategori',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.isLanding ? 0 : 10, 16, 6),
          child: AnimatedContainer(
            duration: dur,
            curve: AppMotion.easeOutQuint,
            height: 52,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: widget.focus.hasFocus ? cs.primary : cs.outlineVariant,
                  width: widget.focus.hasFocus ? 1.5 : 1),
              boxShadow: widget.isLanding
                  ? [
                      BoxShadow(
                        color: dark
                            ? const Color(0x66000000)
                            : const Color(0x1F5A3C1E),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('modern-search'),
                    controller: widget.ctrl,
                    focusNode: widget.focus,
                    onChanged: widget.onChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration.collapsed(
                      hintText: 'Cari produk…',
                      hintStyle:
                          TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.ctrl,
                  builder: (_, v, __) => v.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          key: const Key('modern-search-clear'),
                          tooltip: 'Hapus',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            widget.ctrl.clear();
                            widget.onChanged('');
                          },
                        ),
                ),
                IconButton(
                  key: const Key('modern-scan'),
                  tooltip: 'Scan barcode',
                  onPressed: widget.onScan,
                  icon: Icon(Icons.qr_code_scanner_rounded,
                      color: AppTheme.scanFg(dark)),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Isi landing gaya Baru: chip kategori (terpusat) + daftar "Sering dibeli
/// <pelanggan>" / "Terakhir dijual". TANPA Terlaris (permintaan user).
class _ModernLanding extends ConsumerWidget {
  const _ModernLanding({
    required this.cartId,
    required this.onShowAll,
    required this.tileBuilder,
  });

  final String cartId;
  final VoidCallback onShowAll;
  final Widget Function(Product) tileBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final groups =
        ref.watch(_kasirGroupsProvider).valueOrNull ?? const <ProductGroup>[];
    final meta = ref.watch(cartMetaProvider(cartId));
    final recent = ref.watch(_landingRecentProvider(meta.customerId));
    final items = recent.valueOrNull ?? const <Product>[];
    final title = (meta.customerName ?? '').isNotEmpty
        ? 'Sering dibeli ${meta.customerName}'
        : 'Terakhir dijual';

    return ListView(
      key: const Key('kasir-landing'),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              PressScale(
                depth: 0.05,
                child: ActionChip(
                  key: const Key('landing-all'),
                  label: const Text('Semua produk',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  backgroundColor: cs.primary,
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  onPressed: onShowAll,
                ),
              ),
              for (final g in groups)
                PressScale(
                  depth: 0.05,
                  child: ActionChip(
                    key: Key('landing-cat-${g.id}'),
                    label:
                        Text(g.name!, style: const TextStyle(fontSize: 12.5)),
                    side: BorderSide(color: cs.outlineVariant),
                    backgroundColor: cs.surface,
                    shape: const StadiumBorder(),
                    onPressed: () => ref
                        .read(_kasirSelectedGroupProvider.notifier)
                        .state = g.id,
                  ),
                ),
            ],
          ),
        ),
        if (recent.isLoading && items.isEmpty) ...[
          _LandingSectionTitle(title),
          const SkeletonRow(),
          const SkeletonRow(nameFactor: 0.4),
        ] else if (items.isNotEmpty) ...[
          _LandingSectionTitle(title),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 62, color: cs.outlineVariant),
            tileBuilder(items[i]),
          ],
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tombol aksi pojok kanan bawah (pengganti header Klasik)
// ─────────────────────────────────────────────────────────────────────────────

/// Satu aksi di tombol pojok.
class _FabAction {
  const _FabAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final String key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
}

/// Tombol pojok kanan bawah ala "chips expanded" Telegram.
///  - Landing: RAIL ikon-saja (daftar dikasih lorong kanan supaya tombol "+"
///    produk tidak tertutup).
///  - Selain landing (mengetik/kategori/daftar): mengecil jadi SATU lingkaran
///    (badge = jumlah antrian); ketuk untuk mengembang jadi daftar berlabel
///    dengan latar redup, ketuk lagi/di luar untuk menutup.
/// Urutan dari BAWAH: Riwayat, Antrian, Tempel Pesanan, Sync LAN; di atasnya
/// pilihan tampilan (grid/list) dan sakelar terang/gelap.
class _ModernFab extends StatefulWidget {
  const _ModernFab({
    required this.isLanding,
    required this.actions,
    required this.isGrid,
    required this.dark,
    required this.onToggleGrid,
    required this.onToggleTheme,
  });

  /// Dari BAWAH ke ATAS.
  final List<_FabAction> actions;
  final bool isLanding;
  final bool isGrid;
  final bool dark;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleTheme;

  @override
  State<_ModernFab> createState() => _ModernFabState();
}

class _ModernFabState extends State<_ModernFab>
    with SingleTickerProviderStateMixin {
  // Dibuat di initState (bukan `late final` lazy): kalau hanya rail yang
  // tampil, controller tak pernah disentuh sampai dispose() -> pembuatan
  // Ticker saat unmount melempar "deactivated widget's ancestor".
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 160),
    );
  }

  bool _open = false;

  @override
  void didUpdateWidget(_ModernFab old) {
    super.didUpdateWidget(old);
    // Pindah landing <-> non-landing: selalu mulai tertutup.
    if (old.isLanding != widget.isLanding && _open) _setOpen(false);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _setOpen(bool v) {
    setState(() => _open = v);
    if (AppMotion.reduced(context)) {
      _c.value = v ? 1 : 0;
    } else {
      v ? _c.forward() : _c.reverse();
    }
  }

  void _run(VoidCallback cb) {
    if (_open) _setOpen(false);
    cb();
  }

  int get _totalBadge => widget.actions.fold<int>(0, (s, a) => s + a.badge);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rail = widget.isLanding;
    return Stack(
      children: [
        // Latar redup HANYA saat daftar berlabel terbuka (non-landing).
        if (!rail && _open)
          Positioned.fill(
            child: GestureDetector(
              key: const Key('fab-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _setOpen(false),
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => ColoredBox(
                    color: Colors.black.withOpacity(0.28 * _c.value)),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 12,
          child: rail ? _buildRail(cs) : _buildCollapsible(cs),
        ),
      ],
    );
  }

  // ── Landing: rail ikon ────────────────────────────────────────────────
  Widget _buildRail(ColorScheme cs) {
    return Column(
      key: const Key('fab-rail'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniFab(
          key: const Key('fab-theme'),
          icon:
              widget.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          tooltip: widget.dark ? 'Mode gelap' : 'Mode terang',
          onTap: widget.onToggleTheme,
        ),
        const SizedBox(height: 8),
        _MiniFab(
          key: const Key('fab-grid'),
          icon:
              widget.isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
          tooltip: widget.isGrid ? 'Tampilan daftar' : 'Tampilan grid',
          onTap: widget.onToggleGrid,
        ),
        for (var i = widget.actions.length - 1; i >= 0; i--) ...[
          const SizedBox(height: 8),
          _MiniFab(
            key: Key('fab-${widget.actions[i].key}'),
            icon: widget.actions[i].icon,
            tooltip: widget.actions[i].label,
            badge: widget.actions[i].badge,
            onTap: widget.actions[i].onTap,
          ),
        ],
      ],
    );
  }

  // ── Non-landing: lingkaran -> daftar berlabel ──────────────────────────
  Widget _buildCollapsible(ColorScheme cs) {
    final items = <Widget>[];
    // Dari ATAS ke bawah: sakelar tema, grid/list, lalu aksi (Sync paling
    // atas ... Riwayat paling bawah).
    final topDown = [
      _ExpandedRow(
        index: 0,
        total: widget.actions.length + 2,
        anim: _c,
        label: widget.dark ? 'Mode gelap' : 'Mode terang',
        child: _LampSwitch(
            key: const Key('fab-theme'),
            dark: widget.dark,
            onTap: widget.onToggleTheme),
      ),
      _ExpandedRow(
        index: 1,
        total: widget.actions.length + 2,
        anim: _c,
        label: widget.isGrid ? 'Tampilan daftar' : 'Tampilan grid',
        child: _MiniFab(
          key: const Key('fab-grid'),
          icon:
              widget.isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
          onTap: () => _run(widget.onToggleGrid),
        ),
      ),
      for (var i = widget.actions.length - 1, n = 2; i >= 0; i--, n++)
        _ExpandedRow(
          index: n,
          total: widget.actions.length + 2,
          anim: _c,
          label: widget.actions[i].label,
          child: _MiniFab(
            key: Key('fab-${widget.actions[i].key}'),
            icon: widget.actions[i].icon,
            badge: widget.actions[i].badge,
            onTap: () => _run(widget.actions[i].onTap),
          ),
        ),
    ];
    if (_open) {
      for (final r in topDown) {
        items.add(r);
        items.add(const SizedBox(height: 10));
      }
    }
    return Column(
      key: const Key('fab-collapsible'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ...items,
        _MainFab(
          open: _open,
          badge: _totalBadge,
          anim: _c,
          onTap: () => _setOpen(!_open),
        ),
      ],
    );
  }
}

/// Lingkaran utama (tertutup/terbuka): ikon berputar jadi X.
class _MainFab extends StatelessWidget {
  const _MainFab(
      {required this.open,
      required this.badge,
      required this.anim,
      required this.onTap});
  final bool open;
  final int badge;
  final Animation<double> anim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PressScale(
      depth: 0.06,
      child: Badge(
        isLabelVisible: badge > 0 && !open,
        label: Text('$badge'),
        child: Material(
          key: const Key('fab-main'),
          color: cs.primary,
          elevation: 6,
          shadowColor: const Color(0x59C96442),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: AnimatedBuilder(
                animation: anim,
                builder: (_, __) => Transform.rotate(
                  angle: anim.value * math.pi / 2,
                  child: Icon(open ? Icons.close_rounded : Icons.apps_rounded,
                      color: cs.onPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Baris berlabel saat terbuka: label (pil) di kiri + tombol bulat di kanan;
/// masuk bertahap (menyembul dari lingkaran utama).
class _ExpandedRow extends StatelessWidget {
  const _ExpandedRow({
    required this.index,
    required this.total,
    required this.anim,
    required this.label,
    required this.child,
  });
  final int index;
  final int total;
  final Animation<double> anim;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Yang paling dekat lingkaran utama (index terbesar) muncul duluan.
    final order = total - 1 - index;
    final start = (order * 0.07).clamp(0.0, 0.5);
    final curved = CurvedAnimation(
      parent: anim,
      curve: Interval(start, math.min(1.0, start + 0.5),
          curve: AppMotion.easeOutBack),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (_, __) {
        final t = curved.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: cs.surfaceContainerHigh,
                  elevation: 2,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(label,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                child,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tombol bulat kecil 44dp (+ badge opsional).
class _MiniFab extends StatelessWidget {
  const _MiniFab(
      {super.key,
      required this.icon,
      required this.onTap,
      this.badge = 0,
      this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn = PressScale(
      depth: 0.06,
      child: Badge(
        isLabelVisible: badge > 0,
        label: Text('$badge'),
        child: Material(
          color: cs.surfaceContainerHigh,
          elevation: 3,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 21, color: cs.onSurface),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip!, child: btn);
    return btn;
  }
}

/// Sakelar terang/gelap ala saklar lampu: lintasan pil, kenop berisi
/// matahari/bulan yang meluncur dengan sedikit memantul.
class _LampSwitch extends StatelessWidget {
  const _LampSwitch({super.key, required this.dark, required this.onTap});
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dur = AppMotion.dur(context, AppMotion.medium);
    return Semantics(
      button: true,
      label: dark ? 'Ganti ke mode terang' : 'Ganti ke mode gelap',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: dur,
          curve: AppMotion.easeOutQuint,
          width: 72,
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: dark
                  ? const [Color(0xFF2A2623), Color(0xFF3B3430)]
                  : const [Color(0xFFFCE7B0), Color(0xFFF6D9A8)],
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 2)),
            ],
          ),
          child: AnimatedAlign(
            duration: dur,
            curve: AppMotion.easeOutBack,
            alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0xFFECE7DD) : Colors.white,
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 4,
                      offset: Offset(0, 1)),
                ],
              ),
              child: Icon(
                dark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                size: 18,
                color: dark ? const Color(0xFF3B3430) : const Color(0xFFD97757),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
