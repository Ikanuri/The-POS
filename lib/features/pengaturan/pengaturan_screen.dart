import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/device_provider.dart';
import '../../core/providers/theme_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_formatters.dart';

const _thousandsFmt = ThousandsSeparatorFormatter();

final _allowNegativeStockProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('allow_negative_stock');
  return v == '1';
});

/// Toggle tampilkan nama pegawai di struk share & cetak. Default ON.
final _showEmployeeProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final v = await db.getSetting('receipt_show_employee');
  return v == null || v == '1';
});

/// Aturan poin loyalitas: setiap belanja [threshold] rupiah → dapat [pointsPer]
/// poin. threshold = 0 menonaktifkan poin otomatis.
final loyaltyRuleProvider =
    FutureProvider<({int threshold, int pointsPer})>((ref) async {
  final db = ref.watch(databaseProvider);
  final t = int.tryParse(await db.getSetting('loyalty_point_threshold') ?? '') ?? 0;
  final p = int.tryParse(await db.getSetting('loyalty_points_per') ?? '') ?? 1;
  return (threshold: t, pointsPer: p < 1 ? 1 : p);
});

class PengaturanScreen extends ConsumerWidget {
  const PengaturanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(deviceProvider);
    final themeMode = ref.watch(themeModeProvider);
    final allowNegStock = ref.watch(_allowNegativeStockProvider).valueOrNull ?? false;
    final scheme = Theme.of(context).colorScheme;

    String roleLabel(String role) => switch (role) {
          'owner' => 'Owner',
          'asisten' => 'Asisten',
          'kasir' => 'Kasir',
          _ => role,
        };

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader('Device Ini'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary.withOpacity(0.14),
                    child: Text(
                      device.deviceCode.isEmpty ? '?' : device.deviceCode,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  title: Text(device.deviceName),
                  subtitle: Text(
                      '${roleLabel(device.deviceRole)} · ${device.storeName}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('Toko'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.store_outlined),
                  title: const Text('Informasi Toko'),
                  subtitle: const Text('Nama, alamat, telepon, catatan struk'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/toko'),
                ),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Metode Pembayaran'),
                  subtitle: const Text('QRIS, transfer bank, e-wallet'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/metode-bayar'),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Pegawai Toko'),
                  subtitle: const Text('Dicatat di tiap nota (yang melayani)'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/pegawai'),
                ),
                if (device.isOwner) ...[
                  Builder(builder: (context) {
                    final show =
                        ref.watch(_showEmployeeProvider).valueOrNull ?? true;
                    return SwitchListTile(
                      secondary: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Pegawai di Struk'),
                      subtitle: const Text(
                          'Tampilkan nama pegawai di struk share & cetak'),
                      value: show,
                      onChanged: (v) async {
                        final db = ref.read(databaseProvider);
                        await db.setSetting(
                            'receipt_show_employee', v ? '1' : '0');
                        ref.invalidate(_showEmployeeProvider);
                      },
                    );
                  }),
                ],
                if (device.isOwner) ...[
                  ListTile(
                    leading: const Icon(Icons.tune_outlined),
                    title: const Text('Izin Kasir'),
                    subtitle: const Text('Override harga, input stok, dll'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/izin-kasir'),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.remove_shopping_cart_outlined),
                    title: const Text('Izinkan Stok Minus'),
                    subtitle: const Text('Kasir bisa jual meski stok 0 (pre-order)'),
                    value: allowNegStock,
                    onChanged: (v) async {
                      final db = ref.read(databaseProvider);
                      await db.setSetting('allow_negative_stock', v ? '1' : '0');
                      ref.invalidate(_allowNegativeStockProvider);
                    },
                  ),
                  Builder(builder: (context) {
                    final rule =
                        ref.watch(loyaltyRuleProvider).valueOrNull;
                    final subtitle = rule == null || rule.threshold <= 0
                        ? 'Nonaktif — ketuk untuk mengatur'
                        : 'Setiap belanja ${formatRupiah(rule.threshold)} '
                            '→ ${rule.pointsPer} poin';
                    return ListTile(
                      leading: const Icon(Icons.stars_outlined),
                      title: const Text('Poin Loyalitas'),
                      subtitle: Text(subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showLoyaltyDialog(context, ref),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          const _SectionHeader('Sinkronisasi'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.wifi_outlined),
                  title: const Text('Sync WiFi'),
                  subtitle: const Text('Sinkronisasi antar HP via jaringan lokal'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/sync'),
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt_outlined),
                  title: const Text('Backup & Restore'),
                  subtitle: const Text('File terenkripsi .berkahpos'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/backup'),
                ),
                if (device.isOwner) ...[
                  ListTile(
                    leading: const Icon(Icons.upload_file_outlined),
                    title: const Text('Import Produk CSV'),
                    subtitle: const Text('Impor daftar produk dari file CSV'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/import-csv'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download_outlined),
                    title: const Text('Export Produk CSV'),
                    subtitle: const Text('Ekspor seluruh produk aktif ke CSV'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _exportProductsCsv(context, ref),
                  ),
                  ListTile(
                    leading: const Icon(Icons.qr_code_2_outlined),
                    title: const Text('Pair Device Baru'),
                    subtitle: const Text('Tambah HP kasir / asisten via QR'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/pair'),
                  ),
                ],
              ],
            ),
          ),
          if (device.isOwner) ...[
            const SizedBox(height: 8),
            const _SectionHeader('Manajemen Data'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: const Text('Tutup Buku'),
                    subtitle: const Text('Arsipkan transaksi tahun lalu'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/tutup-buku'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_zip_outlined),
                    title: const Text('Buka Arsip'),
                    subtitle: const Text('Lihat laporan tahun yang sudah diarsipkan'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/pengaturan/arsip'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          const _SectionHeader('Perangkat'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: const Text('Printer Bluetooth'),
                  subtitle: const Text('Pilih printer & test cetak'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/pengaturan/printer'),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Mode Gelap'),
                  value: themeMode == ThemeMode.dark,
                  onChanged: (_) =>
                      ref.read(themeModeProvider.notifier).toggle(),
                ),
                if (device.isOwner)
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('Diagnostic DB'),
                    subtitle: const Text('Cek duplikat tier & integritas data'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDiagnostic(context, ref),
                  ),
                Builder(builder: (context) {
                  final scale = ref.watch(fontScaleProvider);
                  return ListTile(
                    leading: const Icon(Icons.text_fields_outlined),
                    title: const Text('Ukuran Teks'),
                    subtitle: Text(scale.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showFontScaleDialog(context, ref),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFontScaleDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(fontScaleProvider);
    showDialog<FontScale>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Ukuran Teks'),
        children: FontScale.values.map((s) {
          return RadioListTile<FontScale>(
            title: Text(s.label),
            subtitle: Text(
              'Aa Bb Cc 123',
              style: TextStyle(fontSize: 14 * s.factor),
            ),
            value: s,
            groupValue: current,
            onChanged: (v) {
              if (v != null) {
                ref.read(fontScaleProvider.notifier).set(v);
                Navigator.pop(ctx, v);
              }
            },
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showLoyaltyDialog(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final curThreshold =
        int.tryParse(await db.getSetting('loyalty_point_threshold') ?? '') ?? 0;
    final curPer =
        int.tryParse(await db.getSetting('loyalty_points_per') ?? '') ?? 1;
    if (!context.mounted) return;

    final thresholdCtrl = TextEditingController(
        text: curThreshold > 0
            ? ThousandsSeparatorFormatter.format(curThreshold)
            : '');
    final perCtrl =
        TextEditingController(text: (curPer < 1 ? 1 : curPer).toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Poin Loyalitas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pelanggan terdaftar otomatis dapat poin tiap transaksi lunas. '
              'Kosongkan nominal untuk menonaktifkan.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: thresholdCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: const [_thousandsFmt],
              decoration: const InputDecoration(
                labelText: 'Setiap belanja (Rp)',
                prefixText: 'Rp ',
                hintText: 'mis. 10.000',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: perCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dapat berapa poin',
                suffixText: 'poin',
                hintText: 'mis. 1',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final threshold =
          ThousandsSeparatorFormatter.parseValue(thresholdCtrl.text);
      final per = int.tryParse(perCtrl.text.trim()) ?? 1;
      await db.setSetting('loyalty_point_threshold', threshold.toString());
      await db.setSetting('loyalty_points_per', (per < 1 ? 1 : per).toString());
      ref.invalidate(loyaltyRuleProvider);
    }
    thresholdCtrl.dispose();
    perCtrl.dispose();
  }
}

String _escapeCsv(String? value) {
  if (value == null || value.isEmpty) return '';
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

Future<void> _exportProductsCsv(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.of(context);

  try {
    final products = await db.searchProducts('');
    final unitTypes = await db.getAllUnitTypes();
    final typeNameById = {for (final u in unitTypes) u.id: u.name};

    final buf = StringBuffer();
    buf.writeln('nama,kode_produk,satuan,harga_jual,harga_beli,stok,barcode');

    for (final p in products) {
      final units = await db.getProductUnits(p.id);
      for (final u in units) {
        final tiers = await db.getPriceTiers(u.id);
        final baseTier =
            tiers.where((t) => t.minQty == 1).firstOrNull ?? tiers.firstOrNull;
        final barcodes = await db.getProductBarcodes(u.id);
        final barcode = barcodes.firstOrNull?.barcode ?? '';
        final stock = await db.currentStock(u.id);
        final unitName = u.unitTypeId != null
            ? (typeNameById[u.unitTypeId!] ?? '')
            : '';

        buf.writeln([
          _escapeCsv(p.name),
          _escapeCsv(p.kodeProduk),
          _escapeCsv(unitName),
          baseTier?.price ?? 0,
          baseTier?.costPrice ?? 0,
          stock % 1 == 0 ? stock.toInt() : stock,
          _escapeCsv(barcode),
        ].join(','));
      }
    }

    final bytes = utf8.encode(buf.toString());
    final date = DateFormat('yyyyMMdd').format(DateTime.now());
    await FilePicker.platform.saveFile(
      fileName: 'produk_$date.csv',
      bytes: Uint8List.fromList(bytes),
      type: FileType.any,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('${products.length} produk diekspor ke CSV')),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Gagal ekspor: $e')),
    );
  }
}

Future<void> _showDiagnostic(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final buf = StringBuffer();

  // 1. Duplikat tier minQty=1
  final dupTiers = await db.customSelect('''
    SELECT pt.product_unit_id, COUNT(*) as cnt,
           GROUP_CONCAT(pt.id || ':' || pt.price || ':' || pt.cost_price, ' | ') as detail
    FROM price_tiers pt
    WHERE pt.min_qty = 1
    GROUP BY pt.product_unit_id
    HAVING cnt > 1
  ''').get();

  buf.writeln('=== DUPLIKAT TIER (minQty=1) ===');
  buf.writeln('Jumlah unit dengan duplikat: ${dupTiers.length}');
  for (final r in dupTiers) {
    final unitId = r.data['product_unit_id'] as String;
    final cnt = r.data['cnt'] as int;
    final detail = r.data['detail'] as String;

    // Cari nama produk
    final prodRow = await db.customSelect('''
      SELECT p.name, ut.name as unit_name
      FROM product_units pu
      JOIN products p ON p.id = pu.product_id
      LEFT JOIN unit_types ut ON ut.id = pu.unit_type_id
      WHERE pu.id = ?
    ''', variables: [Variable.withString(unitId)]).getSingleOrNull();
    final pName = prodRow?.data['name'] ?? '?';
    final uName = prodRow?.data['unit_name'] ?? '?';

    buf.writeln('');
    buf.writeln('[$pName] ($uName) — $cnt tiers:');
    for (final d in detail.split(' | ')) {
      final parts = d.split(':');
      if (parts.length >= 3) {
        buf.writeln('  id=${parts[0].length > 8 ? parts[0].substring(0, 8) : parts[0]}… '
            'price=${parts[1]} cost=${parts[2]}');
      }
    }
  }

  // 2. Ringkasan total
  final totalTiers = await db.customSelect(
    'SELECT COUNT(*) as cnt FROM price_tiers WHERE min_qty = 1'
  ).getSingle();
  final totalUnits = await db.customSelect(
    'SELECT COUNT(*) as cnt FROM product_units'
  ).getSingle();
  final totalProducts = await db.customSelect(
    'SELECT COUNT(*) as cnt FROM products WHERE is_active = 1'
  ).getSingle();

  buf.writeln('');
  buf.writeln('=== RINGKASAN ===');
  buf.writeln('Produk aktif: ${totalProducts.data['cnt']}');
  buf.writeln('Unit total: ${totalUnits.data['cnt']}');
  buf.writeln('Tier minQty=1 total: ${totalTiers.data['cnt']}');
  buf.writeln('Unit dengan tier duplikat: ${dupTiers.length}');

  if (!context.mounted) return;
  final text = buf.toString();

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Expanded(
              child: Text('Diagnostic DB', style: TextStyle(fontSize: 16))),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Disalin ke clipboard')));
            },
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

