import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';

const _custUuid = Uuid();

class PelangganFormScreen extends ConsumerStatefulWidget {
  const PelangganFormScreen({super.key, this.customerId});
  final String? customerId;

  @override
  ConsumerState<PelangganFormScreen> createState() =>
      _PelangganFormScreenState();
}

class _PelangganFormScreenState
    extends ConsumerState<PelangganFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isEdit = false;
  String? _customerId;
  Customer? _existing;
  List<CustomerGroup> _groups = [];
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _customerId = widget.customerId == 'baru' ? null : widget.customerId;
    _isEdit = _customerId != null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final groups = await (db.select(db.customerGroups)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();

    if (_isEdit) {
      final c = await (db.select(db.customers)
            ..where((t) => t.id.equals(_customerId!)))
          .getSingleOrNull();
      if (c != null && mounted) {
        _nameCtrl.text = c.name;
        _phoneCtrl.text = c.phone ?? '';
        _addressCtrl.text = c.address ?? '';
        setState(() {
          _existing = c;
          _groups = groups;
          _selectedGroupId = c.customerGroupId;
        });
        return;
      }
    }
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final now = DateTime.now();
      final custId = _customerId ?? _custUuid.v4();
      final companion = CustomersCompanion(
        id: Value(custId),
        name: Value(_nameCtrl.text.trim()),
        phone: Value(
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
        address: Value(_addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim()),
        customerGroupId: Value(_selectedGroupId),
        isActive: const Value(true),
        loyaltyPoints: _isEdit ? const Value.absent() : const Value(0),
        outstandingDebt: _isEdit ? const Value.absent() : const Value(0),
        createdAt: _isEdit ? const Value.absent() : Value(now),
        updatedAt: Value(now),
      );
      await db.into(db.customers).insertOnConflictUpdate(companion);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  _isEdit ? 'Data pelanggan diperbarui' : 'Pelanggan ditambahkan')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete() async {
    final c = _existing;
    if (c == null) return;
    final hasDebt = c.outstandingDebt > 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Pelanggan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hapus "${c.name}" dari daftar pelanggan?'),
            const SizedBox(height: 8),
            Text(
              'Riwayat transaksi lama tetap tersimpan. Pelanggan hanya '
              'disembunyikan dari daftar aktif.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            if (hasDebt) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18,
                        color: Theme.of(ctx).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Masih punya hutang ${formatRupiah(c.outstandingDebt)}. '
                        'Pastikan sudah dilunasi / dicatat.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final db = ref.read(databaseProvider);
    await db.deactivateCustomer(c.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Pelanggan "${c.name}" dihapus')));
      context.pop();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Pelanggan' : 'Tambah Pelanggan'),
        actions: [
          if (_isEdit && _existing != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: scheme.error),
              tooltip: 'Hapus Pelanggan',
              onPressed: _isLoading ? null : _delete,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_isEdit && _existing != null) ...[
                    Card(
                      color: scheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.star, color: scheme.onPrimaryContainer),
                            const SizedBox(width: 8),
                            Text(
                              '${_existing!.loyaltyPoints} poin loyalitas',
                              style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            if (_existing!.outstandingDebt > 0)
                              Text(
                                'Utang: ${formatRupiah(_existing!.outstandingDebt)}',
                                style: TextStyle(
                                    color: scheme.error, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nama Pelanggan *',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Nama wajib diisi'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nomor Telepon',
                      hintText: '08xx…',
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Alamat',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  if (_groups.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      value: _selectedGroupId,
                      decoration:
                          const InputDecoration(labelText: 'Grup Harga'),
                      items: [
                        const DropdownMenuItem(
                            value: null,
                            child: Text('Tanpa Grup (Harga Normal)')),
                        ..._groups.map((g) => DropdownMenuItem(
                              value: g.id,
                              child: Text(g.name),
                            )),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedGroupId = v),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: FilledButton(
          onPressed: _isLoading ? null : _save,
          child: Text(_isEdit ? 'Perbarui Data' : 'Simpan Pelanggan'),
        ),
      ),
    );
  }
}
