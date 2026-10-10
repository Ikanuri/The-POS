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
  if (customerId == null || !PerfDiag.s.recentQuery) return const [];
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

/// Diagnostik performa: bayangan/elevasi dimatikan lewat saklar.
List<BoxShadow> _sh(List<BoxShadow> s) => PerfDiag.s.shadows ? s : const [];
double _el(double e) => PerfDiag.s.shadows ? e : 0;

extension _KasirModernX on _KasirScreenState {
  /// Ruang bawah yang harus dikosongkan daftar: keyboard ATAU cart bar
  /// (`extendBody` menaruh tinggi cart bar di `padding.bottom`).
  double _bottomClear(BuildContext c) {
    final k = MediaQuery.viewInsetsOf(c).bottom;
    final b = MediaQuery.paddingOf(c).bottom;
    return k > b ? k : b;
  }

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

  /// Dibungkus pendengar saklar diagnostik: layar dibangun ulang begitu saklar
  /// di Pengaturan > Diagnostik Performa berubah.
  Widget _buildModern(BuildContext context) =>
      ValueListenableBuilder<PerfDiagState>(
        valueListenable: PerfDiag.notifier,
        builder: (context, _, __) => _buildModernBody(context),
      );

  Widget _buildModernBody(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cart = ref.watch(cartProvider(_cartId));
    final cartNotifier = ref.read(cartProvider(_cartId).notifier);
    final cartMeta = ref.watch(cartMetaProvider(_cartId));
    final query = ref.watch(_kasirSearchProvider(_cartId));
    final isGrid = ref.watch(kasirGridProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selectedGroup = ref.watch(_kasirSelectedGroupProvider);
    final showAll = ref.watch(_kasirShowAllProvider(_cartId));
    final isLanding = query.isEmpty && selectedGroup == null && !showAll;
    // Pencarian selalu GLOBAL: begitu ada teks, filter kategori diabaikan
    // (kategori kembali berlaku saat kolom cari dikosongkan).
    final productsAsync = ref.watch(
        _kasirProductsProvider((query, query.isEmpty ? selectedGroup : null)));
    final hasSticker =
        ref.watch(kasirStickerProvider(KasirStickerSlot.landing)).valueOrNull !=
            null;

    void goHome() {
      _searchCtrl.clear();
      ref.read(_kasirSearchProvider(_cartId).notifier).state = '';
      ref.read(_kasirSelectedGroupProvider.notifier).state = null;
      ref.read(_kasirShowAllProvider(_cartId).notifier).state = false;
      _searchFocus.unfocus();
    }

    // Keyboard TIDAK mengecilkan layar (shell juga tidak, lihat
    // `shellResizesForKeyboard`): cart bar tetap di bawah (tertutup keyboard)
    // dan kolom cari tidak digeser - mengecilkan body membuat landing
    // di-layout ulang tiap frame selama keyboard naik (lag di HP uji). Daftar
    // produk diberi ruang bawah setinggi keyboard supaya baris terakhir tetap
    // bisa digulir ke atas keyboard.
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: _ModernBlobs(strong: isLanding)),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _ModernHeader(
                  isLanding: isLanding,
                  isGrid: isGrid,
                  dark: dark,
                  actions: [
                    _HeaderAction(
                      key: 'sync',
                      icon: Icons.sync_rounded,
                      label: 'Sync LAN',
                      fg: AppTheme.scanFg(dark),
                      bg: AppTheme.scanBg(dark),
                      onTap: () => showQuickSyncDialog(context),
                    ),
                    _HeaderAction(
                      key: 'paste',
                      icon: Icons.content_paste_go_rounded,
                      label: 'Tempel',
                      fg: AppTheme.tempelFg(dark),
                      bg: AppTheme.tempelBg(dark),
                      onTap: () => showAppSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => PasteOrderSheet(cartId: _cartId),
                      ),
                    ),
                    _HeaderAction(
                      key: 'held',
                      icon: Icons.pause_circle_outline_rounded,
                      label: 'Antrian',
                      badge: ref.watch(_heldCountProvider).valueOrNull ?? 0,
                      fg: AppTheme.antrianFg(dark),
                      bg: AppTheme.antrianBg(dark),
                      onTap: _openHeldSheet,
                    ),
                    _HeaderAction(
                      key: 'history',
                      icon: Icons.history_rounded,
                      label: 'Riwayat',
                      fg: AppTheme.riwayatFg(dark),
                      bg: AppTheme.riwayatBg(dark),
                      onTap: () => showAppSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => const TxHistorySheet(),
                      ),
                    ),
                  ],
                  onToggleGrid: () =>
                      ref.read(kasirGridProvider.notifier).toggle(),
                  onToggleTheme: () => ref
                      .read(themeModeProvider.notifier)
                      .set(dark ? ThemeMode.light : ThemeMode.dark),
                ),
                // Notifikasi inline (sync di latar, info kasir) di ATAS stiker/
                // kolom cari, tepat di bawah header.
                const SyncStatusBanner(),
                InlineBanner(
                  message: _bannerMsg,
                  type: _bannerType,
                  duration: _bannerDuration,
                  onDismiss: () => _clearBanner(),
                ),
                Expanded(
                  // Tinggi area di bawah header menentukan posisi kolom cari
                  // di landing: dipusatkan secara vertikal (seperti katalog
                  // HTML), bukan menempel di atas.
                  child: Builder(builder: (context) {
                    // Posisi tengah dihitung dari ukuran LAYAR (bukan tinggi area
                    // yang menyusut oleh keyboard) supaya kolom cari TIDAK bergeser
                    // & tidak memicu layout ulang sapaan/stiker tiap frame saat
                    // keyboard naik.
                    final vp = MediaQuery.viewPaddingOf(context);
                    final areaH = MediaQuery.sizeOf(context).height -
                        vp.top -
                        vp.bottom -
                        56 -
                        80;
                    final heroEst = (hasSticker ? 136.0 : 0.0) + 88.0;
                    final topPad =
                        (areaH * 0.46 - heroEst - 26).clamp(8.0, 260.0);
                    return Column(
                      children: [
                        _ModernSearchStage(
                          cartId: _cartId,
                          isLanding: isLanding,
                          landingTopPad: topPad,
                          ctrl: _searchCtrl,
                          focus: _searchFocus,
                          onChanged: (v) => ref
                              .read(_kasirSearchProvider(_cartId).notifier)
                              .state = v,
                          onScan: _openScanner,
                        ),
                        if (!isLanding)
                          _KasirCategoryChipRow(
                              showHome: true, onHome: goHome, modern: true),
                        Expanded(
                          // Tap/scroll di bawah kolom cari keluar dari fokus
                          // cari (teks tetap) - sama dengan Klasik; Listener
                          // (bukan GestureDetector) agar tap tetap sampai ke
                          // kartu produk.
                          child: Listener(
                            behavior: HitTestBehavior.translucent,
                            onPointerDown: (_) {
                              if (_skipNextSearchCollapse) {
                                _skipNextSearchCollapse = false;
                                return;
                              }
                              _searchFocus.unfocus();
                            },
                            child:
                                NotificationListener<ScrollStartNotification>(
                              onNotification: (_) {
                                _searchFocus.unfocus();
                                return false;
                              },
                              child: Column(
                                children: [
                                  Expanded(
                                    child: isLanding
                                        ? Builder(
                                            builder: (ctx) => _ModernLanding(
                                                  cartId: _cartId,
                                                  extraBottom:
                                                      _bottomClear(ctx),
                                                  onShowAll: () => ref
                                                      .read(
                                                          _kasirShowAllProvider(
                                                                  _cartId)
                                                              .notifier)
                                                      .state = true,
                                                  tileBuilder: (p) =>
                                                      _ProductListTile(
                                                    product: p,
                                                    cartId: _cartId,
                                                    onTapBody: () =>
                                                        _openEntry(p),
                                                    onQuickAdd: _quickAdd,
                                                    onOpenEntry: () =>
                                                        _openEntry(p),
                                                    onBeforeTap:
                                                        _markSkipSearchCollapse,
                                                    onAfterQtyChange:
                                                        _highlightSearchIfActive,
                                                  ),
                                                ))
                                        : Builder(
                                            builder: (ctx) =>
                                                _buildProductResults(
                                                    ctx,
                                                    productsAsync,
                                                    query,
                                                    isGrid,
                                                    modern: true,
                                                    extraBottom:
                                                        _bottomClear(ctx)),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
      // Latar sedikit lebih gelap dari kartu (seperti kanvas katalog HTML) agar
      // cart bar & kartu produk terlihat terpisah dari latar.
      backgroundColor: Color.lerp(cs.surface, AppTheme.canvasColor(dark), 0.4),
      // Daftar menggulir DI BELAKANG cart bar (tanpa pita latar bertepi tegas);
      // ruang bawah daftar = tinggi cart bar (atau keyboard bila lebih tinggi).
      extendBody: true,
      bottomNavigationBar: cart.isEmpty
          ? null
          : _buildModernCartBottom(context, cart, cartNotifier, cartMeta),
    );
  }
}

/// Header gaya Baru. Landing: ikon + nama aplikasi di kiri, empat tombol bulat
/// berketerangan kecil, saklar terang/gelap di ujung kanan. Mengetik / daftar:
/// KOMPAK - hanya ikon, empat tombol bulat tanpa keterangan, tombol grid/list
/// (saklar tema disembunyikan). Urutan tombol kiri -> kanan: Sync LAN, Tempel,
/// Antrian, Riwayat (Riwayat paling dekat tepi).
class _ModernHeader extends StatelessWidget {
  const _ModernHeader({
    required this.isLanding,
    required this.isGrid,
    required this.dark,
    required this.actions,
    required this.onToggleGrid,
    required this.onToggleTheme,
  });

  final bool isLanding;
  final bool isGrid;
  final bool dark;

  /// Urutan tampil kiri -> kanan.
  final List<_HeaderAction> actions;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dur = AppMotion.dur(context, AppMotion.medium);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: AnimatedSize(
        duration: dur,
        curve: AppMotion.easeOutQuint,
        alignment: Alignment.topCenter,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFD97757), Color(0xFFC96442)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: _sh(const [
                  BoxShadow(
                      color: Color(0x59C96442),
                      blurRadius: 12,
                      offset: Offset(0, 4)),
                ]),
              ),
              child: const Icon(Icons.shopping_basket_rounded,
                  color: Colors.white, size: 18),
            ),
            // Nama hanya di landing; boleh menyusut/ellipsis bila sempit.
            Expanded(
              child: AnimatedSwitcher(
                duration: dur,
                child: isLanding
                    ? Padding(
                        key: const ValueKey('hdr-name'),
                        padding: const EdgeInsets.only(left: 6, right: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'The POS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.numStyle(context,
                                size: 19, weight: FontWeight.w700),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('hdr-name-none')),
              ),
            ),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) SizedBox(width: isLanding ? 2 : 6),
              _HeaderBtn(
                key: Key('hdr-${actions[i].key}'),
                action: actions[i],
                labeled: isLanding,
              ),
            ],
            AnimatedSize(
              duration: dur,
              curve: AppMotion.easeOutQuint,
              child: AnimatedSwitcher(
                duration: dur,
                child: isLanding
                    ? const SizedBox.shrink(key: ValueKey('hdr-grid-none'))
                    : Padding(
                        key: const ValueKey('hdr-grid-slot'),
                        padding: const EdgeInsets.only(left: 6),
                        child: Tooltip(
                          message: isGrid ? 'Tampilan daftar' : 'Tampilan grid',
                          child: PressScale(
                            depth: 0.06,
                            child: Material(
                              color: cs.surface,
                              elevation: _el(1.5),
                              shadowColor: Colors.black26,
                              shape: CircleBorder(
                                  side: BorderSide(
                                      color: cs.outlineVariant, width: 0.6)),
                              child: InkWell(
                                key: const Key('hdr-grid'),
                                customBorder: const CircleBorder(),
                                onTap: onToggleGrid,
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                      isGrid
                                          ? Icons.view_list_rounded
                                          : Icons.grid_view_rounded,
                                      size: 20,
                                      color: cs.onSurface),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            // Saklar tema TETAP di pojok kanan atas (landing maupun daftar).
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _LightRocker(
                  key: const Key('hdr-theme'),
                  dark: dark,
                  onTap: onToggleTheme),
            ),
          ],
        ),
      ),
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
    if (!PerfDiag.s.blobs) return const SizedBox.shrink();
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
/// kolom cari dan seluruh kelompok dipusatkan secara vertikal; begitu
/// pengguna mengetik/memilih kategori, sapaan menciut dan kolom cari naik ke
/// atas (satu TextField yang sama - fokus & kursor aman).
class _ModernSearchStage extends ConsumerStatefulWidget {
  const _ModernSearchStage({
    required this.cartId,
    required this.isLanding,
    required this.landingTopPad,
    required this.ctrl,
    required this.focus,
    required this.onChanged,
    required this.onScan,
  });

  final String cartId;
  final bool isLanding;

  /// Ruang kosong di atas sapaan saat landing (memusatkan kolom cari).
  final double landingTopPad;
  final TextEditingController ctrl;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onScan;

  @override
  ConsumerState<_ModernSearchStage> createState() => _ModernSearchStageState();
}

class _ModernSearchStageState extends ConsumerState<_ModernSearchStage> {
  static const _kTextStyle = TextStyle(fontSize: 15);

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

  /// Blok seleksi-semua digambar sendiri dengan sudut membulat (seleksi bawaan
  /// Flutter berujung lancip); seleksi sebagian tetap memakai bawaan.
  bool _fullySelected(TextEditingValue v) =>
      widget.focus.hasFocus &&
      v.text.isNotEmpty &&
      v.selection.isValid &&
      v.selection.start == 0 &&
      v.selection.end == v.text.length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sticker =
        ref.watch(kasirStickerProvider(KasirStickerSlot.landing)).valueOrNull;
    final texts = ref.watch(kasirLandingTextProvider).valueOrNull ??
        KasirLandingText.defaults;
    // Diagnostik: tanpa animasi sapaan/pil (berpindah instan).
    final dur = PerfDiag.s.heroAnim
        ? AppMotion.dur(context, AppMotion.page)
        : Duration.zero;
    final customerId = ref.watch(cartMetaProvider(widget.cartId)).customerId;
    final suggestions =
        ref.watch(_customerSuggestionsProvider(customerId)).valueOrNull ??
            const <String>[];
    final focused = widget.focus.hasFocus;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: dur,
          curve: AppMotion.easeOutQuint,
          height: widget.isLanding ? widget.landingTopPad : 0,
        ),
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
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              children: [
                if (sticker != null) ...[
                  AppSticker(key: const Key('landing-sticker'), json: sticker),
                  const SizedBox(height: 8),
                ],
                Text(
                  texts.title,
                  key: const Key('landing-title'),
                  textAlign: TextAlign.center,
                  style: AppTheme.numStyle(context, size: 26),
                ),
                const SizedBox(height: 6),
                Text(
                  texts.subtitle,
                  key: const Key('landing-subtitle'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: AnimatedContainer(
            key: const Key('modern-search-pill'),
            duration: dur,
            curve: AppMotion.easeOutQuint,
            height: 52,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(999),
              // Seperti .search katalog HTML: garis 1,5px warna 'line';
              // saat fokus berubah ke aksen - dibuat memudar, tidak tegas.
              border: Border.all(
                color: focused
                    ? AppTheme.accent.withOpacity(0.5)
                    : cs.outlineVariant,
                width: 1.5,
              ),
              boxShadow: _sh([
                BoxShadow(
                  color:
                      dark ? const Color(0x66000000) : const Color(0x1F5A3C1E),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ]),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search_rounded,
                    size: 20, color: cs.onSurfaceVariant.withOpacity(0.7)),
                const SizedBox(width: 10),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.ctrl,
                    builder: (_, v, __) {
                      final full = _fullySelected(v);
                      // Daftar anak Stack WAJIB stabil (3 slot tetap, TextField
                      // ber-Key): kalau memakai `if` yang menggeser posisi,
                      // Flutter (mencocokkan anak tanpa Key per indeks+tipe)
                      // MEMBUANG & membangun ulang TextField saat seleksi-semua
                      // / kosong<->berisi berganti -> koneksi IME & kursor
                      // hilang (keyboard terbuka tapi kursor tak muncul).
                      return Stack(
                        alignment: Alignment.centerLeft,
                        // Jendela hint boleh lebih tinggi dari TextField.
                        clipBehavior: Clip.none,
                        children: [
                          // Blok seleksi-semua berujung membulat.
                          if (!full)
                            const SizedBox.shrink(
                                key: ValueKey('modern-search-sel-slot'))
                          else
                            LayoutBuilder(
                                key: const ValueKey('modern-search-sel-slot'),
                                builder: (context, c) {
                                  final tp = TextPainter(
                                    text: TextSpan(
                                        text: v.text, style: _kTextStyle),
                                    maxLines: 1,
                                    textDirection: TextDirection.ltr,
                                  )..layout();
                                  return Container(
                                    key: const Key('modern-search-selection'),
                                    width: math.min(c.maxWidth, tp.width + 12),
                                    height: 26,
                                    margin: const EdgeInsets.only(left: 0),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accent.withOpacity(0.22),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  );
                                }),
                          TextSelectionTheme(
                            key: const ValueKey('modern-search-field-slot'),
                            data: TextSelectionThemeData(
                              // Seleksi-semua: warna bawaan disembunyikan
                              // (diganti blok membulat di atas).
                              selectionColor: full
                                  ? Colors.transparent
                                  : AppTheme.accent.withOpacity(0.28),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: TextField(
                                key: const Key('modern-search'),
                                controller: widget.ctrl,
                                focusNode: widget.focus,
                                onChanged: widget.onChanged,
                                onSubmitted: (t) {
                                  if (t.isEmpty) _searchSuggestion();
                                },
                                textInputAction: TextInputAction.search,
                                style: _kTextStyle,
                                cursorColor: AppTheme.accent,
                                // SEMUA border dimatikan eksplisit: border
                                // dari InputDecorationTheme aplikasi
                                // (enabled/focused) kalau tidak akan
                                // membentuk lingkaran kedua di dalam pil.
                                decoration: const InputDecoration(
                                  isCollapsed: true,
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ),
                          // Hint: saran bergilir (produk yang sering dibeli
                          // pelanggan) atau 'Cari produk...'. Hilang saat
                          // mengetik.
                          if (v.text.isNotEmpty)
                            const SizedBox.shrink(
                                key: ValueKey('modern-search-hint-slot'))
                          else
                            Positioned.fill(
                              key: const ValueKey('modern-search-hint-slot'),
                              child: IgnorePointer(
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: _RotatingHint(
                                    names: suggestions,
                                    onChanged: (n) => _currentSuggestion = n,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.ctrl,
                  builder: (_, v, __) => (v.text.isEmpty &&
                          suggestions.isNotEmpty)
                      ? IconButton(
                          key: const Key('modern-suggest-go'),
                          tooltip: 'Cari saran ini',
                          icon: const Icon(Icons.arrow_forward_rounded,
                              size: 20, color: AppTheme.accent),
                          onPressed: _searchSuggestion,
                        )
                      : v.text.isNotEmpty
                          ? IconButton(
                              key: const Key('modern-search-clear'),
                              tooltip: 'Hapus',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                widget.ctrl.clear();
                                widget.onChanged('');
                                // Keyboard tetap terbuka & kolom tetap fokus.
                                widget.focus.requestFocus();
                              },
                            )
                          : const SizedBox.shrink(),
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
    this.extraBottom = 0,
    required this.onShowAll,
    required this.tileBuilder,
  });

  final String cartId;

  /// Tinggi keyboard: ruang bawah list agar baris terakhir bisa digulir ke
  /// atas keyboard (layar tidak dikecilkan oleh keyboard).
  final double extraBottom;
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
      padding: EdgeInsets.only(bottom: 24 + extraBottom),
      children: [
        // Satu baris saja, digeser mendatar bila kategori banyak; bila muat,
        // terpusat.
        SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              key: const Key('landing-chips'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: c.maxWidth - 32),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                      for (final g in groups) ...[
                        const SizedBox(width: 8),
                        PressScale(
                          depth: 0.05,
                          child: ActionChip(
                            key: Key('landing-cat-${g.id}'),
                            label: Text(g.name!,
                                style: const TextStyle(fontSize: 12.5)),
                            side: BorderSide(color: cs.outlineVariant),
                            backgroundColor: cs.surface,
                            shape: const StadiumBorder(),
                            onPressed: () => ref
                                .read(_kasirSelectedGroupProvider.notifier)
                                .state = g.id,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (recent.isLoading && items.isEmpty) ...[
          _LandingSectionTitle(title),
          const SkeletonRow(),
          const SkeletonRow(nameFactor: 0.4),
        ] else if (items.isNotEmpty) ...[
          _LandingSectionTitle(title),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _ModernTileCard(child: tileBuilder(items[i])),
            ),
        ],
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// Tombol aksi bulat di header (pengganti header Klasik)
// ─────────────────────────────────────────────────────────────────────────────

/// Satu aksi di header (warna aksen mengikuti header Klasik).
class _HeaderAction {
  const _HeaderAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.fg,
    required this.bg,
    this.badge = 0,
  });

  final String key;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color fg;
  final Color bg;
  final int badge;
}

/// Tombol bulat berwarna (aksen tiap fungsi). Landing: keterangan kecil di
/// bawahnya; kompak: hanya lingkaran (tetap ber-tooltip & Semantics).
class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn({super.key, required this.action, required this.labeled});
  final _HeaderAction action;
  final bool labeled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final circle = PressScale(
      depth: 0.06,
      child: Badge(
        isLabelVisible: action.badge > 0,
        label: Text('${action.badge}'),
        child: Material(
          color: action.bg,
          elevation: _el(2),
          shadowColor: Colors.black38,
          shape: CircleBorder(
              side: BorderSide(color: action.fg.withOpacity(0.25))),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: action.onTap,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(action.icon, size: 20, color: action.fg),
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: action.label,
      child: Semantics(
        button: true,
        label: action.label,
        excludeSemantics: true,
        child: SizedBox(
          width: labeled ? 42 : 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              circle,
              if (labeled) ...[
                const SizedBox(height: 2),
                // FittedBox: keterangan menyusut (bukan terpotong) bila Ukuran
                // Teks besar.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    action.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Sakelar terang/gelap berbentuk SAKLAR LISTRIK (rocker): pelat dengan
/// tuas dua sisi - sisi atas matahari, sisi bawah bulan - yang miring ke sisi
/// yang aktif dengan sedikit memantul.
class _LightRocker extends StatelessWidget {
  const _LightRocker({super.key, required this.dark, required this.onTap});
  final bool dark;
  final VoidCallback onTap;

  /// Saklar "ilusi optik" ala GoPay: SEBENARNYA hanya satu kotak yang
  /// bergeser naik/turun di dalam lekukan; tebal tepi bawah (bayangan gelap)
  /// & sorot atas yang berubah mengikuti posisi membuatnya tampak seperti
  /// saklar fisik yang ditekan. Terang = kotak di atas (tepi tebal di bawah),
  /// gelap = kotak turun (tepi menipis).
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dur = AppMotion.dur(context, AppMotion.medium);
    return Semantics(
      button: true,
      label: dark ? 'Ganti ke mode terang' : 'Ganti ke mode gelap',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 52,
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF2A2623) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant, width: 0.8),
            boxShadow: _sh(const [
              BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 8,
                  offset: Offset(0, 3)),
            ]),
          ),
          alignment: Alignment.center,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: dark ? 1.0 : 0.0),
            duration: dur,
            curve: AppMotion.easeOutBack,
            builder: (context, t, _) {
              final dy = (t - 0.5) * 8; // -4 (atas) .. +4 (bawah)
              final lip = 3.0 - 1.5 * t; // tebal tepi bawah menipis saat turun
              final well = Color.lerp(
                  const Color(0xFFE2DCCC), const Color(0xFF161412), t)!;
              return Container(
                width: 30,
                height: 44,
                decoration: BoxDecoration(
                  color: well,
                  borderRadius: BorderRadius.circular(11),
                  // Lekukan: tepi dalam atas sedikit lebih gelap (inset).
                  border: Border.all(
                      color: Color.lerp(
                          const Color(0xFFDDD6C6), const Color(0xFF0B0A09), t)!,
                      width: 0.8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(0, dy),
                      child: SizedBox(
                        width: 22,
                        height: 26,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Tebal/tepi kotak (bagian yang tampak "tenggelam").
                            Positioned(
                              left: 0,
                              right: 0,
                              top: lip,
                              bottom: -lip,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(9),
                                  color: Color.lerp(const Color(0xFFCFC6B0),
                                      const Color(0xFF050404), t),
                                ),
                              ),
                            ),
                            // Muka kotak.
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(9),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Color(
                                            dark ? 0x80000000 : 0x2E000000),
                                        blurRadius: 3,
                                        offset: const Offset(0, 1.5)),
                                  ],
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: dark
                                        ? const [
                                            Color(0xFF3B3632),
                                            Color(0xFF26221F)
                                          ]
                                        : const [
                                            Color(0xFFFFFFFF),
                                            Color(0xFFEFE9DA)
                                          ],
                                  ),
                                  border: Border.all(
                                      color: dark
                                          ? const Color(0xFF4A443E)
                                          : const Color(0xFFFFFFFF),
                                      width: 0.8),
                                ),
                                child: Center(
                                  child: Icon(
                                      dark
                                          ? Icons.nightlight_round
                                          : Icons.wb_sunny_rounded,
                                      size: 12,
                                      color: dark
                                          ? const Color(0xFF9FB4E8)
                                          : const Color(0xFFE59A2E)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Hint kolom cari yang bergilir seperti placeholder katalog HTML: "Cari
/// <b>Nama Produk</b>" berganti tiap ~3,4 dtk. Dua lapis (lama & baru)
/// digerakkan SATU controller: yang lama naik + pudar, yang baru naik dari
/// bawah + muncul, di dalam jendela terpotong setinggi satu baris - tanpa
/// geser horizontal. Tanpa saran -> 'Cari produk...' statis (tanpa timer).
/// "Kurangi animasi" -> berganti langsung.
class _RotatingHint extends StatefulWidget {
  const _RotatingHint({required this.names, required this.onChanged});
  final List<String> names;
  final ValueChanged<String?> onChanged;

  @override
  State<_RotatingHint> createState() => _RotatingHintState();
}

class _RotatingHintState extends State<_RotatingHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  Timer? _timer;
  int _i = 0;
  int? _prev;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 620))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _prev = null);
        }
      });
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
  }

  @override
  void didUpdateWidget(_RotatingHint old) {
    super.didUpdateWidget(old);
    if (old.names.join('|') != widget.names.join('|')) {
      _i = 0;
      _prev = null;
      _c.value = 0;
      _start();
      WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    }
  }

  void _start() {
    _timer?.cancel();
    if (widget.names.length < 2 || !PerfDiag.s.hintRotate) return;
    _timer = Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (!mounted) return;
      final next = (_i + 1) % widget.names.length;
      setState(() {
        _prev = _i;
        _i = next;
      });
      if (AppMotion.reduced(context)) {
        _c.value = 1;
        _prev = null;
      } else {
        _c.forward(from: 0);
      }
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
    _c.dispose();
    super.dispose();
  }

  Widget _line(BuildContext context, String name) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 15, color: cs.onSurfaceVariant);
    return Text.rich(
      TextSpan(style: style, children: [
        const TextSpan(text: 'Cari '),
        TextSpan(
            text: name,
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.names.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('Cari produk\u2026',
            style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
      );
    }
    final cur = widget.names[_i % widget.names.length];
    // Tinggi baris DIUKUR dari gaya & skala font sebenarnya (Ukuran Teks besar
    // + line-height font aplikasi) - bukan angka tetap - supaya huruf tidak
    // terpotong jendela. Jendela = 2 baris, dipusatkan di pil.
    final measure = TextPainter(
      text: TextSpan(
          text: 'Cari Xg',
          style: DefaultTextStyle.of(context).style.merge(
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final lineH = measure.height.ceilToDouble() + 2;
    measure.dispose();
    // OverflowBox: Stack induk hanya setinggi TextField (~18dp) - tanpa ini
    // jendela terjepit setinggi itu dan huruf terpotong (akar bug 'hint
    // terpotong').
    return OverflowBox(
      alignment: Alignment.center,
      minHeight: 0,
      maxHeight: lineH * 2,
      child: ClipRect(
        child: SizedBox(
          height: lineH * 2,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = Curves.easeInOutCubic.transform(_c.value);
              final animating = _prev != null;
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  if (animating)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: lineH / 2,
                      height: lineH,
                      child: Opacity(
                        opacity: (1 - t).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, -lineH * 0.6 * t),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _line(context,
                                widget.names[_prev! % widget.names.length]),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: lineH / 2,
                    height: lineH,
                    child: Opacity(
                      opacity: animating ? t.clamp(0.0, 1.0) : 1,
                      child: Transform.translate(
                        offset:
                            Offset(0, animating ? lineH * 0.6 * (1 - t) : 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _line(context, cur),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
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
      // Jarak ke tepi kiri/kanan/bawah (kartu melayang, bukan bar penuh).
      padding: EdgeInsets.fromLTRB(
          14, 6, 14, 12 + MediaQuery.paddingOf(context).bottom),
      child: Container(
        key: const Key('modern-cart-bar'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: cs.outlineVariant.withOpacity(dark ? 0.9 : 1), width: 1),
          boxShadow: _sh([
            BoxShadow(
              color: dark ? const Color(0x99000000) : const Color(0x385A3C1E),
              blurRadius: 22,
              offset: const Offset(0, 6),
            ),
          ]),
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
                                // Nominal mengecil otomatis (satu baris)
                                // mengikuti panjang angka.
                                BumpOnChange(
                                  value: total,
                                  peak: 1.08,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      formatRupiah(total),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: AppTheme.numStyle(context,
                                          size: 22, weight: FontWeight.w700),
                                    ),
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
    final maxH = MediaQuery.sizeOf(context).height * 0.78;

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

/// Pembungkus kartu lembut untuk baris produk gaya Baru: latar kartu, sudut
/// 16, garis tipis + bayangan hangat; isi (avatar, nama, stepper, varian)
/// TIDAK diubah — logikanya tetap di `_ProductListTile`.
class _ModernTileCard extends StatelessWidget {
  const _ModernTileCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Diagnostik: kartu polos (tanpa bayangan & potong sudut) - hanya garis.
    if (!PerfDiag.s.tileDecor) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant, width: 0.6),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant, width: 0.6),
        boxShadow: _sh([
          BoxShadow(
            color: dark ? const Color(0x40000000) : const Color(0x155A3C1E),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ]),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}
