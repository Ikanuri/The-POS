import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';

const _empUuid = Uuid();

final _employeesProvider = StreamProvider<List<Employee>>((ref) {
  return ref.watch(databaseProvider).watchEmployees();
});

class EmployeeScreen extends ConsumerWidget {
  const EmployeeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(_employeesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pegawai Toko')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Tambah'),
      ),
      body: employees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge_outlined,
                        size: 48, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    Text(
                      'Belum ada pegawai.\nTambah pegawai agar bisa dicatat '
                      'di tiap nota — berguna menelusuri siapa yang melayani '
                      'bila ada salah ambil / input.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final e = list[i];
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      (e.name.isEmpty ? '?' : e.name[0]).toUpperCase(),
                      style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(e.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () => _showForm(context, ref, employee: e),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: scheme.error),
                        tooltip: 'Hapus',
                        onPressed: () => _confirmDelete(context, ref, e),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showForm(BuildContext context, WidgetRef ref,
      {Employee? employee}) async {
    final ctrl = TextEditingController(text: employee?.name ?? '');
    final isEdit = employee != null;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Pegawai' : 'Tambah Pegawai'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama Pegawai',
            hintText: 'mis. Budi',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
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
    );
    if (saved != true) {
      ctrl.dispose();
      return;
    }
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (name.isEmpty) return;

    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    await db.upsertEmployee(EmployeesCompanion(
      id: Value(employee?.id ?? _empUuid.v4()),
      name: Value(name),
      isActive: const Value(true),
      createdAt: isEdit ? const Value.absent() : Value(now),
      updatedAt: Value(now),
    ));
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Employee e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Pegawai'),
        content: Text(
            'Hapus "${e.name}" dari daftar pegawai? Nota lama yang sudah '
            'mencatat nama ini tetap utuh.'),
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
    if (confirmed == true) {
      await ref.read(databaseProvider).deleteEmployee(e.id);
    }
  }
}
