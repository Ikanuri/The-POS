import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/theme/app_theme.dart';
import 'payment_qris_view.dart';

/// Struk "Pratinjau Keranjang" (permintaan user) — dibagikan SEBELUM
/// checkout, saat pelanggan minta lihat rincian & estimasi total. SENGAJA
/// widget TERPISAH dari `_ReceiptPaper` (receipt_screen.dart), bukan
/// dipakai-ulang dgn parameter kondisional: `_ReceiptPaper` dibangun dari
/// `Transaction` sungguhan (status lunas/tempo/void, riwayat pembayaran,
/// dll) yang di titik ini BELUM ADA sama sekali — memaksakan satu widget
/// utk keduanya berarti separuh field-nya harus dipalsukan/di-null-kan,
/// dan risiko nyata: sekali ada bug, nota lunas/tempo ASLI bisa ikut
/// ketiban logic "belum checkout" atau sebaliknya.
///
/// Dibuat SECARA VISUAL TIDAK MUNGKIN disalahartikan sbg struk resmi:
/// banner aksen "PRATINJAU KERANJANG" + watermark diagonal berulang +
/// TANPA nomor nota (karena memang belum ada transaksi tercatat) + label
/// "Estimasi Total" (bukan "Total") + disclaimer eksplisit "bukan bukti
/// transaksi/pembayaran".
class CartPreviewPaper extends StatelessWidget {
  const CartPreviewPaper({
    super.key,
    required this.items,
    required this.effectiveQtyOf,
    required this.totalAmount,
    required this.customerName,
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    this.storeWhatsapp = '',
    this.storeTelegram = '',
    this.receiptHeader = '',
    this.receiptFooter = '',
    this.qrData,
  });

  final List<CartItem> items;

  /// Qty efektif per baris (induk dikurangi total varian) — dioper dari
  /// `CartNotifier.effectiveQtyFor` oleh pemanggil, BUKAN dihitung ulang di
  /// sini, supaya angkanya SELALU sama dgn yang ditampilkan di keranjang
  /// itu sendiri (satu sumber kebenaran).
  final double Function(CartItem) effectiveQtyOf;
  final int totalAmount;
  final String customerName;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String storeWhatsapp;
  final String storeTelegram;
  final String receiptHeader;
  final String receiptFooter;

  /// Payload QR QRIS SUDAH JADI (hasil `resolveQrisPayload`, nominal
  /// estimasi saat ini disisipkan bila mode dinamis) dari pemanggil — pola
  /// identik `_ReceiptPaper.qrData`. null = tidak ditampilkan.
  final String? qrData;

  static const _ink = Color(0xFF111111);
  static const _accent = AppTheme.accent;

  static TextStyle get _mono =>
      GoogleFonts.robotoMono(fontSize: 12, color: _ink, height: 1.4);

  static String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  static String _fmtQty(double q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Container(
      width: 300,
      decoration: const BoxDecoration(color: Colors.white),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Watermark diagonal — tetap kebaca walau screenshot ini di-crop
          // sebagian oleh pelanggan, jadi pembeda dari struk asli tidak
          // hilang cuma krn banner di atas terpotong.
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.06,
                child: Transform.rotate(
                  angle: -0.45,
                  child: Wrap(
                    spacing: 22,
                    runSpacing: 18,
                    children: List.generate(
                      24,
                      (_) => Text('PRATINJAU',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _accent)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                  color: _accent,
                  child: Column(
                    children: [
                      Text('PRATINJAU KERANJANG',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.hankenGrotesk(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3)),
                      Text('Bukan struk resmi · belum ada transaksi',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.hankenGrotesk(
                              color: Colors.white.withOpacity(.92),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Text(storeName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style:
                        _mono.copyWith(fontSize: 16, fontWeight: FontWeight.w900)),
                if (storeAddress.isNotEmpty)
                  Text(storeAddress,
                      textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 11)),
                if (storePhone.isNotEmpty)
                  Text('Telp: $storePhone',
                      textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 11)),
                if (storeWhatsapp.isNotEmpty)
                  Text('WA: $storeWhatsapp',
                      textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 11)),
                if (storeTelegram.isNotEmpty)
                  Text('Telegram: $storeTelegram',
                      textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 11)),
                if (receiptHeader.isNotEmpty)
                  Text(receiptHeader,
                      textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 11)),
                const _DashedLine(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(date, style: _mono),
                    Text('Estimasi', style: _mono),
                  ],
                ),
                Text(customerName,
                    style: _mono.copyWith(fontSize: 16, fontWeight: FontWeight.w900)),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Belum checkout',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 9.5, fontWeight: FontWeight.w700, color: _accent)),
                ),
                const _DashedLine(),
                for (final item in items) ...[
                  Text(
                      '${item.isVariant ? '  └ ' : ''}${item.productName}',
                      style: _mono.copyWith(
                          fontWeight: item.isVariant ? FontWeight.w400 : FontWeight.w700)),
                  if (effectiveQtyOf(item) > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                              '${item.isVariant ? '  ' : ''}${_fmtQty(effectiveQtyOf(item))} ${item.unitName} x ${_fmtNum(item.price)}',
                              style: _mono.copyWith(fontSize: 11)),
                        ),
                        Text(
                            'Rp ${_fmtNum((item.price * effectiveQtyOf(item)).round())}',
                            style: _mono.copyWith(fontSize: 11)),
                      ],
                    ),
                ],
                const _DashedLine(),
                Text('Estimasi Total',
                    style: _mono.copyWith(fontSize: 13, fontWeight: FontWeight.w900)),
                Text('Rp ${_fmtNum(totalAmount)}',
                    textAlign: TextAlign.center,
                    style: _mono.copyWith(fontSize: 20, fontWeight: FontWeight.w900)),
                Text(
                    'Harga & total masih bisa berubah (mis. diskon, stok, '
                    'atau item ditambah/dikurangi) sampai transaksi '
                    'benar-benar diselesaikan di kasir.',
                    textAlign: TextAlign.center,
                    style: _mono.copyWith(fontSize: 10, color: const Color(0xFF6B6156))),
                if (qrData != null && qrData!.isNotEmpty) ...[
                  const _DashedLine(),
                  Center(
                    child: Image.asset('assets/qris/qris_logo.png',
                        height: 22, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 6),
                  Center(child: QrisQrBox(data: qrData!, size: 160)),
                  const SizedBox(height: 4),
                  Text('Rp ${_fmtNum(totalAmount)}',
                      textAlign: TextAlign.center,
                      style: _mono.copyWith(fontSize: 13, fontWeight: FontWeight.w800)),
                  Text(
                      'Nominal mengikuti estimasi saat ini.\n'
                      'Konfirmasi ke kasir setelah membayar.',
                      textAlign: TextAlign.center,
                      style: _mono.copyWith(fontSize: 10, color: const Color(0xFF6B6156))),
                ],
                const _DashedLine(),
                Text('Dibagikan atas permintaan pelanggan —\n'
                    'bukan bukti transaksi/pembayaran.',
                    textAlign: TextAlign.center,
                    style: _mono.copyWith(fontSize: 10, color: const Color(0xFF6B6156))),
                Text(receiptFooter.isNotEmpty ? receiptFooter : 'Terima kasih!',
                    textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final count = (constraints.maxWidth / 7).floor();
          return Text(
            List.filled(count, '-').join(),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: GoogleFonts.robotoMono(fontSize: 12, color: const Color(0xFF777777)),
          );
        },
      ),
    );
  }
}
