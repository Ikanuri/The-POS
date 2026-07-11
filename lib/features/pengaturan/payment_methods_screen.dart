import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';

const _pmUuid = Uuid();

final _paymentMethodsProvider = StreamProvider<List<PaymentMethod>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.paymentMethods)
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methodsAsync = ref.watch(_paymentMethodsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Metode Pembayaran'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddSheet(context, ref),
          ),
        ],
      ),
      body: methodsAsync.when(
        data: (methods) => ListView.separated(
          itemCount: methods.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _MethodTile(method: methods[i]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddMethodSheet(),
    );
  }
}

class _MethodTile extends ConsumerWidget {
  const _MethodTile({required this.method});
  final PaymentMethod method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTunai = method.type == 'tunai';
    final scheme = Theme.of(context).colorScheme;

    Future<void> toggle(bool v) async {
      final db = ref.read(databaseProvider);
      await (db.update(db.paymentMethods)
            ..where((t) => t.id.equals(method.id)))
          .write(PaymentMethodsCompanion(isActive: Value(v)));
    }

    final tile = ListTile(
      leading: Icon(_typeIcon(method.type)),
      title: Text(method.name),
      subtitle: Text(_typeLabel(method.type),
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      // Tap judul → edit (kecuali Tunai, konsisten dgn tak bisa dinonaktifkan).
      onTap: isTunai ? null : () => _showEditSheet(context, method),
      trailing: Switch(
        value: method.isActive,
        onChanged: isTunai ? null : toggle,
      ),
    );

    // Tunai tidak bisa dihapus. Metode lain: hapus via swipe, TAPI hanya bila
    // sudah dinonaktifkan dulu (isActive=false) — menghapus baris ini tidak
    // merusak riwayat transaksi (paymentMethod di transaksi = string mandiri,
    // bukan foreign key), jadi aman.
    if (isTunai) return tile;

    return Dismissible(
      key: ValueKey('pm-${method.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline, color: scheme.error),
      ),
      confirmDismiss: (_) async {
        if (method.isActive) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Nonaktifkan metode ini dulu sebelum menghapus.')));
          return false;
        }
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Hapus ${method.name}?'),
            content: const Text(
                'Metode ini akan dihapus permanen. Pastikan benar-benar tidak '
                'dipakai lagi. Riwayat transaksi lama tidak terpengaruh.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Hapus')),
            ],
          ),
        );
        return ok ?? false;
      },
      onDismissed: (_) async {
        final db = ref.read(databaseProvider);
        await (db.delete(db.paymentMethods)
              ..where((t) => t.id.equals(method.id)))
            .go();
      },
      child: tile,
    );
  }

  void _showEditSheet(BuildContext context, PaymentMethod method) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddMethodSheet(existing: method),
    );
  }

  IconData _typeIcon(String t) => switch (t) {
        'qris' => Icons.qr_code_outlined,
        'bank' => Icons.account_balance_outlined,
        'ewallet' => Icons.phone_android_outlined,
        'tempo' => Icons.schedule_outlined,
        _ => Icons.payments_outlined,
      };

  String _typeLabel(String t) => switch (t) {
        'tunai' => 'Uang tunai (tidak bisa dinonaktifkan)',
        'qris' => 'QRIS statis',
        'bank' => 'Transfer bank',
        'ewallet' => 'Dompet digital',
        'tempo' => 'Pembayaran tempo / piutang',
        _ => t,
      };
}

class _AddMethodSheet extends ConsumerStatefulWidget {
  const _AddMethodSheet({this.existing});

  /// null = tambah baru; non-null = edit metode ini (prefill + update).
  final PaymentMethod? existing;

  @override
  ConsumerState<_AddMethodSheet> createState() => _AddMethodSheetState();
}

class _AddMethodSheetState extends ConsumerState<_AddMethodSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _dataCtrl;
  late final TextEditingController _qrCtrl;
  late String _type;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _dataCtrl = TextEditingController(text: e?.data ?? '');
    _qrCtrl = TextEditingController(text: e?.qrValue ?? '');
    _type = e?.type ?? 'bank';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dataCtrl.dispose();
    _qrCtrl.dispose();
    super.dispose();
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
          Text(
              widget.existing == null
                  ? 'Tambah Metode Pembayaran'
                  : 'Edit Metode Pembayaran',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _type,
            decoration: const InputDecoration(labelText: 'Tipe', isDense: true),
            items: const [
              DropdownMenuItem(value: 'qris', child: Text('QRIS')),
              DropdownMenuItem(value: 'bank', child: Text('Transfer Bank')),
              DropdownMenuItem(value: 'ewallet', child: Text('E-Wallet')),
              DropdownMenuItem(value: 'tempo', child: Text('Tempo / Piutang')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'bank'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'Nama',
              hintText: _type == 'bank'
                  ? 'BRI, BCA, Mandiri…'
                  : _type == 'qris'
                      ? 'QRIS BRI'
                      : _type == 'ewallet'
                          ? 'GoPay, OVO, Dana…'
                          : 'Nama metode',
              isDense: true,
            ),
          ),
          if (_type == 'bank' || _type == 'ewallet') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _dataCtrl,
              decoration: InputDecoration(
                labelText: _type == 'bank' ? 'No. Rekening' : 'No. HP / Akun',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),
          ],
          if (_type == 'qris') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _qrCtrl,
              decoration: const InputDecoration(
                labelText: 'QR Value (opsional)',
                hintText: 'Tempel konten QRIS untuk generate QR',
                isDense: true,
              ),
              maxLines: 3,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              if (_nameCtrl.text.trim().isEmpty) return;
              final db = ref.read(databaseProvider);
              final navigator = Navigator.of(context);
              final data =
                  _dataCtrl.text.trim().isEmpty ? null : _dataCtrl.text.trim();
              final qr =
                  _qrCtrl.text.trim().isEmpty ? null : _qrCtrl.text.trim();
              final e = widget.existing;
              if (e == null) {
                await db.into(db.paymentMethods).insert(
                      PaymentMethodsCompanion.insert(
                        id: _pmUuid.v4(),
                        type: _type,
                        name: _nameCtrl.text.trim(),
                        data: Value(data),
                        qrValue: Value(qr),
                      ),
                    );
              } else {
                await (db.update(db.paymentMethods)
                      ..where((t) => t.id.equals(e.id)))
                    .write(PaymentMethodsCompanion(
                  type: Value(_type),
                  name: Value(_nameCtrl.text.trim()),
                  data: Value(data),
                  qrValue: Value(qr),
                ));
              }
              if (!mounted) return;
              navigator.pop();
            },
            child: Text(widget.existing == null ? 'Tambah' : 'Simpan'),
          ),
        ],
      ),
    );
  }
}
