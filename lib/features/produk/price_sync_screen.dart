import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/device_provider.dart';
import '../../core/services/price_match_service.dart';
import '../../core/services/price_sync_service.dart';
import '../../core/widgets/inline_banner.dart';
import '../../core/widgets/qr_sync_widgets.dart';

class PriceSyncScreen extends ConsumerStatefulWidget {
  const PriceSyncScreen({super.key});

  @override
  ConsumerState<PriceSyncScreen> createState() => _PriceSyncScreenState();
}

class _PriceSyncScreenState extends ConsumerState<PriceSyncScreen>
    with InlineBannerStateMixin<PriceSyncScreen> {
  bool _hostRunning = false;
  String _hostIp = '';
  String _hostCode = '';

  final _ipCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _fetching = false;

  // Item 35(opsional) — mode "sinkron via barcode saja": lewati SKU/fuzzy
  // sepenuhnya. Berguna kalau kode produk (SKU) toko sumber tidak bisa
  // dipercaya (mis. diisi nama satuan "Dos"/"Pak", lihat PLAN.md Item 35).
  bool _barcodeOnly = false;

  @override
  void dispose() {
    PriceSyncService.stopHost();
    _ipCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleHost() async {
    if (_hostRunning) {
      await PriceSyncService.stopHost();
      setState(() {
        _hostRunning = false;
        _hostIp = '';
        _hostCode = '';
      });
      return;
    }
    try {
      final db = ref.read(databaseProvider);
      final (ip, code) = await PriceSyncService.startHost(db: db);
      setState(() {
        _hostRunning = true;
        _hostIp = ip;
        _hostCode = code;
      });
    } catch (e) {
      if (!mounted) return;
      showError('Gagal start server: $e');
    }
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    showSuccess('$label disalin: $value');
  }

  Future<void> _fetchFromHost() async {
    final ip = _ipCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (ip.isEmpty || code.isEmpty) {
      showError('Masukkan IP dan Kode');
      return;
    }
    setState(() => _fetching = true);
    try {
      final catalog = await PriceSyncService.fetchFromHost(
        hostIp: ip,
        pairingCode: code,
      );
      if (!mounted) return;
      if (catalog.isEmpty) {
        showError('Tidak ada data produk dari host');
        return;
      }
      final db = ref.read(databaseProvider);
      final result = await PriceMatchService.match(
          db: db, catalog: catalog, barcodeOnly: _barcodeOnly);
      if (!mounted) return;
      context.push('/produk/sinkron-harga/preview', extra: result);
    } catch (e) {
      if (!mounted) return;
      showError('Gagal: $e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _importCsv() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (picked == null || picked.files.single.bytes == null) return;
      final bytes = picked.files.single.bytes!;

      var content = utf8.decode(bytes, allowMalformed: true);
      if (content.startsWith('﻿')) content = content.substring(1);

      final catalog = _parsePriceCsv(content);
      if (catalog.isEmpty) {
        showError('CSV kosong atau format tidak dikenali');
        return;
      }

      if (!mounted) return;
      final db = ref.read(databaseProvider);
      final result = await PriceMatchService.match(
          db: db, catalog: catalog, barcodeOnly: _barcodeOnly);
      if (!mounted) return;
      context.push('/produk/sinkron-harga/preview', extra: result);
    } catch (e) {
      if (!mounted) return;
      showError('Gagal baca CSV: $e');
    }
  }

  Future<void> _exportCsv() async {
    try {
      final db = ref.read(databaseProvider);
      final catalog = await PriceSyncService.buildCatalog(db);

      String esc(String? v) {
        if (v == null || v.isEmpty) return '';
        if (v.contains(',') || v.contains('"') || v.contains('\n')) {
          return '"${v.replaceAll('"', '""')}"';
        }
        return v;
      }

      final buf = StringBuffer();
      buf.writeln('nama,kode_produk,barcode,satuan,harga_jual,harga_beli,'
          'induk_nama,induk_kode,satuan_dasar,rasio');
      for (final item in catalog) {
        buf.writeln([
          esc(item.productName),
          esc(item.kodeProduk),
          esc(item.barcode),
          esc(item.unitTypeName),
          item.price,
          item.costPrice,
          esc(item.parentName),
          esc(item.parentKode),
          item.isBaseUnit ? 1 : 0,
          item.ratioToBase,
        ].join(','));
      }

      final now = DateTime.now();
      String p(int n) => n.toString().padLeft(2, '0');
      final date = '${now.year}${p(now.month)}${p(now.day)}';
      await FilePicker.platform.saveFile(
        fileName: 'katalog_harga_$date.csv',
        bytes: Uint8List.fromList(utf8.encode(buf.toString())),
        type: FileType.any,
      );
      if (!mounted) return;
      showSuccess('${catalog.length} item katalog diekspor ke CSV');
    } catch (e) {
      if (!mounted) return;
      showError('Gagal ekspor: $e');
    }
  }

  List<PriceCatalogItem> _parsePriceCsv(String content) {
    final lines =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    if (lines.isEmpty) return [];

    final header =
        _parseLine(lines.first).map((h) => h.trim().toLowerCase()).toList();
    final items = <PriceCatalogItem>[];

    String col(List<String> aliases, List<String> row) {
      for (final alias in aliases) {
        final idx = header.indexOf(alias);
        if (idx >= 0 && idx < row.length) return row[idx].trim();
      }
      return '';
    }

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final row = _parseLine(line);

      final name =
          col(['nama', 'name', 'product_name', 'nama_produk'], row);
      if (name.isEmpty) continue;

      final priceStr =
          col(['harga_jual', 'harga', 'sell_price', 'price'], row);
      final costStr =
          col(['harga_beli', 'cost', 'buy_price', 'cogs'], row);
      final kode = col(['kode', 'kode_produk', 'code', 'sku'], row);
      final barcode = col(['barcode', 'kode_barcode', 'ean', 'upc'], row);

      items.add(PriceCatalogItem(
        productName: name,
        kodeProduk: kode.isEmpty ? null : kode,
        barcode: barcode.isEmpty ? null : barcode,
        unitTypeName: col(['satuan', 'unit', 'uom', 'unit_type'], row),
        price: _parseIntPrice(priceStr),
        costPrice: _parseIntPrice(costStr),
      ));
    }
    return items;
  }

  static int _parseIntPrice(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 0;
    final direct = int.tryParse(s);
    if (direct != null) return direct;
    final noThousands = s.replaceAll('.', '');
    final noDots = int.tryParse(noThousands);
    if (noDots != null) return noDots;
    final noCommas = s.replaceAll(',', '');
    final noCommaInt = int.tryParse(noCommas);
    if (noCommaInt != null) return noCommaInt;
    return (double.tryParse(s) ?? 0).round();
  }

  static List<String> _parseLine(String line) {
    final fields = <String>[];
    var field = StringBuffer();
    var inQuote = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (c == ',' && !inQuote) {
        fields.add(field.toString());
        field = StringBuffer();
      } else {
        field.write(c);
      }
    }
    fields.add(field.toString());
    return fields;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sinkron Harga')),
      body: Column(
        children: [
          inlineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Host card ──
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.wifi_tethering_outlined,
                              color: scheme.primary),
                          const SizedBox(width: 8),
                          Text('Bagikan Harga',
                              style: Theme.of(context).textTheme.titleMedium),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          'Toko lain bisa mengambil daftar harga dari '
                          'perangkat ini selama terhubung ke WiFi yang sama.',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        if (_hostRunning) ...[
                          _InfoRow(
                            label: 'IP',
                            value: '$_hostIp:8626',
                            onCopy: () => _copy('$_hostIp:8626', 'IP'),
                          ),
                          const SizedBox(height: 6),
                          _InfoRow(
                            label: 'Kode',
                            value: _hostCode,
                            onCopy: () => _copy(_hostCode, 'Kode'),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: QrSyncDisplay(data: {
                              'ip': '$_hostIp:8626',
                              'key': _hostCode,
                            }),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: _toggleHost,
                            child: const Text('Stop Server'),
                          ),
                        ] else
                          FilledButton.icon(
                            onPressed: _toggleHost,
                            icon: const Icon(Icons.play_arrow_outlined),
                            label: const Text('Start Server'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Mode barcode-saja (Item 35 opsional) ──
                Card(
                  child: SwitchListTile(
                    value: _barcodeOnly,
                    onChanged: (v) => setState(() => _barcodeOnly = v),
                    title: const Text('Sinkron via barcode saja'),
                    subtitle: const Text(
                        'Lewati pencocokan kode produk (SKU) & nama mirip — '
                        'hanya cocokkan lewat barcode. Aman dipakai kalau '
                        'kode produk toko sumber tidak bisa dipercaya.',
                        style: TextStyle(fontSize: 12)),
                    dense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // ── Client card ──
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.download_outlined, color: scheme.secondary),
                          const SizedBox(width: 8),
                          Text('Ambil Harga',
                              style: Theme.of(context).textTheme.titleMedium),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          'Scan QR atau masukkan IP dan Kode dari toko '
                          'yang membagikan harga.',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final data = await showQrSyncScanner(context);
                            if (data == null || !mounted) return;
                            var ip = data['ip'] as String? ?? '';
                            final key = data['key'] as String? ?? '';
                            if (ip.contains(':')) ip = ip.split(':').first;
                            if (ip.isNotEmpty) _ipCtrl.text = ip;
                            if (key.isNotEmpty) _codeCtrl.text = key;
                          },
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          label: const Text('Scan QR Host'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _ipCtrl,
                          decoration: const InputDecoration(
                            labelText: 'IP Host (misal: 192.168.1.5)',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _codeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Kode (6 digit)',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                        const SizedBox(height: 4),
                        if (_fetching)
                          const Row(children: [
                            SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Mengambil data…'),
                          ])
                        else
                          FilledButton.icon(
                            onPressed: _fetchFromHost,
                            icon: const Icon(Icons.sync),
                            label: const Text('Ambil Harga'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── CSV card ──
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.description_outlined,
                              color: scheme.tertiary),
                          const SizedBox(width: 8),
                          Text('Import dari CSV',
                              style: Theme.of(context).textTheme.titleMedium),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          'Pilih file CSV yang berisi kolom barcode/kode, '
                          'nama, dan harga.',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _importCsv,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Pilih File CSV'),
                        ),
                        const Divider(height: 24),
                        Text(
                          'Ekspor seluruh katalog harga ke file CSV untuk '
                          'dibagikan atau diimpor di perangkat lain.',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _exportCsv,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Export ke CSV'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.onCopy});
  final String label;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2, right: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              tooltip: 'Salin',
              visualDensity: VisualDensity.compact,
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}
