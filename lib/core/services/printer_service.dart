import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';

/// Satu baris dalam log debug koneksi printer.
class PrintLogEntry {
  PrintLogEntry(this.step, {this.ok, this.detail})
      : time = DateTime.now();

  final DateTime time;
  final String step;
  final bool? ok; // null = info, true = sukses, false = gagal
  final String? detail;

  String get timeStr {
    final t = time;
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${p(t.hour)}:${p(t.minute)}:${p(t.second)}.${p(t.millisecond, 3)}';
  }

  @override
  String toString() =>
      '[$timeStr] $step${ok == null ? '' : ok! ? ' ✓' : ' ✗'}'
      '${detail != null ? ': $detail' : ''}';
}

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

  static Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    final connect = statuses[Permission.bluetoothConnect];
    return connect == null || connect.isGranted || connect.isLimited;
  }

  static Future<bool> hasPermissions() async {
    final connect = await Permission.bluetoothConnect.status;
    return connect.isGranted || connect.isLimited;
  }

  static Future<bool> isBluetoothOn() => PrintBluetoothThermal.bluetoothEnabled
      .timeout(const Duration(seconds: 6), onTimeout: () => false);

  static Future<List<BluetoothInfo>> getPairedDevices() async =>
      PrintBluetoothThermal.pairedBluetooths.timeout(
        const Duration(seconds: 8),
        onTimeout: () => <BluetoothInfo>[],
      );

  static Future<bool> connect(String mac) async {
    try {
      if (await isConnected) return true;
    } catch (_) {}
    for (var attempt = 0; attempt < 3; attempt++) {
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);
      if (ok) return true;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }

  static Future<bool> get isConnected async =>
      PrintBluetoothThermal.connectionStatus
          .timeout(const Duration(seconds: 6), onTimeout: () => false);

  static Future<bool> disconnect() async =>
      PrintBluetoothThermal.disconnect;

  // ── Test print dengan log detail ─────────────────────────────────────────

  /// Test print sambil mengumpulkan log setiap langkah.
  /// Cocok untuk tombol debug; mengembalikan (sukses, log).
  static Future<(bool, List<PrintLogEntry>)> testPrintDetailed(
      String mac) async {
    final log = <PrintLogEntry>[];
    void add(String step, {bool? ok, String? detail}) {
      final e = PrintLogEntry(step, ok: ok, detail: detail);
      log.add(e);
      debugPrint(e.toString());
    }

    try {
      // ── 1. Izin ──────────────────────────────────────────────────────────
      add('Cek izin BLUETOOTH_CONNECT…');
      bool perm;
      try {
        perm = await hasPermissions();
      } catch (e) {
        add('Cek izin exception', ok: false, detail: '$e');
        return (false, log);
      }
      add('Izin BLUETOOTH_CONNECT', ok: perm);
      if (!perm) {
        add('Izin ditolak — buka Pengaturan Aplikasi lalu berikan izin.',
            ok: false);
        return (false, log);
      }

      // ── 2. Bluetooth aktif ───────────────────────────────────────────────
      add('Cek Bluetooth aktif…');
      bool btOn;
      try {
        btOn = await isBluetoothOn();
      } catch (e) {
        add('Cek BT exception', ok: false, detail: '$e');
        return (false, log);
      }
      add('Bluetooth aktif', ok: btOn);
      if (!btOn) {
        add('Aktifkan Bluetooth, lalu coba lagi.', ok: false);
        return (false, log);
      }

      // ── 3. Perangkat ada di daftar paired ────────────────────────────────
      add('Cari "$mac" di daftar perangkat terpasang…');
      List<BluetoothInfo> paired;
      try {
        paired = await getPairedDevices();
      } catch (e) {
        add('getPairedDevices exception', ok: false, detail: '$e');
        paired = [];
      }
      add('Perangkat terpasang ditemukan: ${paired.length}',
          detail: paired.map((d) => '${d.name}(${d.macAdress})').join(', '));
      final found = paired.any(
          (d) => d.macAdress.toUpperCase() == mac.toUpperCase());
      add('Printer "$mac" ada di daftar', ok: found);
      if (!found) {
        add('Printer tidak ditemukan di daftar paired. '
            'Lakukan pairing ulang di Pengaturan Bluetooth HP.',
            ok: false);
      }

      // ── 4. Disconnect jika sedang terhubung ─────────────────────────────
      add('Cek status koneksi sebelumnya…');
      bool wasConnected = false;
      try {
        wasConnected = await PrintBluetoothThermal.connectionStatus
            .timeout(const Duration(seconds: 4), onTimeout: () => false);
      } catch (e) {
        add('connectionStatus exception', ok: false, detail: '$e');
      }
      add('Status sebelumnya', detail: wasConnected ? 'terhubung' : 'terputus');

      if (wasConnected) {
        add('Putuskan koneksi lama sebelum reconnect…');
        try {
          await PrintBluetoothThermal.disconnect
              .timeout(const Duration(seconds: 4));
          add('Disconnect', ok: true);
        } catch (e) {
          add('Disconnect exception', ok: false, detail: '$e');
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }

      // ── 5. Koneksi ───────────────────────────────────────────────────────
      bool connected = false;
      for (var i = 1; i <= 3; i++) {
        add('Percobaan koneksi $i/3 ke $mac…');
        try {
          connected = await PrintBluetoothThermal.connect(
                  macPrinterAddress: mac)
              .timeout(const Duration(seconds: 12), onTimeout: () {
            add('Percobaan $i timeout (12 dtk)', ok: false);
            return false;
          });
        } catch (e) {
          add('Percobaan $i exception', ok: false, detail: '$e');
          connected = false;
        }
        add('Hasil percobaan $i', ok: connected);
        if (connected) break;
        if (i < 3) {
          add('Tunggu 800ms sebelum percobaan berikutnya…');
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }

      if (!connected) {
        add('Gagal terhubung setelah 3 percobaan.', ok: false);
        add('Tips: pastikan printer menyala, dalam jangkauan, '
            'dan sudah dipasangkan di Pengaturan Bluetooth HP.',
            ok: false);
        return (false, log);
      }

      // ── 6. Verifikasi status ─────────────────────────────────────────────
      add('Verifikasi status koneksi setelah connect…');
      bool connStatus = false;
      try {
        connStatus = await PrintBluetoothThermal.connectionStatus
            .timeout(const Duration(seconds: 4), onTimeout: () => false);
      } catch (e) {
        add('Verifikasi exception', ok: false, detail: '$e');
      }
      add('Status terverifikasi', ok: connStatus);

      // ── 7. Build ESC/POS bytes ───────────────────────────────────────────
      add('Membangun data ESC/POS…');
      Uint8List bytes;
      try {
        final profile = await CapabilityProfile.load();
        final gen = Generator(PaperSize.mm58, profile);
        final now = DateTime.now();
        bytes = Uint8List.fromList(<int>[
          ...gen.text('TEST PRINT',
              styles: const PosStyles(
                  bold: true,
                  align: PosAlign.center,
                  height: PosTextSize.size2,
                  width: PosTextSize.size2)),
          ...gen.text('The-POS - Printer OK',
              styles: const PosStyles(align: PosAlign.center)),
          ...gen.text(
              '${now.day}/${now.month}/${now.year} '
              '${now.hour}:${now.minute.toString().padLeft(2, '0')}',
              styles: const PosStyles(align: PosAlign.center)),
          ...gen.feed(3),
          ...gen.cut(),
        ]);
        add('Data ESC/POS siap', ok: true,
            detail: '${bytes.length} bytes');
      } catch (e) {
        add('Build ESC/POS exception', ok: false, detail: '$e');
        return (false, log);
      }

      // ── 8. Kirim data ────────────────────────────────────────────────────
      add('Mengirim ${bytes.length} bytes ke printer…');
      bool writeOk = false;
      try {
        writeOk = await PrintBluetoothThermal.writeBytes(bytes)
            .timeout(const Duration(seconds: 10), onTimeout: () {
          add('Write timeout (10 dtk)', ok: false);
          return false;
        });
      } catch (e) {
        add('Write exception', ok: false, detail: '$e');
        return (false, log);
      }
      add('Kirim data', ok: writeOk);

      if (writeOk) {
        add('Test print BERHASIL — kertas harus keluar dari printer.', ok: true);
      } else {
        add('writeBytes mengembalikan false — data tidak terkirim.', ok: false);
        add('Tips: coba matikan/nyalakan printer lalu test lagi.', ok: false);
      }
      return (writeOk, log);
    } catch (e, st) {
      log.add(PrintLogEntry('Error tak terduga', ok: false, detail: '$e\n$st'));
      debugPrint('PrinterService.testPrintDetailed error: $e\n$st');
      return (false, log);
    }
  }

  // ── Print struk ──────────────────────────────────────────────────────────

  static Future<bool> testPrint(String mac) async {
    final (ok, _) = await testPrintDetailed(mac);
    return ok;
  }

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
    Map<String, String?> parentOf = const {},
    Set<String> checkedIds = const {},
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
      parentOf: parentOf,
      checkedIds: checkedIds,
    );

    return PrintBluetoothThermal.writeBytes(bytes);
  }


  /// Item induk dari sebuah baris (null bila bukan varian / induk tak ada).
  static TransactionItem? _parentItemOf(
      TransactionItem item, List<TransactionItem> items,
      Map<String, String?> parentOf) {
    final pid = parentOf[item.productId];
    if (pid == null) return null;
    for (final it in items) {
      if (it.productId == pid && parentOf[it.productId] == null) return it;
    }
    return null;
  }

  /// Urutkan item: induk diikuti varian-variannya.
  static List<TransactionItem> _orderItems(
      List<TransactionItem> items, Map<String, String?> parentOf) {
    if (parentOf.isEmpty) return items;
    final out = <TransactionItem>[];
    for (final it in items) {
      if (_parentItemOf(it, items, parentOf) == null) {
        out.add(it);
        for (final c in items) {
          if (_parentItemOf(c, items, parentOf)?.id == it.id) out.add(c);
        }
      }
    }
    return out;
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
    Map<String, String?> parentOf = const {},
    Set<String> checkedIds = const {},
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);
    final out = <int>[];

    // Header toko — semua string di-sanitize ke ASCII agar tidak throw exception
    out.addAll(gen.text(
        _toAscii(storeName.isEmpty ? 'Toko' : storeName),
        styles: const PosStyles(bold: true, align: PosAlign.center, height: PosTextSize.size2, width: PosTextSize.size2)));
    if (storeAddress.isNotEmpty) {
      out.addAll(gen.text(_toAscii(storeAddress), styles: const PosStyles(align: PosAlign.center)));
    }
    if (storePhone.isNotEmpty) {
      out.addAll(gen.text('Telp: ${_toAscii(storePhone)}', styles: const PosStyles(align: PosAlign.center)));
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
        PosColumn(text: _toAscii(customer.name), width: 9),
      ]));
    } else if (tx.customerName != null) {
      out.addAll(gen.row([
        PosColumn(text: 'Cust', width: 3),
        PosColumn(text: _toAscii(tx.customerName!), width: 9),
      ]));
    }
    out.addAll(gen.hr());

    // Item (varian bersarang di bawah induk dengan indentasi)
    for (final item in _orderItems(items, parentOf)) {
      final isVar = _parentItemOf(item, items, parentOf) != null;
      final pad = isVar ? '  ' : '';
      final rawName = _toAscii(productNames[item.productId] ?? 'Produk');
      final marked = checkedIds.contains(item.id) ? '[v] $rawName' : rawName;
      final pName = isVar ? '$pad> $marked' : marked;
      final uName = _toAscii(unitNames[item.productUnitId] ?? '');
      out.addAll(gen.text('$pName ($uName)',
          styles: const PosStyles(), linesAfter: 0));
      final qtyStr = item.qty % 1 == 0 ? item.qty.toInt().toString() : item.qty.toString();
      out.addAll(gen.row([
        PosColumn(
            text: '$pad  $qtyStr x ${_fmtRp(item.priceAtSale)}',
            width: 8),
        PosColumn(
            text: _fmtRp(item.subtotal),
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]));
      if (item.itemNote != null && item.itemNote!.isNotEmpty) {
        out.addAll(gen.text('$pad  * ${_toAscii(item.itemNote!)}',
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
      out.addAll(gen.text(_toAscii(strukNote),
          styles: const PosStyles(align: PosAlign.center)));
    }

    out.addAll(gen.feed(3));
    out.addAll(gen.cut());
    return Uint8List.fromList(out);
  }

  /// Bersihkan string agar hanya berisi karakter yang bisa dicetak printer
  /// ESC/POS (ASCII 0x20–0x7E). Karakter non-ASCII umum dikonversi ke padanan
  /// ASCII; sisanya dihapus. Tanpa ini, gen.text() / gen.row() throw exception.
  static String _toAscii(String s) {
    final map = {
      '—': '-',  // em dash —
      '–': '-',  // en dash –
      '‘': "'",  // left single quote '
      '’': "'",  // right single quote '
      '“': '"',  // left double quote "
      '”': '"',  // right double quote "
      '…': '...', // ellipsis …
      '×': 'x',  // ×
      '·': '.',  // middle dot ·
      '«': '"',  // «
      '»': '"',  // »
      '•': '*',  // bullet •
      '❤': '<3', // ❤
      '°': 'deg',// °
      // Vowels with diacritics (e.g. café)
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'í': 'i', 'î': 'i', 'ï': 'i',
      'É': 'E', 'È': 'E', 'Ê': 'E',
      'À': 'A', 'Â': 'A', 'Ä': 'A',
      'Ó': 'O', 'Ô': 'O', 'Ö': 'O',
      'Ú': 'U', 'Û': 'U', 'Ü': 'U',
      'ñ': 'n', 'Ñ': 'N', // ñ Ñ
      'ç': 'c', 'Ç': 'C', // ç Ç
    };
    final buf = StringBuffer();
    // Iterasi per grapheme cluster via runes (menangani surrogate pair dgn benar)
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final mapped = map[ch];
      if (mapped != null) {
        buf.write(mapped);
      } else if (rune >= 0x20 && rune <= 0x7E) {
        buf.write(ch);
      }
      // karakter di luar range ASCII printable: dihapus (tidak error)
    }
    return buf.toString();
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
