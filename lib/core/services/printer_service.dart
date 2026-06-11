import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';

class PrinterService {
  PrinterService._();

  static const _prefMac = 'printer_mac';

  static Future<String?> getSavedMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefMac);
  }

  static Future<void> saveMac(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMac, mac);
  }

  static Future<List<BluetoothInfo>> getPairedDevices() async =>
      PrintBluetoothThermal.pairedBluetooths;

  static Future<bool> connect(String mac) async =>
      PrintBluetoothThermal.connect(macPrinterAddress: mac);

  static Future<bool> get isConnected async =>
      PrintBluetoothThermal.connectionStatus;

  static Future<bool> disconnect() async =>
      PrintBluetoothThermal.disconnect;

  /// Bangun bytes ESC/POS struk dan kirim ke printer.
  static Future<bool> printReceipt({
    required Transaction tx,
    required List<TransactionItem> items,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
    required Customer? customer,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String? strukNote,
  }) async {
    final mac = await getSavedMac();
    if (mac == null || mac.isEmpty) return false;

    final connected = await connect(mac);
    if (!connected) return false;

    final bytes = await _buildBytes(
      tx: tx,
      items: items,
      productNames: productNames,
      unitNames: unitNames,
      customer: customer,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      strukNote: strukNote,
    );

    return PrintBluetoothThermal.writeBytes(bytes);
  }

  static Future<bool> testPrint(String mac) async {
    final connected = await connect(mac);
    if (!connected) return false;

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[
      ...generator.text('TEST PRINT', styles: const PosStyles(
        bold: true,
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      )),
      ...generator.text('Printer Bluetooth OK', styles: const PosStyles(align: PosAlign.center)),
      ...generator.feed(3),
      ...generator.cut(),
    ];

    return PrintBluetoothThermal.writeBytes(Uint8List.fromList(bytes));
  }

  static Future<Uint8List> _buildBytes({
    required Transaction tx,
    required List<TransactionItem> items,
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
    required Customer? customer,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String? strukNote,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    final out = <int>[];

    // Header toko
    out.addAll(gen.text(storeName.isEmpty ? 'Toko' : storeName,
        styles: const PosStyles(bold: true, align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2)));
    if (storeAddress.isNotEmpty) {
      out.addAll(gen.text(storeAddress, styles: const PosStyles(align: PosAlign.center)));
    }
    if (storePhone.isNotEmpty) {
      out.addAll(gen.text('Telp: $storePhone', styles: const PosStyles(align: PosAlign.center)));
    }
    out.addAll(gen.hr());

    // Info transaksi
    final tanggal = _fmtDateTime(tx.createdAt);
    out.addAll(gen.row([
      PosColumn(text: 'No', width: 3),
      PosColumn(text: tx.localId, width: 9),
    ]));
    out.addAll(gen.row([
      PosColumn(text: 'Tgl', width: 3),
      PosColumn(text: tanggal, width: 9),
    ]));
    if (customer != null) {
      out.addAll(gen.row([
        PosColumn(text: 'Cust', width: 3),
        PosColumn(text: customer.name, width: 9),
      ]));
    } else if (tx.customerName != null) {
      out.addAll(gen.row([
        PosColumn(text: 'Cust', width: 3),
        PosColumn(text: tx.customerName!, width: 9),
      ]));
    }
    out.addAll(gen.hr());

    // Item
    for (final item in items) {
      final pName = productNames[item.productId] ?? 'Produk';
      final uName = unitNames[item.productUnitId] ?? '';
      out.addAll(gen.text('$pName ($uName)',
          styles: const PosStyles(), linesAfter: 0));
      final qtyStr = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();
      out.addAll(gen.row([
        PosColumn(
            text: '  $qtyStr x ${_fmtRp(item.priceAtSale)}',
            width: 8),
        PosColumn(
            text: _fmtRp(item.subtotal),
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]));
      if (item.itemNote != null && item.itemNote!.isNotEmpty) {
        out.addAll(gen.text('  * ${item.itemNote}',
            styles: const PosStyles(fontType: PosFontType.fontB)));
      }
    }
    out.addAll(gen.hr());

    // Total
    out.addAll(gen.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(
          text: _fmtRp(tx.total),
          width: 6,
          styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]));
    out.addAll(gen.row([
      PosColumn(text: 'Bayar', width: 6),
      PosColumn(
          text: _fmtRp(tx.paid),
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]));
    if (tx.changeAmount > 0) {
      out.addAll(gen.row([
        PosColumn(text: 'Kembali', width: 6),
        PosColumn(
            text: _fmtRp(tx.changeAmount),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]));
    }
    if (tx.status == 'kurang_bayar' || tx.status == 'tempo') {
      final remaining = tx.total - tx.paid;
      out.addAll(gen.row([
        PosColumn(text: 'Sisa', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(
            text: _fmtRp(remaining),
            width: 6,
            styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]));
    }

    if (strukNote != null && strukNote.isNotEmpty) {
      out.addAll(gen.hr());
      out.addAll(gen.text(strukNote, styles: const PosStyles(align: PosAlign.center)));
    }

    out.addAll(gen.feed(3));
    out.addAll(gen.cut());
    return Uint8List.fromList(out);
  }

  static String _fmtRp(int amount) {
    final s = amount.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return 'Rp${amount < 0 ? '-' : ''}$buf';
  }

  static String _fmtDateTime(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.day)}/${p(dt.month)}/${dt.year} ${p(dt.hour)}:${p(dt.minute)}';
  }
}
