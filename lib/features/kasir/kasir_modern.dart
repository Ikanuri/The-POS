part of 'kasir_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kasir gaya BARU (terinspirasi katalog HTML). Berkas ini `part` dari
// kasir_screen.dart supaya memakai logika kasir yang SAMA persis (scanner
// HID/kamera, quick-add, revolver, select-all pencarian, dst.) tanpa
// menduplikasinya; hanya TATA LETAK & tampilan yang berbeda dari Klasik.
// ─────────────────────────────────────────────────────────────────────────────

/// Nama produk yang SERING DIBELI pelanggan di keranjang (180 hari) — bahan
/// saran bergilir di kolom cari. Tanpa pelanggan = kosong (hint statis).
final _customerSuggestionsProvider = FutureProvider.autoDispose
    .family<List<String>, String?>((ref, customerId) async {
  if (customerId == null) return const [];
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final stats = await db.getCustomerTopProducts(
      customerId, now.subtract(const Duration(days: 180)), now,
      limit: 8);
  return [
    for (final s in stats)
      if (s.name.trim().isNotEmpty) s.name.trim(),
  ];
});

extension _KasirModernX on _KasirScreenState {
  /// Antrian pesanan ditahan (tombol pojok): lembar bawah bergaya struk.
  void _openHeldSheet() {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _ModernHeldSheet(
        busy: _isSwitchingHeld,
        onResume: (o) {
          Navigator.of(sheetCtx).pop();
          _onHeldCardTap(o);
        },
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
                  cartId: _cartId,
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
          : _buildModernCartBottom(context, cart, cartNotifier, cartMeta),
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
    required this.cartId,
    required this.isLanding,
    required this.ctrl,
    required this.focus,
    required this.onChanged,
    required this.onScan,
  });

  final String cartId;
  final bool isLanding;
  final TextEditingController ctrl;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onScan;

  @override
  ConsumerState<_ModernSearchStage> createState() => _ModernSearchStageState();
}

class _ModernSearchStageState extends ConsumerState<_ModernSearchStage> {
  /// Saran yang SEDANG tampil di hint (diisi `_RotatingHint`).
  String? _currentSuggestion;

  /// Cari saran yang sedang tampil (panah / Enter pada kolom kosong).
  void _searchSuggestion() {
    final q = _currentSuggestion;
    if (q == null || q.isEmpty) return;
    widget.ctrl.text = q;
    widget.ctrl.selection = TextSelection.collapsed(offset: q.length);
    widget.onChanged(q);
  }

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
    final customerId = ref.watch(cartMetaProvider(widget.cartId)).customerId;
    final suggestions =
        ref.watch(_customerSuggestionsProvider(customerId)).valueOrNull ??
            const <String>[];

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
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      TextField(
                        key: const Key('modern-search'),
                        controller: widget.ctrl,
                        focusNode: widget.focus,
                        onChanged: widget.onChanged,
                        onSubmitted: (v) {
                          if (v.isEmpty) _searchSuggestion();
                        },
                        textInputAction: TextInputAction.search,
                        style: const TextStyle(fontSize: 15),
                        decoration:
                            const InputDecoration.collapsed(hintText: ''),
                      ),
                      // Hint: saran bergilir (produk yang sering dibeli
                      // pelanggan) atau 'Cari produk…'. Hilang saat mengetik.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: widget.ctrl,
                            builder: (_, v, __) => v.text.isNotEmpty
                                ? const SizedBox.shrink()
                                : _RotatingHint(
                                    names: suggestions,
                                    onChanged: (n) => _currentSuggestion = n,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.ctrl,
                  builder: (_, v, __) =>
                      (v.text.isEmpty && suggestions.isNotEmpty)
                          ? IconButton(
                              key: const Key('modern-suggest-go'),
                              tooltip: 'Cari saran ini',
                              icon: Icon(Icons.arrow_forward_rounded,
                                  size: 20, color: cs.primary),
                              onPressed: _searchSuggestion,
                            )
                          : const SizedBox.shrink(),
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

/// Hint kolom cari yang bergilir seperti placeholder katalog HTML: "Cari
/// <b>Nama Produk</b>" berganti tiap ~3 dtk dengan geser-naik + pudar. Tanpa
/// saran -> 'Cari produk…' statis (tanpa timer). "Kurangi animasi" -> berganti
/// langsung tanpa geser.
class _RotatingHint extends StatefulWidget {
  const _RotatingHint({required this.names, required this.onChanged});
  final List<String> names;
  final ValueChanged<String?> onChanged;

  @override
  State<_RotatingHint> createState() => _RotatingHintState();
}

class _RotatingHintState extends State<_RotatingHint> {
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(_RotatingHint old) {
    super.didUpdateWidget(old);
    if (old.names.join('|') != widget.names.join('|')) {
      _i = 0;
      _start();
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.names.length < 2) return;
    _timer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted) return;
      setState(() => _i = (_i + 1) % widget.names.length);
      _report();
    });
  }

  void _report() {
    if (!mounted) return;
    widget.onChanged(widget.names.isEmpty ? null : widget.names[_i]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Hint hilang (mengetik) -> tidak ada saran aktif.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 15, color: cs.onSurfaceVariant);
    if (widget.names.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('Cari produk…', style: style),
      );
    }
    final name = widget.names[_i % widget.names.length];
    return ClipRect(
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedSwitcher(
          duration: AppMotion.dur(context, AppMotion.medium),
          switchInCurve: AppMotion.easeOutQuint,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero)
                      .animate(anim),
              child: child,
            ),
          ),
          child: Text.rich(
            TextSpan(style: style, children: [
              const TextSpan(text: 'Cari '),
              TextSpan(
                  text: name,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: cs.onSurface)),
            ]),
            key: ValueKey(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cart bar gaya Baru: kartu melayang (mengikuti pola 3/4 + 1/4 katalog HTML)
// ─────────────────────────────────────────────────────────────────────────────

extension _KasirModernCart on _KasirScreenState {
  /// Cart bar baru. Semua data & aksi SAMA dengan Klasik (`_buildCartBottom`):
  /// total (+ pelunasan hutang/pre-order), item terakhir, pengingat Laci Meja,
  /// hutang pelanggan, gerbang pembayaran, tahan, geser-ke-atas buka keranjang.
  Widget _buildModernCartBottom(BuildContext context, List<CartItem> cart,
      CartNotifier cartNotifier, CartMeta cartMeta) {
    final total = cartNotifier.totalAmount +
        ref
            .watch(cartDebtSettlementProvider(_cartId))
            .fold<int>(0, (s, e) => s + e.amount) +
        ref
            .watch(cartPreorderSettlementProvider(_cartId))
            .fold<int>(0, (s, e) => s + e.amount);
    final last = cartNotifier.lastTouchedItem;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        if (d.velocity.pixelsPerSecond.dy < -300) {
          _incrementSwipeHint().ignore();
          _openCartSheet();
        }
      },
      child: _ModernCartBar(
        cartId: _cartId,
        total: total,
        count: cart.length,
        lastItem: last,
        lastEffQty: last == null ? 0 : cartNotifier.effectiveQtyFor(last),
        showSwipeHint: _swipeHintVisible,
        orderNumber: cartMeta.displayOrderNumber,
        laciMejaPending: ref
            .watch(laciMejaPendingProvider(
                (cartMeta.customerId, cartMeta.customerName)))
            .valueOrNull,
        customerDebt: ref
            .watch(cartCustomerDebtProvider(cartMeta.customerId))
            .valueOrNull,
        onTapDebt:
            (!(ref.watch(needsPaymentGateProvider).valueOrNull ?? false) &&
                    cartMeta.customerId != null)
                ? () => showDebtSettlementSheet(
                      context,
                      ref,
                      cartId: _cartId,
                      customerId: cartMeta.customerId!,
                      customerName: cartMeta.customerName ?? 'Pelanggan',
                    )
                : null,
        onHold: _isSwitchingHeld ? null : _holdCurrent,
        onBayar: () => context.push('/kasir/bayar'),
        onOpenCart: _openCartSheet,
      ),
    );
  }
}

class _ModernCartBar extends ConsumerWidget {
  const _ModernCartBar({
    required this.cartId,
    required this.total,
    required this.count,
    required this.lastItem,
    required this.lastEffQty,
    required this.showSwipeHint,
    required this.orderNumber,
    required this.laciMejaPending,
    required this.customerDebt,
    required this.onTapDebt,
    required this.onHold,
    required this.onBayar,
    required this.onOpenCart,
  });

  final String cartId;
  final int total;
  final int count;
  final CartItem? lastItem;
  final double lastEffQty;
  final bool showSwipeHint;
  final String? orderNumber;
  final LaciMejaPending? laciMejaPending;
  final (int total, int count)? customerDebt;
  final VoidCallback? onTapDebt;
  final VoidCallback? onHold;
  final VoidCallback onBayar;
  final VoidCallback onOpenCart;

  void _ensureReserved(WidgetRef ref) {
    final device = ref.read(deviceProvider);
    final db = ref.read(databaseProvider);
    ref
        .read(cartMetaProvider(cartId).notifier)
        .ensureReservedLocalId(() => db.reserveLocalId(device.deviceCode));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final meta = ref.watch(cartMetaProvider(cartId));
    final notifier = ref.read(cartMetaProvider(cartId).notifier);
    final needsGate = ref.watch(needsPaymentGateProvider).valueOrNull ?? false;
    // Item 55: nomor nota di-reserve sekali begitu bar tampil dengan isi.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureReserved(ref));

    String? lastLine;
    if (lastItem != null && lastEffQty > 0) {
      final q =
          lastEffQty % 1 == 0 ? lastEffQty.toInt().toString() : '$lastEffQty';
      final unit = lastItem!.unitName.isEmpty ? '' : ' ${lastItem!.unitName}';
      lastLine = '$q$unit · ${lastItem!.productName}';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
          12, 0, 12, 10 + MediaQuery.of(context).padding.bottom),
      child: Container(
        key: const Key('modern-cart-bar'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cs.outlineVariant, width: 0.6),
          boxShadow: [
            BoxShadow(
              color: dark ? const Color(0x80000000) : const Color(0x2E5A3C1E),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Baris chip: pelanggan & pegawai (+ nomor nota).
            Row(
              children: [
                Flexible(
                  flex: 4,
                  child: _ModernMetaPill(
                    key: const Key('pill-customer'),
                    icon: meta.customerId != null
                        ? Icons.person_rounded
                        : Icons.person_outline_rounded,
                    label: meta.hasCustomer ? meta.customerName! : 'Pelanggan',
                    active: meta.hasCustomer,
                    accent: meta.customerId != null,
                    onTap: () async {
                      final pick = await showCustomerPickerSheet(context, ref,
                          currentName: meta.customerName);
                      if (pick == null) return;
                      notifier.setCustomer(pick.id, pick.name);
                    },
                    onClear: meta.hasCustomer ? notifier.clearCustomer : null,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 3,
                  child: _ModernMetaPill(
                    key: const Key('pill-employee'),
                    icon: Icons.badge_outlined,
                    label: meta.hasEmployee ? meta.employeeName! : 'Pegawai',
                    active: meta.hasEmployee,
                    onTap: () async {
                      final pick = await showEmployeePickerSheet(context, ref,
                          currentId: meta.employeeId);
                      if (pick == null) return;
                      notifier.setEmployee(pick.id, pick.name);
                    },
                    onClear: meta.hasEmployee ? notifier.clearEmployee : null,
                  ),
                ),
                if (orderNumber != null) ...[
                  const SizedBox(width: 8),
                  Text('#$orderNumber',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            LaciMejaReminder.bar(context, laciMejaPending),
            if (customerDebt != null && customerDebt!.$2 > 0)
              InkWell(
                onTap: onTapDebt,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 13, color: cs.error),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Hutang ${formatRupiah(customerDebt!.$1)} '
                          'di ${customerDebt!.$2} nota',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.error),
                        ),
                      ),
                      if (onTapDebt != null)
                        Icon(Icons.chevron_right, size: 13, color: cs.error),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            // Total (ketuk = buka keranjang) | Tahan | Bayar -> pola 3/4 + 1/4.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: InkWell(
                    key: const Key('modern-cart-open'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: onOpenCart,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          ItemCountBadge(count: count),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BumpOnChange(
                                  value: total,
                                  peak: 1.08,
                                  child: Text(
                                    formatRupiah(total),
                                    style: AppTheme.numStyle(context,
                                        size: 22, weight: FontWeight.w700),
                                  ),
                                ),
                                if (lastLine != null)
                                  Text(
                                    lastLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: cs.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 1/4: Tahan (ikon) — disabled saat `_isSwitchingHeld`.
                Tooltip(
                  message: 'Tahan',
                  child: PressScale(
                    depth: 0.05,
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      shape: const CircleBorder(),
                      child: InkWell(
                        key: const Key('modern-hold'),
                        customBorder: const CircleBorder(),
                        onTap: onHold,
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(Icons.pause_rounded,
                              color: onHold != null
                                  ? cs.primary
                                  : cs.onSurfaceVariant.withOpacity(0.4)),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!needsGate) ...[
                  const SizedBox(width: 8),
                  // 3/4: Bayar — pil terracotta (warna tetap, teks putih).
                  PressScale(
                    depth: 0.04,
                    child: Material(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        key: const Key('modern-bayar'),
                        borderRadius: BorderRadius.circular(999),
                        onTap: onBayar,
                        child: const SizedBox(
                          height: 46,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Bayar',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                                SizedBox(width: 6),
                                Icon(Icons.arrow_forward_rounded,
                                    size: 18, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (showSwipeHint) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard_arrow_up_rounded,
                      size: 14, color: cs.onSurfaceVariant.withOpacity(0.5)),
                  const SizedBox(width: 3),
                  Text('Geser ke atas untuk lihat keranjang',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant.withOpacity(0.5))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chip pil Pelanggan/Pegawai di cart bar baru (ketuk = pilih, x = hapus).
class _ModernMetaPill extends StatelessWidget {
  const _ModernMetaPill({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool accent;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showAccent = accent && active;
    final fg = showAccent
        ? AppTheme.accent
        : (active ? cs.onSurface : cs.onSurfaceVariant);
    return Material(
      color: active
          ? (showAccent
              ? AppTheme.accent.withOpacity(0.12)
              : cs.surfaceContainerHigh)
          : cs.surfaceContainerLow,
      shape: StadiumBorder(
          side: BorderSide(
              color: showAccent
                  ? AppTheme.accent.withOpacity(0.4)
                  : cs.outlineVariant,
              width: 0.8)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: fg),
                ),
              ),
              if (onClear != null)
                InkWell(
                  onTap: onClear,
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.close_rounded, size: 14, color: fg),
                  ),
                )
              else
                const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lembar "Antrian Pesanan" gaya Baru (mengikuti sheet struk katalog HTML)
// ─────────────────────────────────────────────────────────────────────────────

class _ModernHeldSheet extends ConsumerWidget {
  const _ModernHeldSheet({required this.onResume, required this.busy});

  final void Function(HeldOrder) onResume;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final heldAsync = ref.watch(_heldOrdersListProvider);
    final maxH = MediaQuery.of(context).size.height * 0.78;

    return SafeArea(
      child: ConstrainedBox(
        key: const Key('modern-held-sheet'),
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Antrian Pesanan',
                      style: AppTheme.numStyle(context, size: 21),
                    ),
                  ),
                  IconButton(
                    key: const Key('modern-held-close'),
                    tooltip: 'Tutup',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Ketuk pesanan untuk melanjutkannya di keranjang.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
            Flexible(
              child: heldAsync.when(
                data: (held) {
                  if (held.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 34, color: cs.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text('Tidak ada pesanan ditahan',
                                style: TextStyle(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: held.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => Opacity(
                      opacity: busy ? 0.5 : 1,
                      child: _ModernHeldRow(
                        order: held[i],
                        onTap: busy ? null : () => onResume(held[i]),
                      ),
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(28),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Error: $e', style: TextStyle(color: cs.error)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu pesanan ditahan: kartu lebar bergaya struk (status di kiri atas,
/// total serif di kanan). Info SAMA dengan `_HeldCard` Klasik.
class _ModernHeldRow extends StatelessWidget {
  const _ModernHeldRow({required this.order, required this.onTap});

  final HeldOrder order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parsed = _parseHeldPayload(order.cartJson);
    final itemCount = parsed.items.where((c) => !c.isVariant).length;
    final total = cartTotalOf(parsed.items);
    final time =
        '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}';
    final isHandoff = parsed.awaitingPayment && parsed.employeeName != null;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: Key('held-${order.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isHandoff
                    ? AppTheme.accent.withOpacity(0.4)
                    : cs.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isHandoff
                            ? AppTheme.accent
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isHandoff
                            ? '${parsed.employeeName} · $time'
                            : 'Ditahan · $time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isHandoff ? Colors.white : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            order.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (parsed.meta.displayOrderNumber != null) ...[
                          const SizedBox(width: 6),
                          Text('#${parsed.meta.displayOrderNumber}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isHandoff
                          ? '$itemCount item · siap dibayarkan'
                          : '$itemCount item',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    if (parsed.prabayar.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.lock_clock_outlined,
                              size: 12, color: cs.primary),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Pra-Bayar ${formatRupiah(parsed.prabayar.fold<int>(0, (s, e) => s + e.amount))}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRupiah(total),
                    style: AppTheme.numStyle(context,
                        size: 17, weight: FontWeight.w700, color: cs.primary),
                  ),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: cs.outline),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
