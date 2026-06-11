import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final savedMac = await PrinterService.getSavedMac();
    final btEnabled = await PrintBluetoothThermal.bluetoothEnabled;
    List<BluetoothInfo> devices = [];
    if (btEnabled) {
      devices = await PrinterService.getPairedDevices();
    }
    if (!mounted) return;
    setState(() {
      _savedMac = savedMac;
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
          : _devices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bluetooth_disabled, size: 64, color: scheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text(
                        'Tidak ada printer Bluetooth yang dipasangkan.\n'
                        'Pasangkan printer terlebih dahulu di Pengaturan Bluetooth HP.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
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
