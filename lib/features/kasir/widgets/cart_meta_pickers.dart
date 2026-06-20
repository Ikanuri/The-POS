import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/theme/app_theme.dart';

/// Hasil pilih pelanggan. null = batal (tidak berubah). Bila [id] dan [name]
/// keduanya null → pelanggan dihapus (jadi "Umum"). [id] null + [name] terisi
/// → nama manual (tanpa record pelanggan).
class CustomerPick {
  const CustomerPick(this.id, this.name);
  final String? id;
  final String? name;
}

/// Hasil pilih pegawai. null = batal. id+name null → tanpa pegawai.
class EmployeePick {
  const EmployeePick(this.id, this.name);
  final String? id;
  final String? name;
}

/// Sheet pilih pelanggan: cari di DB atau ketik nama manual. Ringan, dipakai
/// dari cart bar kasir (bukan layar bayar yang lebih lengkap).
Future<CustomerPick?> showCustomerPickerSheet(
  BuildContext context,
  WidgetRef ref, {
  String? currentName,
}) {
  return showModalBottomSheet<CustomerPick>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CustomerPickerSheet(currentName: currentName),
  );
}

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet({this.currentName});
  final String? currentName;

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  final _ctrl = TextEditingController();
  List<Customer> _results = [];
  final Map<String, (int, int)> _debts = {};

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.currentName ?? '';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    final db = ref.read(databaseProvider);
    final res = await db.searchCustomers(q);
    final debts = <String, (int, int)>{};
    for (final c in res) {
      debts[c.id] = await db.getCustomerOutstandingDebt(c.id);
    }
    if (!mounted) return;
    setState(() {
      _results = res;
      _debts
        ..clear()
        ..addAll(debts);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manual = _ctrl.text.trim();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Text('Pelanggan',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, const CustomerPick(null, null)),
                  icon: const Icon(Icons.person_off_outlined, size: 16),
                  label: const Text('Umum'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Cari pelanggan atau ketik nama…',
                prefixIcon: const Icon(Icons.person_outline, size: 18),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (v) {
                setState(() {});
                _search(v);
              },
            ),
            if (manual.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () =>
                    Navigator.pop(context, CustomerPick(null, manual)),
                icon: const Icon(Icons.check, size: 16),
                label: Text('Pakai nama "$manual"'),
              ),
            ],
            if (_results.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView(
                  shrinkWrap: true,
                  children: _results.take(8).map((c) {
                    final debt = _debts[c.id];
                    final hasDebt = debt != null && debt.$1 > 0;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          (c.name.isEmpty ? '?' : c.name[0]).toUpperCase(),
                          style: TextStyle(
                              color: scheme.onPrimaryContainer, fontSize: 12),
                        ),
                      ),
                      title: Text(c.name),
                      subtitle: hasDebt
                          ? Text(
                              'Hutang: ${formatRupiah(debt.$1)} (${debt.$2} nota)',
                              style: TextStyle(
                                  fontSize: 11, color: scheme.error))
                          : null,
                      onTap: () =>
                          Navigator.pop(context, CustomerPick(c.id, c.name)),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sheet pilih pegawai dari daftar (tanpa keyboard).
Future<EmployeePick?> showEmployeePickerSheet(
  BuildContext context,
  WidgetRef ref, {
  String? currentId,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final employees = await ref.read(databaseProvider).getEmployees();
  if (!context.mounted) return null;
  return showModalBottomSheet<EmployeePick>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('Pilih Pegawai',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ctx.push('/pengaturan/pegawai');
                  },
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Kelola'),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('Tanpa pegawai'),
                  onTap: () =>
                      Navigator.pop(ctx, const EmployeePick(null, null)),
                ),
                if (employees.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Belum ada pegawai. Tambah lewat "Kelola".',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ...employees.map((e) => ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: scheme.primaryContainer,
                        child: Text(
                          (e.name.isEmpty ? '?' : e.name[0]).toUpperCase(),
                          style: TextStyle(
                              color: scheme.onPrimaryContainer, fontSize: 12),
                        ),
                      ),
                      title: Text(e.name),
                      trailing: currentId == e.id
                          ? Icon(Icons.check, color: scheme.primary)
                          : null,
                      onTap: () =>
                          Navigator.pop(ctx, EmployeePick(e.id, e.name)),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
