import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart' show databaseProvider;

/// Layar diagnostik: cari baris duplikat di `product_barcodes`/`price_tiers`/
/// `alt_prices` (lihat `AppDatabase.findMasterDataDuplicates`) — dulu bisa
/// muncul kalau device ini pernah restore backup dari device lain yang
/// datanya sempat basi akibat bug orphan-cleanup sinkron (fix `6455b9a`).
/// HANYA melapor + tautan ke Edit Produk — TIDAK menghapus otomatis, krn
/// baris mana yang "benar" tidak bisa ditentukan cuma dari data lokal (mis.
/// barcode mana yang labelnya sudah tercetak & dipakai kasir). Owner tinjau
/// & simpan ulang lewat form (delete-lama-insert-baru bawaan `saveProduct`
/// otomatis merapikan jadi 1 baris).
class DuplicateDataScreen extends ConsumerStatefulWidget {
  const DuplicateDataScreen({super.key});

  @override
  ConsumerState<DuplicateDataScreen> createState() =>
      _DuplicateDataScreenState();
}

class _DuplicateDataScreenState extends ConsumerState<DuplicateDataScreen> {
  List<MasterDataDuplicate>? _dupes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final dupes = await db.findMasterDataDuplicates();
    if (!mounted) return;
    setState(() => _dupes = dupes);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dupes = _dupes;

    // Group per produk supaya beberapa temuan produk yang sama tampil jadi
    // satu kartu (mis. barcode DAN tier dobel sekaligus di produk yang sama).
    final byProduct = <String, List<MasterDataDuplicate>>{};
    if (dupes != null) {
      for (final d in dupes) {
        (byProduct[d.productId] ??= []).add(d);
      }
    }
    final productIds = byProduct.keys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cek Duplikat Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Periksa ulang',
            onPressed: () => setState(() {
              _dupes = null;
              _load();
            }),
          ),
        ],
      ),
      body: dupes == null
          ? const Center(child: CircularProgressIndicator())
          : productIds.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Tidak ditemukan data duplikat. Database bersih.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${productIds.length} produk ditemukan punya baris '
                        'duplikat (barcode/harga). Ketuk produk untuk buka '
                        'Edit Produk, lalu tekan Simpan Produk untuk '
                        'merapikannya jadi satu baris.',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    for (final pid in productIds)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(byProduct[pid]!.first.productName),
                          subtitle: Text(byProduct[pid]!
                              .map((d) => '${d.unitName}: ${d.detail}')
                              .join('\n')),
                          isThreeLine: byProduct[pid]!.length > 1,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/produk/$pid'),
                        ),
                      ),
                  ],
                ),
    );
  }
}
