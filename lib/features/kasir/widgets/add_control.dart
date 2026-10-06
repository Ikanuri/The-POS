import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Tombol "+" yang berubah jadi lingkaran berisi jumlah saat produk ada di
/// keranjang. Tap menambah 1 (produk satuan tunggal) atau membuka modal
/// (produk multi-satuan). Dipakai di kartu/baris produk kasir DAN di baris
/// item keranjang (`cart_sheet.dart`) supaya gaya stepper konsisten di
/// seluruh alur kasir.
class AddControl extends StatefulWidget {
  const AddControl({
    super.key,
    required this.qty,
    required this.onTap,
    this.onMinus,
    this.onSetQty,
    this.size = 34,
  });

  final double qty;
  final VoidCallback onTap;
  final VoidCallback? onMinus;

  /// "Revolver": menggeser tombol "+" ke KIRI memunculkan pita bertanda
  /// (seperti tuner radio) untuk input qty cepat — geser kiri = qty naik,
  /// balik ke kanan = turun (minimum 1; menghapus tetap lewat tombol "-").
  /// Menerima qty ABSOLUT (bukan selisih) supaya aman dipanggil beberapa kali
  /// per frame tanpa terpengaruh closure basi. null = fitur nonaktif.
  final void Function(double qty)? onSetQty;
  final double size;

  @override
  State<AddControl> createState() => _AddControlState();

  /// Permintaan user: stepper yang baru saja di-tap "tetap besar" (pijakan
  /// jempol, supaya tap berikutnya — mis. nambah qty lagi — tidak gampang
  /// missclick) sampai user tap AREA LAIN atau scroll, BUKAN cuma sesaat
  /// selagi ditekan. Karena stepper dirender berulang di banyak kartu/baris
  /// berbeda (widget baru dibuat tiap rebuild), "mana yang aktif" dilacak
  /// via instance State (stabil selama widget tetap di tree), disimpan di
  /// sini (satu per app — cukup, cuma 1 stepper yang relevan aktif kapan
  /// saja) alih-alih di-plumb sbg id ke semua pemanggil.
  static final ValueNotifier<State<AddControl>?> activeStepper =
      ValueNotifier(null);

  /// Dipanggil dari layar pemanggil (kasir_screen.dart/cart_sheet.dart) saat
  /// area LAIN di-tap atau list di-scroll, supaya stepper yang lagi
  /// "membesar" kembali normal.
  static void clearActive() {
    activeStepper.value = null;
    _pointerDownOnStepper = false;
  }
}

// Pijakan jempol: stepper yang habis di-tap membesar & TETAP besar (lihat
// AddControl.activeStepper) sampai di-nonaktifkan dari luar.
const _kActiveScale = 1.15;
const _kActiveScaleDuration = Duration(milliseconds: 150);

// Di-set true oleh Listener di dalam [AddControl] saat pointer turun TEPAT di
// atas sebuah stepper, lalu dibaca-dan-direset oleh [StepperActiveScope].
// Guna: saat user menekan lagi stepper yang SAMA (mis. tambah qty berkali-
// kali), scope TIDAK ikut menonaktifkannya di event pointer-down — kalau
// dinonaktifkan sekejap lalu diaktifkan lagi saat tap dikenali (event up),
// angka qty "berkedip" pindah sisi. Karena pointer-down di-dispatch dari
// target (descendant) ke root, Listener AddControl SELALU jalan sebelum
// Listener scope, jadi flag ini pasti sudah ter-set saat scope membacanya.
bool _pointerDownOnStepper = false;

class _AddControlState extends State<AddControl> {
  // Item 43 — sisi mana angka qty ditampilkan SELAGI stepper aktif. true =
  // angka pindah ke tombol minus (kiri), tombol plus (kanan) jadi ikon "+"
  // polos (dipakai setelah tombol "+" ditekan). false = normal (angka di
  // tombol +/kanan). Hanya berpengaruh saat stepper aktif — begitu tidak
  // aktif, rendering selalu normal (lihat `qtyOnLeft` di build).
  bool _qtyOnLeft = false;

  // ── Revolver (geser "+" ke kiri) ──────────────────────────────────────────
  final LayerLink _dialLink = LayerLink();
  OverlayEntry? _dialOverlay;
  final ValueNotifier<double> _dialValue = ValueNotifier(0);
  double _dialBase = 0;
  double _dialAcc = 0;
  double _dialVel = 0;
  bool _dialing = false;

  // Satu langkah qty = sekian px geser pelan; makin cepat jari, makin besar
  // pengali (lihat `_dialUpdate`).
  static const _kPxPerStep = 11.0;
  static const _kDialMax = 9999.0;

  bool get _dialEnabled =>
      widget.onSetQty != null && widget.qty >= 0 && widget.qty % 1 == 0;

  void _dialStart(DragStartDetails d, double circleSize) {
    if (!_dialEnabled) return;
    _dialing = true;
    _dialBase = widget.qty;
    _dialAcc = 0;
    _dialVel = 0;
    _dialLastTs = d.sourceTimeStamp?.inMilliseconds ?? 0;
    _dialValue.value = math.max(1, widget.qty);
    _activate();
    final box = context.findRenderObject() as RenderBox?;
    final right = box == null
        ? MediaQuery.of(context).size.width
        : box.localToGlobal(Offset(box.size.width, 0)).dx;
    final width = math.min(270.0, right - circleSize - 14);
    if (width < 120) {
      _dialing = false;
      return;
    }
    _dialOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _dialLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.centerRight,
          followerAnchor: Alignment.centerRight,
          offset: Offset(-(circleSize + 6), 0),
          child: _DialPill(value: _dialValue, width: width, height: circleSize),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_dialOverlay!);
    HapticFeedback.selectionClick();
  }

  void _dialUpdate(DragUpdateDetails d) {
    if (!_dialing) return;
    final dx = d.delta.dx;
    final dtMs = math.max(
        1, (d.sourceTimeStamp ?? const Duration(milliseconds: 16)).inMilliseconds -
            _dialLastTs);
    _dialLastTs = (d.sourceTimeStamp ?? Duration.zero).inMilliseconds;
    final v = dx.abs() / math.min(dtMs, 50);
    _dialVel = _dialVel * 0.7 + v * 0.3;
    // Pelan (<~0.4 px/ms) = 1x; makin cepat makin besar, dibatasi 6x.
    final mult = 1 + math.min(5.0, math.max(0.0, _dialVel - 0.4) * 3.5);
    _dialAcc += (-dx) * mult / _kPxPerStep;
    // Jangan menumpuk "utang" geser di bawah batas minimum/maksimum.
    _dialAcc = _dialAcc.clamp(1 - _dialBase, _kDialMax - _dialBase);
    final next = (_dialBase + _dialAcc).round().clamp(1, _kDialMax.toInt());
    if (next.toDouble() != _dialValue.value) {
      _dialValue.value = next.toDouble();
      HapticFeedback.selectionClick();
      widget.onSetQty!(next.toDouble());
    }
  }

  int _dialLastTs = 0;

  void _dialEnd([DragEndDetails? _]) {
    if (!_dialing) return;
    _dialing = false;
    _dialOverlay?.remove();
    _dialOverlay = null;
    if (mounted) setState(() => _qtyOnLeft = true);
  }

  @override
  void dispose() {
    _dialOverlay?.remove();
    _dialOverlay = null;
    _dialValue.dispose();
    super.dispose();
  }

  void _activate() => AddControl.activeStepper.value = this;

  void _handleTap() {
    _activate();
    // Tombol yang BARU ditekan (plus) jadi ikon polos → angka pindah ke sisi
    // minus. setState WAJIB: kalau stepper sudah aktif, `_activate()` men-set
    // notifier ke nilai sama (this) → ValueNotifier TIDAK memberitahu, jadi
    // perpindahan angka tak akan ter-render tanpa setState eksplisit ini.
    setState(() => _qtyOnLeft = true);
    widget.onTap();
  }

  void _handleMinus() {
    _activate();
    // Tombol minus yang baru ditekan jadi ikon polos → angka kembali ke sisi
    // plus (kanan).
    setState(() => _qtyOnLeft = false);
    widget.onMinus?.call();
  }

  /// Label angka qty bulat, disusutkan `FittedBox` agar qty desimal panjang
  /// (mis. "0.25", produk timbang) tetap muat dalam lingkaran, bukan
  /// terpotong/meluber.
  Widget _qtyLabel(String label, double circleSize,
          {Color color = Colors.white}) =>
      Padding(
        padding: EdgeInsets.all(circleSize * 0.12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: circleSize * 0.40,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final qty = widget.qty;
    final size = widget.size;
    final inCart = qty > 0;
    final label = qty % 1 == 0 ? qty.toInt().toString() : qty.toString();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final circleSize = size + 4;
    final minusSize = size - 2;
    // Revisi susulan (permintaan user): lingkaran solid (hijau/merah) di
    // state "sudah di keranjang" DIHILANGKAN TOTAL — hanya angka/ikon yang
    // tampil mengambang, TANPA latar. Cakupan sentuh (ukuran `circleSize`/
    // `minusSize`) TIDAK ikut mengecil, cuma bobot visualnya yang berkurang
    // (sejalan dgn revisi idle sebelumnya: "terlalu ramai" saat semua kartu
    // grid punya lingkaran solid sekaligus). Warna kini ditentukan oleh SISI
    // (kanan/"+" = hijau, kiri/"−" = merah) — BUKAN oleh jenis kontennya
    // (ikon vs angka) — jadi saat qty "pindah sisi" (lihat `qtyOnLeft`),
    // warnanya ikut berpindah, bukan menempel ke angka.
    final greenSlot = AppTheme.changeFg(isDark);
    final redSlot = AppTheme.debtFg(isDark);
    // SEBELUM ada di keranjang, ikon "+" polos warna netral, supaya idle
    // state tidak menyaingi info produk. Warna baru "hidup" (hijau) begitu
    // produk BENAR2 masuk keranjang. Area tap TIDAK berubah sama sekali —
    // cuma bobot visualnya.
    final idleColor = Theme.of(context).colorScheme.onSurfaceVariant;
    // Revisi susulan (permintaan user): ring putus-putus MELINGKAR dibuang,
    // diganti SATU garis putus-putus VERTIKAL di kiri tombol "+" — lebih
    // minimalis, dan yang lama dinilai "masih terlalu tegas" walau sudah
    // netral (lingkaran penuh = banyak garis sekaligus, jadi berat walau
    // warnanya redup). Garisnya sendiri pakai `outlineVariant` (token
    // pembatas paling samar di app ini — dipakai juga oleh garis batas atas
    // cart bar), BUKAN `onSurfaceVariant` yang derajatnya setara teks.
    final hairlineColor = Theme.of(context).colorScheme.outlineVariant;

    return ValueListenableBuilder<State<AddControl>?>(
      valueListenable: AddControl.activeStepper,
      builder: (context, active, _) {
        final isActive = identical(active, this);
        // Angka pindah ke sisi minus HANYA saat aktif, sudah di keranjang,
        // dan tombol terakhir yang ditekan adalah "+" (`_qtyOnLeft`). Selain
        // itu selalu normal (angka di tombol +/kanan).
        final qtyOnLeft = inCart && isActive && _qtyOnLeft;
        // Lingkaran utama (kanan) tampil "+" bila belum di keranjang ATAU
        // angka sedang dipindah ke sisi minus.
        final rightShowsPlus = !inCart || qtyOnLeft;

        // Lingkaran utama (jumlah / "+") berukuran sama baik saat kosong
        // maupun saat sudah ada di keranjang, agar tidak "melompat" ukuran —
        // TANPA latar/fill lagi, cuma kotak transparan sbg cakupan sentuh.
        final mainCircle = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onHorizontalDragStart:
              _dialEnabled ? (d) => _dialStart(d, circleSize) : null,
          onHorizontalDragUpdate: _dialEnabled ? _dialUpdate : null,
          onHorizontalDragEnd: _dialEnabled ? _dialEnd : null,
          onHorizontalDragCancel: _dialEnabled ? _dialEnd : null,
          child: AnimatedScale(
            scale: isActive ? _kActiveScale : 1.0,
            duration: _kActiveScaleDuration,
            curve: Curves.easeOut,
            child: SizedBox(
              width: circleSize,
              height: circleSize,
              child: Center(
                child: rightShowsPlus
                    ? Icon(Icons.add_rounded,
                        color: inCart ? greenSlot : idleColor,
                        // HANYA ikon "+" IDLE yang dikecilkan (permintaan
                        // user) — "+" yang muncul lagi setelah qty
                        // dipindah ke kiri (`inCart`) TETAP ukuran lama.
                        // Cakupan sentuh (SizedBox di atas) TIDAK ikut
                        // mengecil sama sekali di kedua kasus.
                        size: circleSize * (inCart ? 0.6 : 0.5))
                    : _qtyLabel(label, circleSize, color: greenSlot),
              ),
            ),
          ),
        );

        // Tandai pointer-down yang jatuh di atas stepper ini supaya
        // StepperActiveScope tidak menonaktifkannya (cegah kedip angka qty
        // saat tombol yang sama ditekan berulang). deferToChild: hanya
        // menandai bila benar-benar mengenai tombol (bukan celah antar-tombol).
        Widget markDown(Widget child) => Listener(
              behavior: HitTestBehavior.deferToChild,
              onPointerDown: (_) => _pointerDownOnStepper = true,
              child: child,
            );

        // Idle: "+" polos didampingi SATU garis putus-putus vertikal di
        // kirinya (lihat dok `hairlineColor`). Tingginya sengaja cuma
        // sebagian dari kotak stepper & rata tengah — permintaan user:
        // garis ini TIDAK boleh menyambung ke kartu/baris di bawahnya,
        // harus tetap ada jeda di atas & bawahnya.
        if (!inCart) {
          return CompositedTransformTarget(
              link: _dialLink,
              child: markDown(Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: Size(_kHairlineStroke, circleSize * 0.58),
                painter: _DashedVLinePainter(color: hairlineColor),
              ),
              const SizedBox(width: 10),
              mainCircle,
            ],
          )));
        }

        // Tombol minus: TANPA latar/fill (lihat dok `redSlot`), cakupan
        // sentuh (`minusSize`) tidak berubah. Pakai HitTestBehavior.opaque
        // agar tap tidak "tembus" ke InkWell kartu produk. Menampilkan
        // angka qty saat `qtyOnLeft` (setelah "+" ditekan), selain itu
        // ikon "-" — keduanya warna merah (warna sisi, bukan warna konten).
        final minusButton = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleMinus,
          child: AnimatedScale(
            scale: isActive ? _kActiveScale : 1.0,
            duration: _kActiveScaleDuration,
            curve: Curves.easeOut,
            child: SizedBox(
              width: minusSize,
              height: minusSize,
              child: Center(
                child: qtyOnLeft
                    ? _qtyLabel(label, minusSize, color: redSlot)
                    : Icon(Icons.remove_rounded,
                        color: redSlot, size: minusSize * 0.6),
              ),
            ),
          ),
        );

        return CompositedTransformTarget(
            link: _dialLink,
            child: markDown(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            minusButton,
            const SizedBox(width: 6),
            mainCircle,
          ],
        )));
      },
    );
  }
}

/// Pita "revolver" qty: angka besar di kiri (tidak tertutup jari yang ada di
/// tombol "+" di kanan) + penggaris bertanda yang bergeser mengikuti nilai,
/// jarum tetap di ujung kanan. Murni tampilan — logika ada di [AddControl].
class _DialPill extends StatelessWidget {
  const _DialPill(
      {required this.value, required this.width, required this.height});

  final ValueNotifier<double> value;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: ValueListenableBuilder<double>(
          valueListenable: value,
          builder: (_, v, __) => Row(
            children: [
              SizedBox(
                width: 62,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    v.toInt().toString(),
                    style: AppTheme.numStyle(context,
                        size: height * 0.62,
                        weight: FontWeight.w700,
                        color: cs.onSurface),
                  ),
                ),
              ),
              Expanded(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _RulerPainter(
                    value: v,
                    tick: cs.onSurfaceVariant,
                    needle: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter(
      {required this.value, required this.tick, required this.needle});

  final double value;
  final Color tick;
  final Color needle;

  static const gap = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final needleX = size.width - 22;
    final cy = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    final first = (value - needleX / gap).floor();
    final last = (value + (size.width - needleX) / gap).ceil();
    for (var n = first; n <= last; n++) {
      if (n < 1) continue;
      final x = needleX + (n - value) * gap;
      if (x < 0 || x > size.width) continue;
      final major = n % 10 == 0;
      final mid = n % 5 == 0;
      final h = size.height * (major ? 0.5 : mid ? 0.36 : 0.22);
      // Memudar di tepi kiri supaya penggaris tidak terpotong kasar.
      final fade = (x / 40).clamp(0.0, 1.0);
      paint.color = tick.withOpacity((major ? 0.9 : 0.55) * fade);
      canvas.drawLine(Offset(x, cy - h / 2), Offset(x, cy + h / 2), paint);
    }
    canvas.drawLine(
      Offset(needleX, cy - size.height * 0.36),
      Offset(needleX, cy + size.height * 0.36),
      Paint()
        ..color = needle
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.value != value || old.tick != tick || old.needle != needle;
}

/// Ketebalan garis rambut putus-putus idle (lihat [_DashedVLinePainter]).
/// Sengaja tipis — keluhan user: versi ring sebelumnya "masih terlalu
/// tegas" walau warnanya sudah netral.
const _kHairlineStroke = 1.5;

/// Garis putus-putus VERTIKAL di kiri tombol "+" saat idle (menggantikan
/// ring melingkar). Digambar manual (`Canvas.drawLine` berulang) karena
/// Flutter tidak punya border/garis dashed bawaan.
///
/// Jumlah segmen DIHITUNG dari tinggi yang tersedia (bukan angka tetap)
/// supaya pola dash tetap proporsional di semua ukuran stepper
/// (grid/list/varian punya `size` berbeda-beda) dan selalu berakhir rapi
/// di ujung bawah, bukan terpotong separuh dash.
class _DashedVLinePainter extends CustomPainter {
  const _DashedVLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const targetSegment = 6.0; // dash+gap idaman, dlm px logis
    final segments = (size.height / targetSegment).round().clamp(3, 20);
    final segmentHeight = size.height / segments;
    final dashHeight = segmentHeight * 0.55;
    final x = size.width / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kHairlineStroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < segments; i++) {
      final top = i * segmentHeight;
      canvas.drawLine(Offset(x, top), Offset(x, top + dashHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedVLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Bungkus area yang berisi [AddControl] (grid/list produk kasir, daftar
/// item keranjang) supaya stepper yang lagi "membesar" (`AddControl.
/// activeStepper`) otomatis kembali normal saat user tap di LUAR stepper
/// mana pun (kartu produk lain, area kosong, dst.) atau mulai scroll area
/// ini. `Listener` (bukan `GestureDetector`) SENGAJA dipakai — tidak ikut
/// gesture arena sama sekali, jadi tetap terpanggil di SETIAP pointer-down
/// dalam area ini TERMASUK yang jatuh tepat di atas sebuah `AddControl`
/// (aman: pembatalan di sini terjadi saat pointer DOWN, sedangkan
/// `AddControl` menjadikan dirinya aktif lagi saat tap-nya BENAR-BENAR
/// dikenali — event UP yang datang belakangan — jadi urutannya tidak
/// pernah balapan).
class StepperActiveScope extends StatelessWidget {
  const StepperActiveScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        // Pointer turun di atas sebuah stepper (Listener di AddControl sudah
        // jalan lebih dulu & menyalakan flag) → JANGAN nonaktifkan, cukup
        // konsumsi flag-nya. Selain itu (area kosong/kartu lain) → nonaktifkan
        // stepper yang sedang membesar.
        if (_pointerDownOnStepper) {
          _pointerDownOnStepper = false;
          return;
        }
        AddControl.clearActive();
      },
      child: NotificationListener<ScrollStartNotification>(
        onNotification: (_) {
          AddControl.clearActive();
          return false;
        },
        child: child,
      ),
    );
  }
}
