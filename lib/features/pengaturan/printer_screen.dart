import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../core/services/printer_service.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  List<BluetoothInfo> _devices = [];
  String? _savedMac;
  bool _loading = true;
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

  Future<void> _select(BluetoothInfo device) async {
    await PrinterService.saveMac(device.macAdress);
    if (!mounted) return;
    setState(() => _savedMac = device.macAdress);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Printer dipilih: ${device.name}')),
    );
  }

  Future<void> _testPrint(BluetoothInfo device) async {
    setState(() => _testingMac = device.macAdress);
    try {
      final ok = await PrinterService.testPrint(device.macAdress);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Test print berhasil!' : 'Gagal menghubungi printer'),
        backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    } finally {
      if (mounted) setState(() => _testingMac = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Bluetooth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permGranted == false
              ? _MessageState(
                  icon: Icons.lock_outline,
                  message:
                      'Izin Bluetooth belum diberikan.\nAplikasi butuh izin '
                      '"Perangkat di sekitar" untuk menyambung ke printer.',
                  actionLabel: 'Buka Pengaturan Izin',
                  onAction: () => openAppSettings(),
                  secondaryLabel: 'Coba Lagi',
                  onSecondary: () {
                    setState(() => _loading = true);
                    _load();
                  },
                )
              : _btOff
                  ? _MessageState(
                      icon: Icons.bluetooth_disabled,
                      message:
                          'Bluetooth mati.\nAktifkan Bluetooth HP lalu coba lagi.',
                      actionLabel: 'Coba Lagi',
                      onAction: () {
                        setState(() => _loading = true);
                        _load();
                      },
                    )
                  : _devices.isEmpty
                      ? _MessageState(
                          icon: Icons.print_disabled_outlined,
                          message:
                              'Tidak ada printer Bluetooth yang dipasangkan.\n'
                              'Pasangkan printer dulu di Pengaturan Bluetooth HP, '
                              'lalu kembali dan tekan Coba Lagi.',
                          actionLabel: 'Coba Lagi',
                          onAction: () {
                            setState(() => _loading = true);
                            _load();
                          },
                        )
                      : Column(
                  children: [
                    if (_savedMac != null)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Icon(Icons.print, size: 16, color: scheme.onPrimaryContainer),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Printer aktif: $_savedMac',
                              style: TextStyle(
                                  fontSize: 12, color: scheme.onPrimaryContainer),
                            ),
                          ),
                        ]),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _devices.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 56),
                        itemBuilder: (_, i) {
                          final d = _devices[i];
                          final isSelected = d.macAdress == _savedMac;
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
                            title: Text(d.name),
                            subtitle: Text(d.macAdress,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant)),
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
                                    onPressed: () => _testPrint(d),
                                  ),
                                if (!isSelected)
                                  FilledButton.tonal(
                                    onPressed: () => _select(d),
                                    child: const Text('Pilih', style: TextStyle(fontSize: 12)),
                                  )
                                else
                                  Chip(
                                    label: const Text('Aktif',
                                        style: TextStyle(fontSize: 11)),
                                    backgroundColor: scheme.primaryContainer,
                                    side: BorderSide.none,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
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
      child: Padding(
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
