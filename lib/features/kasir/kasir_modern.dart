part of 'kasir_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Kasir gaya BARU (terinspirasi katalog HTML). Berkas ini `part` dari
// kasir_screen.dart supaya memakai logika kasir yang SAMA persis (scanner
// HID/kamera, quick-add, revolver, select-all pencarian, dst.) tanpa
// menduplikasinya; hanya TATA LETAK & tampilan yang berbeda dari Klasik.
// ─────────────────────────────────────────────────────────────────────────────

extension _KasirModernX on _KasirScreenState {
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
                                ? _ModernLanding(
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
