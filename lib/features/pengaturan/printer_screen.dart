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

  /// null = belum dicek, false = ditolak, true = diberikan
  bool? _permGranted;
  bool _btOff = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final savedMac = await PrinterService.getSavedMac();

    // Minta izin Bluetooth runtime DULU. Tanpa ini, plugin menggantung di
    // Android 12+ (Future tidak pernah selesai → layar loading selamanya).
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

  /// "Scan ulang" — segarkan daftar perangkat Bluetooth yang terpasang.
  /// Catatan: printer thermal (Bluetooth Classic/SPP) harus dipasangkan dulu
  /// lewat Pengaturan Bluetooth HP agar bisa muncul & disambung di sini.
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
    setState(() => _testingMac = mac);
    try {
      final ok = await PrinterService.testPrint(mac);
      if (!mounted) return;
      AppTheme.showSnack(
          context, ok ? 'Test print berhasil!' : 'Gagal menghubungi printer',
          isError: !ok);
    } catch (e) {
      if (!mounted) return;
      AppTheme.showSnack(context, 'Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _testingMac = null);
    }
  }

  /// Input MAC manual — jalan pintas bila printer tidak muncul di daftar.
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
              'Masukkan alamat MAC printer (lihat di Pengaturan Bluetooth HP).',
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
                labelText: 'MAC',
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
    AppTheme.showSnack(context, 'Printer manual disimpan: $mac');
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
        Expanded(
          child: _devices.isEmpty
              ? _MessageState(
                  icon: Icons.print_disabled_outlined,
                  message: 'Belum ada printer terpasang.\n'
                      'Pasangkan printer di Pengaturan Bluetooth HP, lalu tekan '
                      'Scan. Atau masukkan alamat MAC printer secara manual.',
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
      ],
    );
  }

  Widget _deviceTile(BuildContext context, BluetoothInfo d) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = d.macAdress == _savedMac;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isSelected
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        child: Icon(
          Icons.print_outlined,
          color:
              isSelected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(d.name.isEmpty ? 'Printer' : d.name),
      subtitle: Text(d.macAdress,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_testingMac == d.macAdress)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: const Icon(Icons.print_outlined, size: 20),
              tooltip: 'Test Print',
              onPressed: () => _testPrint(d.macAdress),
            ),
          if (!isSelected)
            FilledButton.tonal(
              onPressed: () => _select(d),
              child: const Text('Pilih', style: TextStyle(fontSize: 12)),
            )
          else
            Chip(
              label: const Text('Aktif', style: TextStyle(fontSize: 11)),
              backgroundColor: scheme.primaryContainer,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
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
