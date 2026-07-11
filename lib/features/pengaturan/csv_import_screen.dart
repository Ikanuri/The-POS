import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/csv_import_service.dart';
import '../../core/widgets/inline_banner.dart';

/// Import produk dari CSV. [griyoMode] menampilkan varian "Import dari Griyo
/// POS" — **EKSPERIMENTAL**: judul, bantuan format, dan badge eksperimental
/// disesuaikan untuk migrasi dari Griyo POS, tapi memakai [CsvImportService]
/// yang sama persis (parser otomatis kenali pemisah `;`/`,` dan skema
/// legacy Griyo, jadi tetap kompatibel dengan CSV format bebas biasa).
class CsvImportScreen extends ConsumerStatefulWidget {
  const CsvImportScreen({super.key, this.griyoMode = false});
  final bool griyoMode;

  @override
  ConsumerState<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends ConsumerState<CsvImportScreen>
    with InlineBannerStateMixin<CsvImportScreen> {
  bool _busy = false;

  Future<void> _pickAndImport() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final bytes = result.files.single.bytes!;
    final fileName = result.files.single.name;

    if (!mounted) return;
    // Konfirmasi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.griyoMode ? 'Import dari Griyo POS' : 'Import Produk CSV'),
        content: Text('Import "$fileName"?\n\nProduk duplikat (nama+satuan sama) akan dilewati.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Import')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final db = ref.read(databaseProvider);
      final result2 = await CsvImportService.importFromBytes(bytes: bytes, db: db);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hasil Import'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResultRow(label: 'Diimport', value: result2.imported, icon: Icons.check_circle_outline, color: Colors.green),
              _ResultRow(label: 'Harga produk lama diperbarui', value: result2.updated, icon: Icons.update_outlined),
              _ResultRow(label: 'Duplikat dilewati', value: result2.duplicates, icon: Icons.skip_next_outlined),
              _ResultRow(label: 'Tanpa barcode', value: result2.noBarcode, icon: Icons.qr_code_outlined),
              if (result2.sameNameDifferentUnit > 0) ...[
                _ResultRow(
                  label: 'Nama sama, satuan beda (cek manual)',
                  value: result2.sameNameDifferentUnit,
                  icon: Icons.warning_amber_outlined,
                  color: Colors.orange,
                ),
                const SizedBox(height: 4),
                Text(
                  'Produk ini masuk sebagai entri terpisah (bukan 1 produk '
                  'multi-satuan) karena rasio konversi antar satuan tidak '
                  'ada di CSV. Gabung manual lewat Edit Produk bila perlu.',
                  style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ],
              if (result2.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${result2.errors.length} baris error:',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: result2.errors
                          .map((e) => Text(e,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(ctx).colorScheme.error)))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showError('Gagal import: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.griyoMode
              ? 'Import dari Griyo POS'
              : 'Import Produk CSV')),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.griyoMode) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.science_outlined,
                            size: 14, color: scheme.onTertiaryContainer),
                        const SizedBox(width: 5),
                        Text('Eksperimental',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: scheme.onTertiaryContainer)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Format CSV',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          widget.griyoMode
                              ? 'File export produk dari Griyo POS (pemisah '
                                  '";") langsung didukung — kolom "Produk", '
                                  '"Kode Produk", "Grup Produk", "Satuan", '
                                  '"Harga Jual", "Harga Pokok", "Stok", '
                                  '"Barcode" dikenali otomatis. Kolom Satuan '
                                  '& Grup Produk berisi kode angka bawaan '
                                  'Griyo — otomatis dipetakan ke satuan/grup '
                                  'yang sesuai.\n\nProduk dengan nama sama '
                                  'tapi satuan berbeda (mis. Slop & Pak) '
                                  'TIDAK digabung otomatis jadi satu produk '
                                  'multi-satuan (rasio konversi antar satuan '
                                  'tidak ada di file Griyo) — akan ditandai '
                                  'di hasil import untuk digabung manual '
                                  'lewat Edit Produk bila perlu.'
                              : 'File CSV harus memiliki baris header. '
                                  'Kolom yang dikenali:\n\n'
                                  '• nama / name / product_name\n'
                                  '• kode / kode_produk / sku\n'
                                  '• grup / kategori / group\n'
                                  '• satuan / unit / uom\n'
                                  '• harga_jual / harga / sell_price\n'
                                  '• harga_beli / cost / buy_price\n'
                                  '• stok / stock / qty\n'
                                  '• barcode / ean / upc',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _pickAndImport,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Pilih File CSV'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
  final String label;
  final int value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 18, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }
}
