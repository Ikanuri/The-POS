import 'package:flutter/foundation.dart';

/// Sinyal "produk baru saja di-scan scanner HID" dari layar Kasir ke sheet
/// keranjang yang SEDANG terbuka (sheet terbuka = `_openCartSheet` tidak
/// membukanya lagi, jadi sheet perlu diberi tahu). Berisi `productUnitId`
/// item yang baru masuk/bertambah qty-nya; `seq` naik tiap scan supaya scan
/// beruntun produk yang SAMA tetap terdeteksi sebagai perubahan.
class CartSheetScanSignal {
  CartSheetScanSignal._();

  static final ValueNotifier<({int seq, String unitId})?> notifier =
      ValueNotifier(null);

  static int _seq = 0;

  static void notify(String unitId) {
    notifier.value = (seq: ++_seq, unitId: unitId);
  }
}
