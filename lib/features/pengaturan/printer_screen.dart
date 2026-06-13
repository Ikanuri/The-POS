import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/services/printer_service.dart';
import '../../core/theme/app_theme.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  List<BluetoothInfo> _devices = [];
  String? _savedMac;
  bool _loading = true;
  bool _scanning = false;
  String? _testingMac;

  bool? _permGranted;
  bool _btOff = false;

  // ── Log debug ─────────────────────────────────────────────────────────────
  final List<PrintLogEntry> _log = [];
  bool _logExpanded = false;
  final _logScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final savedMac = await PrinterService.getSavedMac();

    final granted = await PrinterService.ensurePermissions();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _savedMac = savedMac;
        _permGranted = false;
        _devices = [];
        _loading = false;
      });
      return;
    }

    final btEnabled = await PrinterService.isBluetoothOn();
    List<BluetoothInfo> devices = [];
    if (btEnabled) {
      devices = await PrinterService.getPairedDevices();
    }
    if (!mounted) return;
    setState(() {
      _savedMac = savedMac;
      _permGranted = true;
      _btOff = !btEnabled;
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _rescan() async {
    setState(() => _scanning = true);
    final btEnabled = await PrinterService.isBluetoothOn();
    final devices =
        btEnabled ? await PrinterService.getPairedDevices() : <BluetoothInfo>[];
    if (!mounted) return;
    setState(() {
      _btOff = !btEnabled;
      _devices = devices;
      _scanning = false;
    });
  }

  Future<void> _select(BluetoothInfo device) async {
    await PrinterService.saveMac(device.macAdress);
    if (!mounted) return;
    setState(() => _savedMac = device.macAdress);
    AppTheme.showSnack(context, 'Printer dipilih: ${device.name}');
  }

  Future<void> _testPrint(String mac) async {
    setState(() {
      _testingMac = mac;
      _log.clear();
      _logExpanded = true;
    });
    try {
      final (ok, entries) = await PrinterService.testPrintDetailed(mac);
      if (!mounted) return;
      setState(() => _log.addAll(entries));
      // Scroll ke bawah log setelah frame render
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollCtrl.hasClients) {
          _logScrollCtrl.animateTo(
            _logScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      if (!mounted) return;
      AppTheme.showSnack(
          context, ok ? 'Test print berhasil!' : 'Gagal — lihat log di bawah',
          isError: !ok);
    } catch (e) {
      if (!mounted) return;
      AppTheme.showSnack(context, 'Exception: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testingMac = null);
    }
  }

  Future<void> _addManual() async {
    final nameCtrl = TextEditingController();
    final macCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Printer Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Masukkan alamat MAC printer.\n'
              'Lihat di Pengaturan Bluetooth HP → nama printer → detail.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nama (opsional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: macCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9A-Fa-f:]')),
              ],
              decoration: const InputDecoration(
                labelText: 'MAC Address',
                hintText: '00:11:22:33:44:55',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (result != true) return;
    final mac = macCtrl.text.trim().toUpperCase();
    if (mac.length < 11) {
      if (mounted) AppTheme.showSnack(context, 'MAC tidak valid', isError: true);
      return;
    }
    await PrinterService.saveMac(mac);
    if (!mounted) return;
    setState(() {
      _savedMac = mac;
      final exists = _devices.any((d) => d.macAdress == mac);
      if (!exists) {
        _devices = [
          BluetoothInfo(
              name: nameCtrl.text.trim().isEmpty
                  ? 'Printer Manual'
                  : nameCtrl.text.trim(),
              macAdress: mac),
          ..._devices,
        ];
      }
    });
    AppTheme.showSnack(context, 'Printer disimpan: $mac');
  }

  void _copyLog() {
    final text = _log.map((e) => e.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    AppTheme.showSnack(context, 'Log disalin ke clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Bluetooth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Tambah MAC manual',
            onPressed: _addManual,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Muat ulang',
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permGranted == false) {
      return _MessageState(
        icon: Icons.lock_outline,
        message: 'Izin Bluetooth belum diberikan.\nAplikasi butuh izin '
            '"Perangkat di sekitar" untuk menyambung ke printer.',
        actionLabel: 'Buka Pengaturan Izin',
        onAction: openAppSettings,
        secondaryLabel: 'Coba Lagi',
        onSecondary: _load,
      );
    }
    if (_btOff) {
      return _MessageState(
        icon: Icons.bluetooth_disabled,
        message: 'Bluetooth mati.\nAktifkan Bluetooth HP lalu coba lagi.',
        actionLabel: 'Coba Lagi',
        onAction: _load,
      );
    }
    return _buildDeviceList(context);
  }

  Widget _buildDeviceList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner printer aktif
        if (_savedMac != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.print, size: 16, color: scheme.onPrimaryContainer),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Printer aktif: $_savedMac',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),

        // Header daftar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('Perangkat terpasang',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: _scanning ? null : _rescan,
                icon: _scanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bluetooth_searching, size: 18),
                label: const Text('Scan'),
              ),
            ],
          ),
        ),

        // Daftar perangkat
        Expanded(
          child: _devices.isEmpty
              ? _MessageState(
                  icon: Icons.print_disabled_outlined,
                  message: 'Belum ada printer terpasang.\n'
                      'Pasangkan printer di Pengaturan Bluetooth HP, '
                      'lalu tekan Scan. Atau masukkan alamat MAC printer secara manual.',
                  actionLabel: 'Tambah MAC Manual',
                  onAction: _addManual,
                  secondaryLabel: 'Scan Ulang',
                  onSecondary: _rescan,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _devices.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 56),
                  itemBuilder: (_, i) => _deviceTile(context, _devices[i]),
                ),
        ),

        // Panel log debug (bisa dilipat)
        if (_log.isNotEmpty) _buildLogPanel(context, scheme),
      ],
    );
  }

  Widget _deviceTile(BuildContext context, BluetoothInfo d) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = d.macAdress == _savedMac;
    final isTesting = _testingMac == d.macAdress;

    final btnStyle = FilledButton.styleFrom(
      minimumSize: const Size(62, 34),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12),
    );

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isSelected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        child: Icon(
          Icons.print_outlined,
          color: isSelected
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(d.name.isEmpty ? 'Printer' : d.name),
      subtitle: Text(d.macAdress,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTesting)
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              icon: const Icon(Icons.print_outlined, size: 20),
              tooltip: 'Test Print + Lihat Log',
              visualDensity: VisualDensity.compact,
              onPressed: () => _testPrint(d.macAdress),
            ),
          const SizedBox(width: 4),
          if (!isSelected)
            FilledButton.tonal(
              onPressed: () => _select(d),
              style: btnStyle,
              child: const Text('Pilih'),
            )
          else
            Chip(
              label: const Text('Aktif', style: TextStyle(fontSize: 11)),
              backgroundColor: scheme.primaryContainer,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Widget _buildLogPanel(BuildContext context, ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logBg = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F0F8);
    final logFg = isDark ? const Color(0xFFE0E0F0) : const Color(0xFF1A1A3E);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      constraints: BoxConstraints(
        maxHeight: _logExpanded ? 240 : 44,
      ),
      decoration: BoxDecoration(
        color: logBg,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header bar
          InkWell(
            onTap: () => setState(() => _logExpanded = !_logExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.terminal,
                      size: 16, color: logFg.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Log Debug (${_log.length} langkah)',
                      style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: logFg.withOpacity(0.8)),
                    ),
                  ),
                  // Status ringkas — ikon hasil akhir
                  if (_log.isNotEmpty)
                    Icon(
                      _log.last.ok == true
                          ? Icons.check_circle
                          : _log.last.ok == false
                              ? Icons.cancel
                              : Icons.info_outline,
                      size: 16,
                      color: _log.last.ok == true
                          ? Colors.green
                          : _log.last.ok == false
                              ? Colors.red
                              : logFg.withOpacity(0.6),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Salin log',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    onPressed: _copyLog,
                    color: logFg.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _logExpanded
                        ? Icons.expand_more
                        : Icons.chevron_right,
                    size: 18,
                    color: logFg.withOpacity(0.6),
                  ),
                ],
              ),
            ),
          ),

          // Log lines
          if (_logExpanded)
            Expanded(
              child: ListView.builder(
                controller: _logScrollCtrl,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _log.length,
                itemBuilder: (_, i) {
                  final e = _log[i];
                  final Color lineColor;
                  if (e.ok == true) {
                    lineColor = Colors.green.shade400;
                  } else if (e.ok == false) {
                    lineColor = Colors.red.shade400;
                  } else {
                    lineColor = logFg.withOpacity(0.7);
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: logFg.withOpacity(0.5)),
                        children: [
                          TextSpan(text: '[${e.timeStr}] '),
                          TextSpan(
                            text: e.step,
                            style: TextStyle(
                                color: lineColor,
                                fontWeight: e.ok != null
                                    ? FontWeight.w600
                                    : FontWeight.normal),
                          ),
                          if (e.ok == true)
                            TextSpan(
                                text: ' ✓',
                                style: TextStyle(color: Colors.green.shade400)),
                          if (e.ok == false)
                            TextSpan(
                                text: ' ✗',
                                style: TextStyle(color: Colors.red.shade400)),
                          if (e.detail != null)
                            TextSpan(
                              text: ': ${e.detail}',
                              style: TextStyle(
                                  color: logFg.withOpacity(0.5),
                                  fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: scheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
