import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import 'payment_qris_view.dart';

/// Sheet pelunasan / tambah bayar hutang — kalkulator gaya checkout, plus
/// pemilihan metode bayar & tampilan QRIS/metadata langsung di dalamnya.
///
/// Mengembalikan `(amount, method, methodName)` atau null bila dibatalkan.
/// [method] = `PaymentMethod.type` metode terpilih (konsisten dgn cara
/// transaksi awal menyimpan `paymentMethod` — lihat payment_screen
/// `_selectedMethodType`). [methodName] = nama SPESIFIK metode terpilih
/// (mis. "GoPay") — null utk Tunai/metode tanpa nama spesifik, dipakai
/// caller utk snapshot `TransactionPayments.methodName`. Default =
/// 'tunai'/null (metode Tunai selalu ada & tak bisa dinonaktifkan).
///
/// Menggantikan `showDebtPaymentDialog` (AlertDialog sempit) di SEMUA
/// pemanggil — pelunasan satu nota (struk/riwayat/daftar transaksi) maupun
/// pelunasan gabungan banyak nota (Buku Hutang, `settleMergedDebt` yang
/// membagi FIFO). Bentuknya sheet, bukan dialog, karena `AlertDialog`
/// dibungkus `IntrinsicWidth` oleh framework & lebarnya dipotong
/// inset/content padding — QR 200px + metadata + keypad TIDAK muat di sana
/// (file dialog lama sendiri sudah pernah kena overflow 3-tombol).
Future<({int amount, String method, String? methodName})?> showDebtPaymentSheet(
  BuildContext context,
  AppDatabase db, {
  required int remaining,
  String title = 'Lunasi Transaksi',
  bool prefillRemaining = true,
}) async {
  final methods = await (db.select(db.paymentMethods)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => drift.OrderingTerm.asc(t.sortOrder)]))
      .get();
  // Mode QR mengikuti setting toko yang sama dgn checkout — TAPI di sini
  // default awalnya SELALU statis (lihat dok `_DebtPaymentSheet._qrDynamic`).
  final qrisEnabled = (await db.getSetting('qris_dynamic_enabled')) != '0';
  if (!context.mounted) return null;
  return showModalBottomSheet<
      ({int amount, String method, String? methodName})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _DebtPaymentSheet(
      remaining: remaining,
      title: title,
      methods: methods,
      prefillRemaining: prefillRemaining,
      qrisToggleAllowed: qrisEnabled,
    ),
  );
}

class _DebtPaymentSheet extends StatefulWidget {
  const _DebtPaymentSheet({
    required this.remaining,
    required this.title,
    required this.methods,
    required this.prefillRemaining,
    required this.qrisToggleAllowed,
  });

  final int remaining;
  final String title;
  final List<PaymentMethod> methods;
  final bool prefillRemaining;

  /// Setting toko `qris_dynamic_enabled` (dipakai bersama checkout). Bila
  /// OFF, toggle statis/dinamis tidak ditawarkan sama sekali — toko itu
  /// memang memilih tidak memakai QR ber-nominal.
  final bool qrisToggleAllowed;

  @override
  State<_DebtPaymentSheet> createState() => _DebtPaymentSheetState();
}

class _DebtPaymentSheetState extends State<_DebtPaymentSheet> {
  /// Nominal yang diketik kasir. Dipegang sbg int (bukan TextEditingController)
  /// karena input via keypad sheet, bukan keyboard — sama seperti kalkulator
  /// checkout (`_CashKeypadSheet._tendered`).
  late int _amount = widget.prefillRemaining ? widget.remaining : 0;

  /// Metode terpilih. null = Tunai (default). Tunai SENGAJA tidak pernah
  /// jadi "terpilih eksplisit": ia gerbang masuk ke metode lain, dan tidak
  /// punya metadata untuk ditonjolkan — jadi menyembunyikan chip lain saat
  /// Tunai aktif cuma bikin kasir tidak bisa berpindah metode.
  String? _selectedId;

  /// Mode QR saat metode QRIS dipilih. SELALU mulai dari STATIS walau toko
  /// memakai QR ber-nominal: di alur pelunasan, nominalnya justru yang belum
  /// diketahui — kasir mengetiknya dulu di mode statis (keypad tersedia),
  /// baru menggeser ke dinamis supaya angka itu terpatri di QR. Beda dari
  /// checkout, di mana totalnya sudah pasti sejak awal.
  bool _qrDynamic = false;

  /// QR statis ditaruh di ATAS nominal (supaya keypad tetap menempel di
  /// bawah, area jempol), TAPI yang terlihat lebih dulu tetap keypad —
  /// kasir menggulir ke atas saat mau menunjukkan QR ke pelanggan. Kunci &
  /// controller ini dipakai untuk melompati blok QR sekali, tepat setelah
  /// blok itu dirender.
  final _qrBlockKey = GlobalKey();
  final _scroll = ScrollController();

  /// Akumulasi overscroll (drag ke bawah saat sudah di posisi paling atas)
  /// selama SATU gesture drag. `showModalBottomSheet` bawaan cuma
  /// menghubungkan swipe-turun ke `Navigator.pop` kalau isi TIDAK
  /// scrollable (mis. state QRIS statis yang lebih tinggi dari layar) —
  /// begitu ada `SingleChildScrollView` yang benar-benar overflow, gesture
  /// arena selalu dimenangkan scrollable itu, dismiss-drag bawaan tidak
  /// pernah kebagian giliran. `OverscrollNotification` tetap muncul walau
  /// scroll-nya `ClampingScrollPhysics` (posisi tidak bergerak, tapi
  /// notifikasi overscroll tetap dikirim) — dipakai di sini utk pop manual
  /// begitu tarikan ke bawah melewati ambang batas, meniru perilaku
  /// `DraggableScrollableSheet`.
  double _dragOverscroll = 0;

  void _scrollPastQrBlock() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _scroll;
      final ctx = _qrBlockKey.currentContext;
      if (!c.hasClients || ctx == null || !mounted) return;
      final h = ctx.size?.height ?? 0;
      if (h <= 0) return;
      c.jumpTo(h.clamp(0.0, c.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  PaymentMethod? get _selected => _selectedId == null
      ? null
      : widget.methods.where((m) => m.id == _selectedId).firstOrNull;

  String get _selectedType => _selected?.type ?? 'tunai';

  bool get _isQris => _selectedType == 'qris';

  /// Nominal yang dipatri ke QR dinamis: angka yang diketik kasir, atau —
  /// bila belum mengetik apa pun — sisa tagihan penuh. Tanpa fallback ini,
  /// menggeser toggle sebelum mengetik menghasilkan QR bernominal nol yang
  /// tidak sah.
  int get _qrAmount => _amount > 0 ? _amount : widget.remaining;

  /// Keypad disembunyikan HANYA saat QR dinamis aktif — di sana nominalnya
  /// sudah terkunci di dalam QR, jadi tidak ada yang perlu diketik lagi.
  bool get _showKeypad => !(_isQris && _qrDynamic);

  int get _change =>
      _amount > widget.remaining ? _amount - widget.remaining : 0;
  int get _shortfall => _amount > 0 && _amount < widget.remaining
      ? widget.remaining - _amount
      : 0;

  void _press(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _amount = 0;
        case '⌫':
          _amount = _amount ~/ 10;
        case '00':
          _amount = (_amount * 100).clamp(0, 99999999);
        case '000':
          _amount = (_amount * 1000).clamp(0, 99999999);
        default:
          final d = int.tryParse(key);
          if (d != null) _amount = (_amount * 10 + d).clamp(0, 99999999);
      }
    });
  }

  /// Tap chip metode. Metode yang SEDANG terpilih diketuk lagi → batal,
  /// kembali ke Tunai & chip lain muncul lagi. Tunai sendiri tidak pernah
  /// meng-collapse apa pun.
  void _tapMethod(PaymentMethod m) {
    setState(() {
      if (_selectedId == m.id) {
        _selectedId = null;
        _qrDynamic = false;
      } else if (m.type == 'tunai') {
        _selectedId = null;
        _qrDynamic = false;
      } else {
        _selectedId = m.id;
        // Selalu mulai statis tiap kali QRIS dipilih (lihat dok `_qrDynamic`).
        _qrDynamic = false;
        if (m.type == 'qris') _scrollPastQrBlock();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _selected;
    final collapsed = selected != null; // ada metode non-tunai terpilih

    final qris = _isQris && (selected?.qrValue?.trim().isNotEmpty ?? false)
        ? resolveQrisPayload(
            staticPayload: selected!.qrValue!,
            amount: _qrAmount,
            dynamicMode: _qrDynamic,
          )
        : null;

    final ctx = context;
    // Tinggi sheet mengikuti ISI (mainAxisSize.min), bukan pecahan tetap
    // layar spt `DraggableScrollableSheet` — persis pola kalkulator checkout
    // (`_CashKeypadSheet`). Ini yang membuat jarak keypad->tombol bawah
    // PERMANEN: tombol ikut mengalir tepat di bawah keypad (bukan dipatok
    // ke dasar sheet), jadi berubahnya isi di ATAS keypad (mis. metadata
    // metode muncul/hilang) menggeser keduanya BERSAMAAN tanpa mengubah
    // jaraknya. `Flexible` + scroll cuma aktif kalau isi melebihi layar
    // (kasus QRIS statis: QR + keypad sekaligus).
    return Material(
      color: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle (juga area seret utk menutup sheet) ──────────────
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 10),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is OverscrollNotification && n.dragDetails != null) {
                    _dragOverscroll += n.overscroll;
                    if (_dragOverscroll < -60) {
                      Navigator.of(context).maybePop();
                    }
                  } else if (n is ScrollEndNotification) {
                    _dragOverscroll = 0;
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(
                      16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // QR STATIS ditaruh PALING ATAS (di atas nominal) supaya
                      // keypad tetap menempel di bawah — area jempol kasir.
                      // Awalnya di luar layar; kasir menggulir ke atas untuk
                      // menunjukkannya ke pelanggan.
                      if (qris != null && !_qrDynamic)
                        Column(
                          key: _qrBlockKey,
                          children: [
                            Center(child: QrisQrBox(data: qris.data)),
                            const SizedBox(height: 6),
                            Text(
                              'QR statis — pelanggan mengetik sendiri '
                              'nominalnya. Geser tombol di bawah ke "Nominal" '
                              'agar jumlahnya terkunci di QR.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11, color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),

                      // ── Sisa tagihan ────────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(ctx).textTheme.titleSmall),
                          ),
                          const SizedBox(width: 8),
                          // Dua Text terpisah (bukan Text.rich) supaya nominal
                          // sisa bisa di-assert langsung di widget test — angka
                          // ini yang nanti dicatat sbg pembayaran, jadi wajib
                          // terjaga (lihat `tx_history_net_sisa_test.dart`).
                          Text('Sisa tagihan ',
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13)),
                          Text(formatRupiah(widget.remaining),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: scheme.onSurface)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ── Metode bayar (+ metadata segaris saat terpilih) ──
                      _MethodPicker(
                        methods: widget.methods,
                        selectedId: _selectedId,
                        collapsed: collapsed,
                        onTap: _tapMethod,
                      ),
                      const SizedBox(height: 10),

                      // ── Nominal diterima ────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Dibayar',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                          Text(formatRupiah(_amount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 22)),
                        ],
                      ),
                      if (_amount > 0) ...[
                        const SizedBox(height: 8),
                        _StatusPill(
                            change: _change,
                            shortfall: _shortfall,
                            isDark: isDark),
                      ],
                      const SizedBox(height: 10),

                      // ── Keypad ⇄ QR dinamis ─────────────────────────────
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _showKeypad
                              ? Column(
                                  key: const ValueKey('keypad'),
                                  children: [
                                    _QuickAmountChips(
                                      remaining: widget.remaining,
                                      // "Uang Pas" hanya perlu dimunculkan
                                      // sbg chip saat slot tombol kiri-bawah
                                      // sedang dipakai toggle QR — kalau
                                      // tidak, ia sudah ada di sana.
                                      includeUangPas: _isQris &&
                                          widget.qrisToggleAllowed &&
                                          qris != null,
                                      onPick: (v) =>
                                          setState(() => _amount = v),
                                    ),
                                    const SizedBox(height: 8),
                                    _Keypad(onPress: _press),
                                  ],
                                )
                              : Column(
                                  key: const ValueKey('qr'),
                                  children: [
                                    Center(
                                        child:
                                            QrisQrBox(data: qris?.data ?? '')),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Nominal ${formatRupiah(_qrAmount)} sudah '
                                      'terkunci di QR — pelanggan tinggal scan. '
                                      'Untuk mengubahnya, geser kembali ke '
                                      '"Statis".',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      // ── Baris tombol ────────────────────────────────────
                      // Jarak ke keypad SENGAJA konstan 10px & ikut mengalir
                      // di dalam scroll (bukan dipatok ke dasar sheet) —
                      // sama persis dgn kalkulator checkout, supaya posisinya
                      // relatif terhadap keypad tidak pernah bergeser saat
                      // isi di atasnya berubah.
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // "Uang Pas" DIGANTI toggle Statis/Nominal saat QRIS
                          // dipilih: QR dinamis nominalnya sudah pas by definition,
                          // sedangkan QR statis justru dipakai untuk nominal bebas.
                          if (_isQris &&
                              widget.qrisToggleAllowed &&
                              qris != null)
                            _QrModeToggle(
                              dynamicMode: _qrDynamic,
                              onChanged: (v) => setState(() {
                                _qrDynamic = v;
                                if (!v) _scrollPastQrBlock();
                              }),
                            )
                          else
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 52),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16)),
                              onPressed: () =>
                                  setState(() => _amount = widget.remaining),
                              child: const Text('Uang Pas'),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.payGreen,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _payEnabled
                                    ? () => Navigator.of(ctx).pop((
                                          amount: _payAmount,
                                          method: _selectedType,
                                          methodName: _selected?.name,
                                        ))
                                    : null,
                                child: Text(_payLabel,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Di mode QR dinamis nominalnya = yang terpatri di QR (`_qrAmount`),
  /// bukan `_amount` mentah — kalau kasir belum mengetik apa pun, QR sudah
  /// terlanjur membawa sisa penuh, jadi nota HARUS dicatat sebesar itu juga.
  int get _payAmount => (_isQris && _qrDynamic) ? _qrAmount : _amount;

  bool get _payEnabled => _payAmount > 0;

  String get _payLabel {
    if (_isQris && _qrDynamic) return 'Bayar ${formatRupiah(_qrAmount)}';
    if (_shortfall > 0) return 'Bayar · Sisa ${formatRupiah(_shortfall)}';
    if (_change > 0) return 'Bayar · Kembali ${formatRupiah(_change)}';
    return 'Bayar';
  }
}

/// Baris chip metode bayar. Saat sebuah metode non-tunai dipilih, chip lain
/// menghilang halus & chip terpilih bergeser ke kiri — sisa ruang di kanannya
/// dipakai metadata (no. rekening/akun + tombol salin) supaya tidak menambah
/// baris baru.
class _MethodPicker extends StatelessWidget {
  const _MethodPicker({
    required this.methods,
    required this.selectedId,
    required this.collapsed,
    required this.onTap,
  });

  final List<PaymentMethod> methods;
  final String? selectedId;
  final bool collapsed;
  final ValueChanged<PaymentMethod> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = methods.where((m) => m.id == selectedId).firstOrNull;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: collapsed && selected != null
            ? Row(
                key: ValueKey('sel-${selected.id}'),
                children: [
                  ChoiceChip(
                    label: Text(selected.name),
                    selected: true,
                    selectedColor: scheme.primaryContainer,
                    avatar: Icon(paymentMethodIcon(selected.type), size: 16),
                    onSelected: (_) => onTap(selected),
                  ),
                  if (hasTextMetadata(selected)) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(paymentMetadataLabel(selected.type),
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurfaceVariant)),
                                Text(selected.data!.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_outlined, size: 18),
                            tooltip: 'Salin',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => copyPaymentMetadata(
                                context, selected.data!.trim()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              )
            : Wrap(
                key: const ValueKey('all'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in methods)
                    ChoiceChip(
                      label: Text(m.name),
                      selected: m.type == 'tunai' && selectedId == null,
                      selectedColor: scheme.primaryContainer,
                      onSelected: (_) => onTap(m),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Toggle Statis ⇄ Nominal, menggantikan "Uang Pas" saat metode QRIS aktif.
class _QrModeToggle extends StatelessWidget {
  const _QrModeToggle({required this.dynamicMode, required this.onChanged});
  final bool dynamicMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Ini TOMBOL AKSI, bukan indikator status: labelnya menyebut TUJUAN
    // (ke mana perpindahannya), bukan keadaan sekarang. Sedang di mode
    // statis → tertulis "Nominal" (artinya: tekan utk ke mode nominal).
    // Beda dari toggle QR di layar checkout yang memakai `Switch` — di sana
    // label memang menyebut keadaan sekarang, karena itu memang lazimnya
    // switch. Ikonnya ikut menyebut tujuan yang sama supaya tidak bertolak
    // belakang dgn teksnya.
    //
    // OutlinedButton BIASA (bukan `.icon`) — `.icon` menghasilkan subclass
    // privat sehingga `find.byType(OutlinedButton)` di widget test tidak
    // pernah match, dan tombol ini menggantikan slot "Uang Pas" yang juga
    // OutlinedButton polos.
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 12)),
      onPressed: () => onChanged(!dynamicMode),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(dynamicMode ? Icons.qr_code_2_outlined : Icons.lock_outline,
              size: 18),
          const SizedBox(width: 6),
          Text(dynamicMode ? 'Statis' : 'Nominal',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: scheme.primary)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.change, required this.shortfall, required this.isDark});
  final int change;
  final int shortfall;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    if (change > 0) {
      bg = AppTheme.changeBg(isDark);
      fg = AppTheme.changeFg(isDark);
      label = 'Kembalian';
    } else if (shortfall > 0) {
      bg = AppTheme.debtBg(isDark);
      fg = AppTheme.debtFg(isDark);
      label = 'Sisa Hutang';
    } else {
      bg = AppTheme.changeBg(isDark);
      fg = AppTheme.changeFg(isDark);
      label = '✓ Pas';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
          if (change > 0 || shortfall > 0)
            Text(formatRupiah(change > 0 ? change : shortfall),
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16, color: fg)),
        ],
      ),
    );
  }
}

class _QuickAmountChips extends StatelessWidget {
  const _QuickAmountChips(
      {required this.remaining,
      required this.onPick,
      required this.includeUangPas});
  final int remaining;
  final ValueChanged<int> onPick;
  final bool includeUangPas;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (includeUangPas)
          ActionChip(
            label: const Text('Uang Pas'),
            onPressed: () => onPick(remaining),
          ),
        ...{10000, 20000, 50000, 100000}
            .where((d) => d >= remaining)
            .take(3)
            .map((d) => ActionChip(
                  label: Text(formatRupiah(d)),
                  onPressed: () => onPick(d),
                )),
      ],
    );
  }
}

/// Keypad angka — tata letak & warna SAMA dgn kalkulator checkout
/// (`payment_screen.dart` `_Keypad`) supaya kasir tidak perlu belajar dua
/// pola berbeda untuk aksi yang sama.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onPress});
  final ValueChanged<String> onPress;

  static const _rows = [
    ['1', '2', '3', '⌫'],
    ['4', '5', '6', 'C'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blueLight = [
      const Color(0xFFE7EEF5),
      const Color(0xFFD3E1EE),
      const Color(0xFFBFD4E7),
    ];
    final blueDark = [
      const Color(0x268AABC4),
      const Color(0x408AABC4),
      const Color(0x598AABC4),
    ];

    Color? keyBg(String k, bool isAction) {
      if (isAction) return scheme.surfaceContainerHighest;
      final blueIdx = k == '0' ? 0 : (k == '00' ? 1 : (k == '000' ? 2 : -1));
      if (blueIdx >= 0) return (isDark ? blueDark : blueLight)[blueIdx];
      return AppTheme.changeBg(isDark);
    }

    Color keyFg(String k, bool isAction) {
      if (isAction) return scheme.onSurfaceVariant;
      final isZero = k == '0' || k == '00' || k == '000';
      return isZero ? AppTheme.scanFg(isDark) : AppTheme.changeFg(isDark);
    }

    Widget key(String k) {
      final isAction = k == 'C' || k == '⌫';
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: keyBg(k, isAction),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: scheme.outlineVariant, width: 0.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onPress(k),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(k,
                      style: TextStyle(
                        fontSize: k.length > 1 && !isAction ? 16 : 20,
                        fontWeight: FontWeight.w600,
                        color: keyFg(k, isAction),
                      )),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in _rows) Row(children: [for (final k in row) key(k)]),
        Row(children: [key('0'), key('00'), key('000')]),
      ],
    );
  }
}
