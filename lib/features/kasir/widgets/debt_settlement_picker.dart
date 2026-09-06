import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../cart_debt_settlement_provider.dart';
import 'debt_payment_sheet.dart';

/// Rencana alokasi FIFO nota lama dari SATU nominal — algoritma PERSIS
/// [AppDatabase.settleMergedDebt] (nota terlama dulu, `sisa <= 0` dilewati,
/// tiap nota dicap `min(remaining, sisa)`), tapi PURE (tanpa DB/tulis apa
/// pun) — dipakai membekukan rencana ke [DebtSettlementEntry.targetInvoices]
/// SAAT entri dibuat, supaya ringkasan yang kasir lihat konsisten sampai
/// checkout. [invoices] HARUS sudah terurut terlama dulu (lihat
/// `getUnpaidTxDetails`). Kelebihan di atas total sisa (mis. kasir mengetik
/// lebih dari sisa nota terpilih) TIDAK dialokasikan ke nota manapun di sini
/// — itu jadi kembalian tunai saat `settleMergedDebt` benar-benar dijalankan
/// di checkout (lihat dok `payment_screen.dart`), bukan overpay hutang.
List<DebtSettlementTarget> planFifoSettlement(
  List<UnpaidTxEntry> invoices,
  int amount,
) {
  var remaining = amount;
  final out = <DebtSettlementTarget>[];
  for (final inv in invoices) {
    if (remaining <= 0) break;
    if (inv.sisa <= 0) continue;
    final applied = remaining < inv.sisa ? remaining : inv.sisa;
    out.add(DebtSettlementTarget(
      invoiceId: inv.id,
      invoiceLocalId: inv.localId,
      amount: applied,
    ));
    remaining -= applied;
  }
  return out;
}

/// Alur "Lunasi Hutang" dari keranjang aktif: pilih pelanggan (dgn hutang
/// tertunggak) -> pilih nota tempo/kurang_bayar miliknya (checklist, boleh
/// sebagian) -> input nominal (kalkulator `showDebtPaymentSheet` yang sudah
/// ada, di-reuse). Mengembalikan SATU [DebtSettlementEntry] baru siap
/// ditambah ke `cartDebtSettlementProvider`, atau null bila dibatalkan di
/// langkah manapun.
Future<DebtSettlementEntry?> showDebtSettlementPicker(
  BuildContext context,
  WidgetRef ref,
  AppDatabase db,
) async {
  final customer = await showModalBottomSheet<DebtBookEntry>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _DebtCustomerPickerSheet(),
  );
  if (customer == null || !context.mounted) return null;

  final invoices = await db.getUnpaidTxDetails(customer.customerId);
  if (invoices.isEmpty || !context.mounted) return null;

  final selected = await showModalBottomSheet<List<UnpaidTxEntry>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DebtInvoicePickerSheet(
      customerName: customer.name,
      invoices: invoices,
    ),
  );
  if (selected == null || selected.isEmpty || !context.mounted) return null;

  final remaining = selected.fold<int>(0, (s, e) => s + e.sisa);
  final result = await showDebtPaymentSheet(
    context,
    db,
    remaining: remaining,
    title: 'Lunasi Hutang ${customer.name}',
  );
  if (result == null || result.amount <= 0) return null;

  // Rencana FIFO dihitung dari nota TERPILIH SAJA (terlama dulu, sesuai urutan
  // `getUnpaidTxDetails`) — nota lain milik pelanggan yang sama tapi TIDAK
  // dicentang kasir tidak ikut kena alokasi, walau amount lebih besar dari
  // sisa nota terpilih (kelebihan jadi kembalian, bukan lompat ke nota lain).
  final targets = planFifoSettlement(selected, result.amount);

  return DebtSettlementEntry(
    id: const Uuid().v4(),
    customerId: customer.customerId,
    customerName: customer.name,
    amount: result.amount,
    targetInvoices: targets,
    createdAt: DateTime.now(),
    method: result.method,
    methodName: result.methodName,
  );
}

class _DebtCustomerPickerSheet extends ConsumerStatefulWidget {
  const _DebtCustomerPickerSheet();

  @override
  ConsumerState<_DebtCustomerPickerSheet> createState() =>
      _DebtCustomerPickerSheetState();
}

class _DebtCustomerPickerSheetState
    extends ConsumerState<_DebtCustomerPickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final db = ref.watch(databaseProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text('Lunasi Hutang — Pilih Pelanggan',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _ctrl,
                  autofocus: false,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cari nama pelanggan...',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<DebtBookEntry>>(
                    future: db.getDebtBook(),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final all = snap.data!;
                      final list = _query.isEmpty
                          ? all
                          : all
                              .where((e) =>
                                  e.name.toLowerCase().contains(_query))
                              .toList();
                      if (list.isEmpty) {
                        return Center(
                          child: Text(
                            all.isEmpty
                                ? 'Tidak ada pelanggan dengan hutang tertunggak'
                                : 'Tidak ditemukan',
                            style:
                                TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        );
                      }
                      return ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = list[i];
                          return ListTile(
                            title: Text(e.name,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${e.count} nota belum lunas'),
                            trailing: Text(
                              formatRupiah(e.debt),
                              style: AppTheme.numStyle(context,
                                  size: 14,
                                  weight: FontWeight.w700,
                                  color: AppTheme.debtFg(
                                      Theme.of(context).brightness ==
                                          Brightness.dark)),
                            ),
                            onTap: () => Navigator.of(context).pop(e),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebtInvoicePickerSheet extends StatefulWidget {
  const _DebtInvoicePickerSheet(
      {required this.customerName, required this.invoices});
  final String customerName;
  final List<UnpaidTxEntry> invoices;

  @override
  State<_DebtInvoicePickerSheet> createState() =>
      _DebtInvoicePickerSheetState();
}

class _DebtInvoicePickerSheetState extends State<_DebtInvoicePickerSheet> {
  late final Set<String> _selected =
      widget.invoices.map((e) => e.id).toSet(); // default: semua dicentang

  int get _selectedTotal => widget.invoices
      .where((e) => _selected.contains(e.id))
      .fold<int>(0, (s, e) => s + e.sisa);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Pilih Nota — ${widget.customerName}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.invoices.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final inv = widget.invoices[i];
                  final checked = _selected.contains(inv.id);
                  return CheckboxListTile(
                    value: checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    title: Text(inv.localId,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_formatDate(inv.createdAt)),
                    secondary: Text(
                      formatRupiah(inv.sisa),
                      style: AppTheme.numStyle(context,
                          size: 13.5,
                          weight: FontWeight.w700,
                          color: AppTheme.debtFg(
                              Theme.of(context).brightness ==
                                  Brightness.dark)),
                    ),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(inv.id);
                      } else {
                        _selected.remove(inv.id);
                      }
                    }),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total terpilih',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                Text(formatRupiah(_selectedTotal),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                          widget.invoices
                              .where((e) => _selected.contains(e.id))
                              .toList(),
                        ),
                child: const Text('Lanjut'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
}
