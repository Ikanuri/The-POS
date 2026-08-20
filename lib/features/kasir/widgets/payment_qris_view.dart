import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/qris_dynamic.dart';

/// Potongan tampilan QRIS/metadata yang dipakai BERSAMA oleh layar checkout
/// (`payment_screen.dart`) dan sheet pelunasan hutang
/// (`debt_payment_sheet.dart`).
///
/// SENGAJA cuma berbagi bagian yang benar-benar sama (resolve payload, kotak
/// QR, label & aksi salin metadata) — TATA LETAKNYA dibiarkan lokal di
/// masing-masing layar, karena keduanya memang beda: di checkout QR & toggle
/// menyatu dalam satu Card, sedangkan di sheet hutang QR berpindah posisi
/// (menggantikan keypad saat dinamis, di atas nominal saat statis) dan
/// toggle-nya tinggal di baris tombol bawah menggantikan "Uang Pas".
/// Memaksakan satu widget layout untuk keduanya justru bikin parameter
/// kondisional yang lebih ruwet daripada manfaatnya.

/// Hasil resolve payload QR untuk sebuah metode QRIS.
class QrisPayload {
  const QrisPayload({required this.data, required this.nominalLocked});

  /// Payload yang dirender jadi QR.
  final String data;

  /// true bila nominal BERHASIL disisipkan (mode dinamis & payload valid).
  /// false = QR statis polos — entah karena mode statis dipilih, atau karena
  /// payload toko tidak bisa diparse (fallback diam-diam, lihat di bawah).
  final bool nominalLocked;
}

/// Resolve payload QR: sisipkan [amount] ke [staticPayload] bila
/// [dynamicMode] aktif & nominalnya masuk akal (> 0).
///
/// Gagal parse (`QrisTlvException` — payload toko bukan format EMVCo yang
/// dikenali) → fallback DIAM-DIAM ke payload statis apa adanya. Pembayaran
/// TIDAK BOLEH gagal cuma karena nominal tak bisa disisipkan; kasir masih
/// bisa memakai QR statis seperti sebelum fitur ini ada.
QrisPayload resolveQrisPayload({
  required String staticPayload,
  required int amount,
  required bool dynamicMode,
}) {
  if (dynamicMode && amount > 0) {
    try {
      return QrisPayload(
        data: injectQrisAmount(staticPayload, amount),
        nominalLocked: true,
      );
    } on QrisTlvException {
      // jatuh ke statis di bawah.
    }
  }
  return QrisPayload(data: staticPayload, nominalLocked: false);
}

/// Kotak QR putih siap-scan. Latar putih WAJIB eksplisit (bukan ikut tema) —
/// di mode gelap QR bertema gelap tidak terbaca scanner.
class QrisQrBox extends StatelessWidget {
  const QrisQrBox({super.key, required this.data, this.size = 200});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    // `key` ikut brightness: `QrImageView` (qr_flutter 4.1.0) melempar assert
    // framework 'debugSize == size' (text_painter.dart) kalau tema berganti
    // selagi QR terlihat — dicat memakai ukuran layout LAMA. Bug ada di
    // package, bukan di app ini (terbukti lewat probe QrImageView polos di
    // layar minimal). Mengganti key memaksa elemen baru, jadi layout & paint
    // selalu sepadan.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: QrImageView(
        key: ValueKey(isDark),
        data: data,
        size: size,
        backgroundColor: Colors.white,
      ),
    );
  }
}

/// Label field metadata sesuai jenis metode: bank → nomor rekening,
/// e-wallet → nomor HP/akun.
String paymentMetadataLabel(String type) =>
    type == 'bank' ? 'No. Rekening' : 'No. HP / Akun';

/// Ikon yang mewakili jenis metode non-tunai.
IconData paymentMethodIcon(String type) => switch (type) {
      'bank' => Icons.account_balance_outlined,
      'ewallet' => Icons.phone_android_outlined,
      'qris' => Icons.qr_code_outlined,
      _ => Icons.payments_outlined,
    };

/// Salin metadata (no. rekening / no. HP) ke clipboard + tampilkan konfirmasi.
void copyPaymentMetadata(BuildContext context, String data) {
  Clipboard.setData(ClipboardData(text: data));
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Nomor disalin')));
}

/// true bila metode ini punya metadata teks untuk ditampilkan (bank/e-wallet
/// yang nomornya sudah diisi di Pengaturan → Metode Pembayaran).
bool hasTextMetadata(PaymentMethod m) =>
    (m.type == 'bank' || m.type == 'ewallet') &&
    (m.data?.trim().isNotEmpty ?? false);
