import 'dart:async';

import 'package:flutter/material.dart';

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
    this.size = 34,
  });

  final double qty;
  final VoidCallback onTap;
  final VoidCallback? onMinus;
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
  static void clearActive() => activeStepper.value = null;
}

// Item 13 — jeda anti-missclick: tap +/- yang datang terlalu rapat (jari
// sedikit geser lalu kena tombol sebelah) diabaikan, bukan diproses dobel.
const _kMisclickDebounce = Duration(milliseconds: 150);

// Pijakan jempol: stepper yang habis di-tap membesar & TETAP besar (lihat
// AddControl.activeStepper) sampai di-nonaktifkan dari luar.
const _kActiveScale = 1.15;
const _kActiveScaleDuration = Duration(milliseconds: 150);

class _AddControlState extends State<AddControl> {
  bool _blocked = false;
  Timer? _unblockTimer;

  // Item 43 — sisi mana angka qty ditampilkan SELAGI stepper aktif. true =
  // angka pindah ke tombol minus (kiri), tombol plus (kanan) jadi ikon "+"
  // polos (dipakai setelah tombol "+" ditekan). false = normal (angka di
  // tombol +/kanan). Hanya berpengaruh saat stepper aktif — begitu tidak
  // aktif, rendering selalu normal (lihat `qtyOnLeft` di build).
  bool _qtyOnLeft = false;

  @override
  void dispose() {
    _unblockTimer?.cancel();
    super.dispose();
  }

  bool _debounced() {
    if (_blocked) return true;
    _blocked = true;
    _unblockTimer?.cancel();
    _unblockTimer = Timer(_kMisclickDebounce, () => _blocked = false);
    return false;
  }

  void _activate() => AddControl.activeStepper.value = this;

  void _handleTap() {
    _activate();
    // Tombol yang BARU ditekan (plus) jadi ikon polos → angka pindah ke sisi
    // minus. setState WAJIB: kalau stepper sudah aktif, `_activate()` men-set
    // notifier ke nilai sama (this) → ValueNotifier TIDAK memberitahu, jadi
    // perpindahan angka tak akan ter-render tanpa setState eksplisit ini.
    setState(() => _qtyOnLeft = true);
    if (_debounced()) return;
    widget.onTap();
  }

  void _handleMinus() {
    _activate();
    // Tombol minus yang baru ditekan jadi ikon polos → angka kembali ke sisi
    // plus (kanan).
    setState(() => _qtyOnLeft = false);
    if (_debounced()) return;
    widget.onMinus?.call();
  }

  /// Label angka qty bulat, disusutkan `FittedBox` agar qty desimal panjang
  /// (mis. "0.25", produk timbang) tetap muat dalam lingkaran, bukan
  /// terpotong/meluber.
  Widget _qtyLabel(String label, double circleSize) => Padding(
        padding: EdgeInsets.all(circleSize * 0.12),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
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
    final bgColor = inCart ? AppTheme.changeFg(isDark) : AppTheme.accent;
    final shadowColor = inCart
        ? AppTheme.changeFg(isDark).withOpacity(0.30)
        : const Color(0x33C96442);
    final circleSize = size + 4;
    final minusSize = size - 2;

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
        // maupun saat sudah ada di keranjang, agar tidak "melompat" ukuran.
        final mainCircle = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: AnimatedScale(
            scale: isActive ? _kActiveScale : 1.0,
            duration: _kActiveScaleDuration,
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: circleSize,
              height: circleSize,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: shadowColor,
                      blurRadius: 6,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Center(
                child: rightShowsPlus
                    ? Icon(Icons.add_rounded,
                        color: Colors.white, size: circleSize * 0.6)
                    : _qtyLabel(label, circleSize),
              ),
            ),
          ),
        );

        if (!inCart) return mainCircle;

        // Tombol minus: merah, sedikit lebih kecil dari lingkaran jumlah.
        // Pakai HitTestBehavior.opaque agar tap tidak "tembus" ke InkWell
        // kartu produk. Menampilkan angka qty saat `qtyOnLeft` (setelah "+"
        // ditekan), selain itu ikon "-".
        final minusButton = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleMinus,
          child: AnimatedScale(
            scale: isActive ? _kActiveScale : 1.0,
            duration: _kActiveScaleDuration,
            curve: Curves.easeOut,
            child: Container(
              width: minusSize,
              height: minusSize,
              decoration: const BoxDecoration(
                color: Color(0xFFD64545),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: qtyOnLeft
                    ? _qtyLabel(label, minusSize)
                    : Icon(Icons.remove_rounded,
                        color: Colors.white, size: minusSize * 0.6),
              ),
            ),
          ),
        );

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            minusButton,
            const SizedBox(width: 6),
            mainCircle,
          ],
        );
      },
    );
  }
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
      onPointerDown: (_) => AddControl.clearActive(),
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
