import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';

/// Dialog pelunasan / tambah bayar hutang dengan pemilihan metode bayar.
///
/// Mengembalikan `(amount, method)` atau null bila dibatalkan. [method] =
/// `PaymentMethod.type` metode terpilih (konsisten dengan cara transaksi awal
/// menyimpan `paymentMethod` — lihat payment_screen `_selectedMethodType`).
/// Default = 'tunai' (metode Tunai selalu ada & tak bisa dinonaktifkan).
///
/// Menggantikan 3 dialog "Tambah Bayar/Lunasi" yang dulu identik & hardcode
/// `method: 'tunai'` (tx_history_sheet, transaksi_tab, receipt_screen).
Future<({int amount, String method})?> showDebtPaymentDialog(
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
  if (!context.mounted) return null;
  return showDialog<({int amount, String method})>(
    context: context,
    builder: (ctx) => _DebtPaymentDialog(
      remaining: remaining,
      title: title,
      methods: methods,
      prefillRemaining: prefillRemaining,
    ),
  );
}

class _DebtPaymentDialog extends StatefulWidget {
  const _DebtPaymentDialog({
    required this.remaining,
    required this.title,
    required this.methods,
    required this.prefillRemaining,
  });

  final int remaining;
  final String title;
  final List<PaymentMethod> methods;
  final bool prefillRemaining;

  @override
  State<_DebtPaymentDialog> createState() => _DebtPaymentDialogState();
}

class _DebtPaymentDialogState extends State<_DebtPaymentDialog> {
  late final TextEditingController _ctrl;
  String? _selectedId; // null bila daftar metode kosong → fallback 'tunai'

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.prefillRemaining
            ? ThousandsSeparatorFormatter.format(widget.remaining)
            : '');
    // Item 11 — tombol Bayar nyala/mati ikut isi field (persis kalkulator
    // di modal checkout), butuh rebuild tiap ketikan.
    _ctrl.addListener(_onAmountChanged);
    if (widget.methods.isNotEmpty) {
      final tunai = widget.methods.where((m) => m.type == 'tunai').firstOrNull;
      _selectedId = (tunai ?? widget.methods.first).id;
    }
  }

  void _onAmountChanged() => setState(() {});

  @override
  void dispose() {
    _ctrl.removeListener(_onAmountChanged);
    _ctrl.dispose();
    super.dispose();
  }

  String get _selectedType {
    if (_selectedId == null) return 'tunai';
    return widget.methods.firstWhere((m) => m.id == _selectedId).type;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      // AlertDialog SELALU membungkus content dengan IntrinsicWidth (lihat
      // framework `dialog.dart`), yang kurang cocok dgn Expanded di bawah —
      // SizedBox(width: maxFinite) memberi lebar pasti ke subtree ini
      // supaya Expanded bisa dipakai dgn aman (dialog tetap dibatasi lebar
      // maksimum oleh constraint Dialog sendiri, TIDAK jadi selebar layar).
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sisa tagihan: ${formatRupiah(widget.remaining)}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsSeparatorFormatter()],
              decoration: const InputDecoration(
                  prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
            if (widget.methods.length > 1) ...[
              const SizedBox(height: 14),
              Text('Metode bayar',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in widget.methods)
                    ChoiceChip(
                      label: Text(m.name),
                      selected: _selectedId == m.id,
                      selectedColor: scheme.primaryContainer,
                      onSelected: (_) => setState(() => _selectedId = m.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // 3 tombol lebar-penuh ("Uang Pas" + "Bayar") TIDAK MUAT sejajar
            // dalam SATU baris di dialog sesempit ini (sudah dibuktikan
            // overflow nyata di widget test dgn surface sesempit HP asli) —
            // "Batal" dipisah baris sendiri di kanan atas (tidak berebut
            // lebar dgn 2 tombol lain), baru "Uang Pas"+"Bayar" sebaris di
            // bawahnya persis pola payment_screen.dart (yang muat karena
            // cuma 2 tombol).
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal')),
            ),
            Row(
              children: [
                OutlinedButton(
                  // AppTheme set minimumSize OutlinedButton lebar penuh by
                  // default (utk tombol CTA berdiri sendiri) — di sini WAJIB
                  // override sempit, sama seperti payment_screen.dart.
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16)),
                  onPressed: () => setState(() => _ctrl.text =
                      ThousandsSeparatorFormatter.format(widget.remaining)),
                  child: const Text('Uang Pas'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: FilledButton(
                      onPressed:
                          ThousandsSeparatorFormatter.parseValue(_ctrl.text) <=
                                  0
                              ? null
                              : () {
                                  final amount =
                                      ThousandsSeparatorFormatter.parseValue(
                                          _ctrl.text);
                                  Navigator.of(context).pop(
                                      (amount: amount, method: _selectedType));
                                },
                      child: const Text('Bayar'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
