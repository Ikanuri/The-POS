import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';

/// Pilihan QRIS untuk struk (bagikan & cetak) dan pratinjau keranjang —
/// SATU pilihan untuk semuanya (keputusan user), disimpan per-device. Bila
/// toko punya lebih dari satu QRIS aktif, kasir memilih lewat [QrisChoiceRow]
/// di sheet bagikan; bila tidak pernah memilih (atau pilihannya sudah
/// nonaktif/kosong), jatuh ke QRIS aktif PERTAMA menurut urutan.
const kShareQrisMethodKey = 'share_qris_method_id';

/// Semua metode QRIS aktif dgn payload terisi, urut `sortOrder`.
Future<List<PaymentMethod>> activeQrisMethods(AppDatabase db) async {
  final methods = await (db.select(db.paymentMethods)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .get();
  return [
    for (final m in methods)
      if (m.type == 'qris' && (m.qrValue?.trim().isNotEmpty ?? false)) m
  ];
}

/// QRIS terpilih dari [methods]: yang tersimpan bila masih ada di daftar,
/// selain itu yang pertama; null bila daftar kosong.
PaymentMethod? pickQrisMethod(List<PaymentMethod> methods, String? savedId) {
  if (methods.isEmpty) return null;
  for (final m in methods) {
    if (m.id == savedId) return m;
  }
  return methods.first;
}

/// QRIS yang dipakai struk/pratinjau saat ini (pilihan tersimpan atau default).
Future<PaymentMethod?> resolveSharedQrisMethod(AppDatabase db) async {
  final prefs = await SharedPreferences.getInstance();
  return pickQrisMethod(
      await activeQrisMethods(db), prefs.getString(kShareQrisMethodKey));
}

/// Satu baris chip pilihan QRIS (geser ke samping kalau banyak). Dipasang
/// HANYA saat ada >= 2 QRIS aktif — lihat pemanggilnya.
class QrisChoiceRow extends StatelessWidget {
  const QrisChoiceRow({
    super.key,
    required this.methods,
    required this.selectedId,
    required this.onSelected,
  });

  final List<PaymentMethod> methods;
  final String? selectedId;
  final ValueChanged<PaymentMethod> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text('QRIS:',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          for (final m in methods)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                key: ValueKey('qris-choice-${m.id}'),
                visualDensity: VisualDensity.compact,
                label: Text(m.name, style: const TextStyle(fontSize: 12)),
                selected: m.id == selectedId,
                onSelected: (_) => onSelected(m),
              ),
            ),
        ],
      ),
    );
  }
}
