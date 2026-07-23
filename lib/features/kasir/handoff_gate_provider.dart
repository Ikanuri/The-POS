import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';

/// Item 24d — true bila device INI perlu digerbang dari akses bayar
/// langsung: role Pegawai (`deviceRole == 'kasir'`) TANPA izin
/// `terima_pembayaran`. Owner/Asisten TIDAK PERNAH digerbang. Dipakai
/// bersama di `cart_sheet.dart` (tombol Bayar → QR handoff) dan
/// `kasir_screen.dart` (Item 56 — tombol Bayar di cart bar & tombol
/// Transfer QR, keduanya butuh cek yang SAMA persis).
final needsPaymentGateProvider = FutureProvider.autoDispose<bool>((ref) async {
  final device = ref.watch(deviceProvider);
  if (device.deviceRole != 'kasir') return false;
  final db = ref.watch(databaseProvider);
  return !(await db.isPermissionEnabled('terima_pembayaran'));
});
