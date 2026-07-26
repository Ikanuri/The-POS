import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/device_provider.dart';
import '../../core/providers/laci_meja_provider.dart';

/// Item 52 ("Laci Meja") — dialog catat Pre-order/backorder, dipakai dari
/// DUA jalur entry (pencarian Kasir saat stok kosong, & halaman Produk).
/// Kalau [requiresDeposit] true (mis. LPG tukar-wadah), field jumlah wadah
/// dititip WAJIB diisi min 1 — validasi di sini (bukan CHECK constraint
/// DB), sesuai aturan bisnis di PLAN.md Item 52: syarat antri adalah
/// TITIP WADAH, bukan bayar duluan (dua-duanya dapat privilege FIFO yang
/// sama; yang bayar tapi TIDAK titip wadah sengaja diabaikan lewat
/// validasi wajib ini).
Future<void> showPreorderEntryDialog(
  BuildContext context,
  WidgetRef ref, {
  required String productId,
  required String productUnitId,
  required bool requiresDeposit,
  String? transactionId,
}) async {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final qtyController = TextEditingController(text: '1');
  final depositController = TextEditingController(text: requiresDeposit ? '1' : '0');
  var paid = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Catat Pre-order'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nama pelanggan'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'No. HP (opsional)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Jumlah dipesan'),
              ),
              if (requiresDeposit) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: depositController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Jumlah wadah dititip (wajib, min 1)'),
                ),
              ],
              const SizedBox(height: 8),
              CheckboxListTile(
                value: paid,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Sudah bayar (informatif, tidak menentukan '
                    'urutan antrian)'),
                onChanged: (v) => setDialogState(() => paid = v ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    ),
  );
  if (result != true) return;

  final qty = double.tryParse(qtyController.text.trim());
  final deposit = double.tryParse(depositController.text.trim()) ?? 0;
  if (nameController.text.trim().isEmpty || qty == null || qty <= 0) return;
  if (requiresDeposit && deposit < 1) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Produk ini butuh jaminan fisik — jumlah wadah '
              'dititip wajib diisi minimal 1')));
    }
    return;
  }

  final db = ref.read(databaseProvider);
  final locallyModified = ref.read(laciMejaLocallyModifiedProvider);
  await db.addPreorderEntry(
    id: const Uuid().v4(),
    productId: productId,
    productUnitId: productUnitId,
    transactionId: transactionId,
    customerName: nameController.text.trim(),
    phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
    qtyOrdered: qty,
    depositQty: deposit,
    paid: paid,
    locallyModified: locallyModified,
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Pre-order tercatat di Laci Meja')));
  }
}
