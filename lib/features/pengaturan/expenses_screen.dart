import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_formatters.dart';

const _thousandsFmt = ThousandsSeparatorFormatter();

// Locale 'id' tidak di-initializeDateFormatting di app ini — format nama
// hari/bulan MANUAL agar tidak throw LocaleDataException.
const _idDays = [
  'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
];
const _idMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
];
String _fmtTanggal(DateTime d) =>
    '${_idDays[d.weekday - 1]}, ${d.day} ${_idMonths[d.month - 1]} ${d.year}';
String _fmtTanggalShort(DateTime d) =>
    '${d.day} ${_idMonths[d.month - 1]} ${d.year}';

/// Label kategori pengeluaran (enum `Expenses.type`).
const _expenseTypeLabels = {
  'daily_expense': 'Operasional',
  'owner_withdrawal': 'Ambil Pribadi (Owner)',
  'supplier_payment': 'Bayar Supplier',
  'change_given': 'Uang Keluar Laci',
};

IconData _expenseTypeIcon(String t) => switch (t) {
      'daily_expense' => Icons.receipt_long_outlined,
      'owner_withdrawal' => Icons.account_balance_wallet_outlined,
      'supplier_payment' => Icons.local_shipping_outlined,
      'change_given' => Icons.money_off_outlined,
      _ => Icons.payments_outlined,
    };

/// Rentang bulan berjalan (awal bulan s/d akhir hari ini).
DateTimeRange _thisMonth() {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, 1),
    end: DateTime(now.year, now.month, now.day, 23, 59, 59),
  );
}

// Item 42 — filter periode di tab Pengeluaran. Preset terpilih ('hari'/
// 'minggu'/'bulan'/'custom') + rentang custom bila preset = 'custom'.
final _expensePeriodProvider = StateProvider<String>((ref) => 'bulan');
final _expenseCustomRangeProvider =
    StateProvider<DateTimeRange?>((ref) => null);

/// Rentang efektif dari preset terpilih. Untuk 'hari'/'minggu'/'bulan'
/// dihitung dari `DateTime.now()` saat provider dibangun (segar tiap layar
/// dibuka; sama seperti perilaku lama yang selalu bulan berjalan).
final _expenseRangeProvider = Provider.autoDispose<DateTimeRange>((ref) {
  final kind = ref.watch(_expensePeriodProvider);
  final now = DateTime.now();
  switch (kind) {
    case 'hari':
      return DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    case 'minggu':
      final ws = now.subtract(Duration(days: now.weekday - 1));
      return DateTimeRange(
        start: DateTime(ws.year, ws.month, ws.day),
        end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      );
    case 'custom':
      return ref.watch(_expenseCustomRangeProvider) ?? _thisMonth();
    case 'bulan':
    default:
      return _thisMonth();
  }
});

final _expensesProvider = StreamProvider.autoDispose<List<Expense>>((ref) {
  final db = ref.watch(databaseProvider);
  final range = ref.watch(_expenseRangeProvider);
  return db.watchExpenses(range.start, range.end);
});

String _periodLabel(String kind) => switch (kind) {
      'hari' => 'hari ini',
      'minggu' => 'minggu ini',
      'custom' => 'periode ini',
      _ => 'bulan ini',
    };

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncExpenses = ref.watch(_expensesProvider);
    final kind = ref.watch(_expensePeriodProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Pengeluaran'),
      ),
      body: Column(
        children: [
          _periodSelector(context, ref),
          Expanded(
            child: asyncExpenses.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (expenses) {
                if (expenses.isEmpty) {
                  return Center(
                    child: Text(
                        'Belum ada pengeluaran ${_periodLabel(kind)}.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  );
                }
                final total = expenses.fold<int>(0, (s, e) => s + e.amount);
                // Kelompokkan per tanggal (yyyy-MM-dd).
                final groups = <String, List<Expense>>{};
                for (final e in expenses) {
                  final key = DateFormat('yyyy-MM-dd').format(e.createdAt);
                  groups.putIfAbsent(key, () => []).add(e);
                }
                final device = ref.watch(deviceProvider);

                return ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text('Total ${_periodLabel(kind)}',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant)),
                          ),
                          const SizedBox(width: 8),
                          Text(formatRupiah(total),
                              style: AppTheme.numStyle(context,
                                  size: 18, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text(
                          _fmtTanggal(DateTime.parse(entry.key)),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant),
                        ),
                      ),
                      ...entry.value.map((e) => _ExpenseTile(
                            expense: e,
                            // Owner/asisten boleh hapus apa saja; kasir
                            // hanya pengeluaran miliknya sendiri.
                            canDelete: device.canSeeReports ||
                                e.kasirId == device.deviceCode,
                          )),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Item 42 — pemilih periode (Hari Ini / Minggu Ini / Bulan Ini / Custom).
  Widget _periodSelector(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(_expensePeriodProvider);
    final range = ref.watch(_expenseRangeProvider);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Row(
            children: [
              for (final (k, label) in const [
                ('hari', 'Hari Ini'),
                ('minggu', 'Minggu Ini'),
                ('bulan', 'Bulan Ini'),
                ('custom', 'Custom'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: kind == k,
                    onSelected: (_) => _selectPeriod(context, ref, k),
                  ),
                ),
            ],
          ),
        ),
        if (kind == 'custom')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Text(
              '${_fmtTanggalShort(range.start)} – '
              '${_fmtTanggalShort(range.end)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  Future<void> _selectPeriod(
      BuildContext context, WidgetRef ref, String kind) async {
    if (kind == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange:
            ref.read(_expenseCustomRangeProvider) ?? _thisMonth(),
      );
      if (picked == null) return;
      ref.read(_expenseCustomRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
      );
      ref.read(_expensePeriodProvider.notifier).state = 'custom';
    } else {
      ref.read(_expensePeriodProvider.notifier).state = kind;
    }
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddExpenseSheet(),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense, required this.canDelete});
  final Expense expense;
  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tile = ListTile(
      leading: Icon(_expenseTypeIcon(expense.type),
          color: scheme.onSurfaceVariant),
      title: Text(_expenseTypeLabels[expense.type] ?? expense.type),
      subtitle: expense.note != null && expense.note!.isNotEmpty
          ? Text(expense.note!)
          : null,
      trailing: Text(formatRupiah(expense.amount),
          style: AppTheme.numStyle(context,
              size: 15, weight: FontWeight.w700, color: scheme.error)),
    );
    if (!canDelete) return tile;
    return Dismissible(
      key: ValueKey('exp-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Hapus pengeluaran?'),
                content: Text(
                    '${_expenseTypeLabels[expense.type] ?? expense.type} · '
                    '${formatRupiah(expense.amount)}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Hapus')),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        await ref.read(databaseProvider).deleteExpense(expense.id);
      },
      child: tile,
    );
  }
}

class _AddExpenseSheet extends ConsumerStatefulWidget {
  const _AddExpenseSheet();

  @override
  ConsumerState<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<_AddExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _type = 'daily_expense';
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = ThousandsSeparatorFormatter.parseValue(_amountCtrl.text);
    if (amount <= 0) return;
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final navigator = Navigator.of(context);
    // Pertahankan jam saat ini bila tanggal = hari ini; kalau tanggal lain,
    // pakai tengah hari agar tetap masuk rentang harian yang benar.
    final now = DateTime.now();
    final createdAt = DateUtils.isSameDay(_date, now)
        ? now
        : DateTime(_date.year, _date.month, _date.day, 12);
    await db.addExpense(
      type: _type,
      amount: amount,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      kasirId: device.deviceCode,
      createdAt: createdAt,
    );
    if (!mounted) return;
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tambah Pengeluaran',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: const [_thousandsFmt],
            decoration: const InputDecoration(
                labelText: 'Nominal', prefixText: 'Rp ', isDense: true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _type,
            decoration:
                const InputDecoration(labelText: 'Kategori', isDense: true),
            items: [
              for (final e in _expenseTypeLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'daily_expense'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Catatan (opsional)', isDense: true),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(_fmtTanggalShort(_date))),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: const Text('Ubah tanggal'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _save,
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }
}
