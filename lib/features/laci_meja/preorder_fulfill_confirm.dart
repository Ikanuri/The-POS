import 'package:flutter/material.dart';

import '../../core/database/app_database.dart';
import '../../core/theme/app_theme.dart';

/// Konfirmasi anti-misclick utk "Penuhi" pre-order yang SISANYA <= 1 (tidak
/// ada dialog jumlah, dulu langsung dipenuhi). Kalau DP/jaminan masih
/// terhutang (harga baris nota Rp 0), dialog menambah peringatan. Hanya DUA
/// tombol (gotcha CLAUDE.md soal tombol di `AlertDialog`).
Future<bool> confirmFulfillPreorder(
  BuildContext context,
  AppDatabase db, {
  required String entryId,
  required String productName,
  required String customerName,
}) async {
  final owed = await db.getPreorderDepositOwed(entryId);
  if (!context.mounted) return false;
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Penuhi pre-order?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$productName untuk $customerName akan ditandai dipenuhi '
              'dan stok berkurang.'),
          if (owed != null) ...[
            const SizedBox(height: 8),
            Text(
              'DP/jaminan ${formatRupiah(owed)} belum dibayar.',
              key: const ValueKey('fulfill-confirm-dp-warning'),
              style:
                  TextStyle(fontWeight: FontWeight.w700, color: scheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Penuhi'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
