import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// Pengaturan format nota yang disimpan di SharedPreferences.
class PrinterSettings {
  const PrinterSettings({
    this.paperSize = '58',
    this.showDateHeader = true,
    this.showTxNumber = true,
    this.showCustomer = true,
    this.showProductCount = true,
    this.showPaymentDetail = true,
    this.showStatusText = true,
  });

  final String paperSize;       // '58' | '80'
  final bool showDateHeader;    // baris tanggal berdiri sendiri sebelum separator
  final bool showTxNumber;      // "#localId" di baris datetime
  final bool showCustomer;      // nama pelanggan
  final bool showProductCount;  // "Produk: N"
  final bool showPaymentDetail; // baris Bayar + Kembali/Kurang
  final bool showStatusText;    // "Sudah bayar" / "Kurang bayar" dll

  int get charWidth => paperSize == '80' ? 42 : 32;

  PrinterSettings copyWith({
    String? paperSize,
    bool? showDateHeader,
    bool? showTxNumber,
    bool? showCustomer,
    bool? showProductCount,
    bool? showPaymentDetail,
    bool? showStatusText,
  }) =>
      PrinterSettings(
        paperSize: paperSize ?? this.paperSize,
        showDateHeader: showDateHeader ?? this.showDateHeader,
        showTxNumber: showTxNumber ?? this.showTxNumber,
        showCustomer: showCustomer ?? this.showCustomer,
        showProductCount: showProductCount ?? this.showProductCount,
        showPaymentDetail: showPaymentDetail ?? this.showPaymentDetail,
        showStatusText: showStatusText ?? this.showStatusText,
      );
}

class PrinterService {
  PrinterService._();

  static const _channel = MethodChannel('com.thepos/bt_print');
  static const _prefMac = 'printer_mac';

  // ── Preferensi ───────────────────────────────────────────────────────────

  static Future<String?> getSavedMac() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefMac);
  }

  static Future<void> saveMac(String mac) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMac, mac);
  }

  static Future<PrinterSettings> loadSettings() async {
    final p = await SharedPreferences.getInstance();
    return PrinterSettings(
      paperSize: p.getString('printer_paper_size') ?? '58',
      showDateHeader: p.getBool('printer_show_date_header') ?? true,
      showTxNumber: p.getBool('printer_show_tx_number') ?? true,
      showCustomer: p.getBool('printer_show_customer') ?? true,
      showProductCount: p.getBool('printer_show_product_count') ?? true,
      showPaymentDetail: p.getBool('printer_show_payment_detail') ?? true,
      showStatusText: p.getBool('printer_show_status_text') ?? true,
    );
  }

  static Future<void> saveSettings(PrinterSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('printer_paper_size', s.paperSize);
    await p.setBool('printer_show_date_header', s.showDateHeader);
    await p.setBool('printer_show_tx_number', s.showTxNumber);
    await p.setBool('printer_show_customer', s.showCustomer);
    await p.setBool('printer_show_product_count', s.showProductCount);
    await p.setBool('printer_show_payment_detail', s.showPaymentDetail);
    await p.setBool('printer_show_status_text', s.showStatusText);
  }

  // ── Bluetooth helpers ────────────────────────────────────────────────────

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

  // ── Koneksi (native channel) ─────────────────────────────────────────────

  static Future<bool> connect(String mac) async {
    try {
      if (await isConnected) return true;
    } catch (_) {}
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final res = await _channel.invokeMapMethod<String, dynamic>(
          'connect', {'mac': mac},
        ).timeout(const Duration(seconds: 12), onTimeout: () => null);
        final ok = res?['ok'] as bool? ?? false;
        if (ok) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          return true;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }

  static Future<bool> get isConnected async {
    try {
      return await _channel
              .invokeMethod<bool>('status')
              .timeout(const Duration(seconds: 4), onTimeout: () => false) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> disconnect() async {
    try {
      await _channel
          .invokeMethod<void>('disconnect')
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
    return true;
  }

  // ── Test print dengan log detail ─────────────────────────────────────────

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
      final found =
          paired.any((d) => d.macAdress.toUpperCase() == mac.toUpperCase());
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
        wasConnected = await _channel
                .invokeMethod<bool>('status')
                .timeout(const Duration(seconds: 4), onTimeout: () => false) ??
            false;
      } catch (e) {
        add('status exception', ok: false, detail: '$e');
      }
      add('Status sebelumnya',
          detail: wasConnected ? 'terhubung' : 'terputus');

      if (wasConnected) {
        add('Putuskan koneksi lama sebelum reconnect…');
        try {
          await _channel
              .invokeMethod<void>('disconnect')
              .timeout(const Duration(seconds: 4));
          add('Disconnect', ok: true);
        } catch (e) {
          add('Disconnect exception', ok: false, detail: '$e');
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }

      // ── 5. Koneksi ───────────────────────────────────────────────────────
      bool connected = false;
      String? connectErr;
      for (var i = 1; i <= 3; i++) {
        add('Percobaan koneksi $i/3 ke $mac…');
        try {
          final res = await _channel.invokeMapMethod<String, dynamic>(
            'connect', {'mac': mac},
          ).timeout(const Duration(seconds: 12), onTimeout: () {
            add('Percobaan $i timeout (12 dtk)', ok: false);
            return null;
          });
          connected = res?['ok'] as bool? ?? false;
          connectErr = res?['err'] as String?;
        } catch (e) {
          add('Percobaan $i exception', ok: false, detail: '$e');
          connected = false;
          connectErr = '$e';
        }
        add('Hasil percobaan $i', ok: connected,
            detail: connected ? null : connectErr);
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
        connStatus = await _channel
                .invokeMethod<bool>('status')
                .timeout(const Duration(seconds: 4), onTimeout: () => false) ??
            false;
      } catch (e) {
        add('Verifikasi exception', ok: false, detail: '$e');
      }
      add('Status terverifikasi', ok: connStatus);

      // ── 6b. Stabilisasi RFCOMM ───────────────────────────────────────────
      add('Tunggu 600ms stabilisasi RFCOMM output stream…');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      add('Kirim warm-up ESC @ (init printer)…');
      try {
        final warmup = Uint8List.fromList([0x1B, 0x40]);
        final wRes = await _channel.invokeMapMethod<String, dynamic>(
          'write', {'bytes': warmup},
        ).timeout(const Duration(seconds: 4), onTimeout: () => null);
        final wOk = wRes?['ok'] as bool? ?? false;
        final wErr = wRes?['err'] as String?;
        add('Warm-up write', ok: wOk,
            detail: wOk ? 'stream siap' : (wErr ?? 'belum siap'));
        if (!wOk) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final wRes2 = await _channel.invokeMapMethod<String, dynamic>(
            'write', {'bytes': warmup},
          ).timeout(const Duration(seconds: 4), onTimeout: () => null);
          final wOk2 = wRes2?['ok'] as bool? ?? false;
          final wErr2 = wRes2?['err'] as String?;
          add('Warm-up write retry', ok: wOk2,
              detail: wOk2 ? null : (wErr2 ?? 'masih gagal'));
          if (!wOk2) {
            add('Stream tidak bisa ditulis. '
                'Error: ${wErr2 ?? wErr ?? "tidak diketahui"}',
                ok: false);
            return (false, log);
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        add('Warm-up exception', ok: false, detail: '$e');
      }

      // ── 7. Build ESC/POS bytes ───────────────────────────────────────────
      add('Membangun data ESC/POS…');
      Uint8List bytes;
      try {
        final settings = await loadSettings();
        final profile = await CapabilityProfile.load();
        final paperSize =
            settings.paperSize == '80' ? PaperSize.mm80 : PaperSize.mm58;
        final gen = Generator(paperSize, profile);
        final w = settings.charWidth;
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
          ...gen.text(_sep(w)),
          ...gen.text(_fmtDateTimeFull(now),
              styles: const PosStyles(align: PosAlign.center)),
          ...gen.text(_sep(w)),
          ...gen.feed(3),
          ...gen.cut(),
        ]);
        add('Data ESC/POS siap', ok: true, detail: '${bytes.length} bytes');
      } catch (e) {
        add('Build ESC/POS exception', ok: false, detail: '$e');
        return (false, log);
      }

      // ── 8. Kirim data ────────────────────────────────────────────────────
      add('Mengirim ${bytes.length} bytes ke printer…');
      bool writeOk = false;
      try {
        final writeRes = await _channel.invokeMapMethod<String, dynamic>(
          'write', {'bytes': bytes},
        ).timeout(const Duration(seconds: 10), onTimeout: () {
          add('Write timeout (10 dtk)', ok: false);
          return null;
        });
        writeOk = writeRes?['ok'] as bool? ?? false;
        final writeErr = writeRes?['err'] as String?;
        add('Kirim data', ok: writeOk,
            detail: writeOk
                ? '${bytes.length} bytes terkirim'
                : (writeErr ?? 'tidak ada detail'));
        if (!writeOk && writeErr != null) {
          add('Error detail: $writeErr', ok: false);
        }
      } catch (e) {
        add('Write exception', ok: false, detail: '$e');
        return (false, log);
      }

      if (writeOk) {
        add('Test print BERHASIL — kertas harus keluar dari printer.',
            ok: true);
      } else {
        add('Data tidak terkirim — lihat error detail di atas.', ok: false);
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

    final settings = await loadSettings();
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
      settings: settings,
    );

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'write', {'bytes': bytes},
      ).timeout(const Duration(seconds: 10), onTimeout: () => null);
      return res?['ok'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Item ordering helpers ────────────────────────────────────────────────

  static TransactionItem? _parentItemOf(TransactionItem item,
      List<TransactionItem> items, Map<String, String?> parentOf) {
    final pid = parentOf[item.productId];
    if (pid == null) return null;
    for (final it in items) {
      if (it.productId == pid && parentOf[it.productId] == null) return it;
    }
    return null;
  }

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

  // ── Build ESC/POS bytes ──────────────────────────────────────────────────

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
    required PrinterSettings settings,
  }) async {
    final w = settings.charWidth;
    final profile = await CapabilityProfile.load();
    final paperSize =
        settings.paperSize == '80' ? PaperSize.mm80 : PaperSize.mm58;
    final gen = Generator(paperSize, profile);
    final out = <int>[];

    // ── Header toko ──────────────────────────────────────────────────────────
    if (storeName.isNotEmpty) {
      out.addAll(gen.text(
        _toAscii(storeName),
        styles: const PosStyles(
            bold: true,
            align: PosAlign.center,
            height: PosTextSize.size2,
            width: PosTextSize.size2),
      ));
    }
    if (storeAddress.isNotEmpty) {
      out.addAll(gen.text(_toAscii(storeAddress),
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (storePhone.isNotEmpty) {
      out.addAll(gen.text('Telp: ${_toAscii(storePhone)}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    out.addAll(gen.text(_sep(w)));

    // ── Baris tanggal ─────────────────────────────────────────────────────
    if (settings.showDateHeader) {
      out.addAll(gen.text(_fmtDate(tx.createdAt)));
    }
    out.addAll(gen.text(_sep(w)));

    // ── Info transaksi ────────────────────────────────────────────────────
    final dtStr = _fmtDateTimeFull(tx.createdAt);
    if (settings.showTxNumber) {
      out.addAll(gen.text(_rowLR(dtStr, '#${tx.localId}', w)));
    } else {
      out.addAll(gen.text(dtStr));
    }

    if (settings.showCustomer) {
      final custName = customer?.name ?? tx.customerName;
      if (custName != null && custName.isNotEmpty) {
        out.addAll(gen.text(_toAscii(custName)));
      }
    }
    out.addAll(gen.text(_sep(w)));

    // ── Item ─────────────────────────────────────────────────────────────
    int productCount = 0;
    for (final item in _orderItems(items, parentOf)) {
      final isVar = _parentItemOf(item, items, parentOf) != null;
      if (!isVar) productCount++;

      final rawName = _toAscii(productNames[item.productId] ?? 'Produk');
      final marked = checkedIds.contains(item.id) ? '[v] $rawName' : rawName;
      final prefix = isVar ? '  > ' : '';
      out.addAll(gen.text('$prefix$marked'));

      if (item.itemNote != null && item.itemNote!.isNotEmpty) {
        out.addAll(gen.text(_toAscii(item.itemNote!)));
      }

      final uName = _toAscii(unitNames[item.productUnitId] ?? 'pcs');
      final qtyStr = item.qty % 1 == 0
          ? item.qty.toInt().toString()
          : item.qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
      final qtyLine = '  $qtyStr $uName x ${_fmtNum(item.priceAtSale)}';
      out.addAll(gen.text(_rowLR(qtyLine, _fmtNum(item.subtotal), w)));
    }
    out.addAll(gen.text(_sep(w)));

    // ── Jumlah produk ─────────────────────────────────────────────────────
    if (settings.showProductCount) {
      out.addAll(gen.text('Produk: $productCount'));
      out.addAll(gen.text(_sep(w)));
    }

    // ── Total ─────────────────────────────────────────────────────────────
    out.addAll(gen.text(
        _rowLR('Total', 'Rp ${_fmtNum(tx.total)}', w),
        styles: const PosStyles(bold: true)));

    if (settings.showPaymentDetail) {
      out.addAll(gen.text(_rowLR('  Bayar..', 'Rp ${_fmtNum(tx.paid)}', w)));

      if (tx.changeAmount > 0) {
        out.addAll(gen.text(
            _rowLR('Kembali', 'Rp ${_fmtNum(tx.changeAmount)}', w)));
      } else if (tx.status == 'kurang_bayar' || tx.status == 'tempo') {
        final remaining = tx.total - tx.paid;
        out.addAll(gen.text(
            _rowLR('Kurang', 'Rp ${_fmtNum(remaining)}', w)));
      }
    }

    if (settings.showStatusText) {
      out.addAll(gen.text(_rowLR('', _statusLabel(tx), w)));
    }

    // ── Footer ────────────────────────────────────────────────────────────
    if (strukNote != null && strukNote.isNotEmpty) {
      out.addAll(gen.text(_sep(w)));
      out.addAll(gen.text(_toAscii(strukNote),
          styles: const PosStyles(align: PosAlign.center)));
    }

    out.addAll(gen.feed(3));
    out.addAll(gen.cut());
    return Uint8List.fromList(out);
  }

  // ── Format helpers ───────────────────────────────────────────────────────

  static String _sep(int width) => '-' * width;

  static String _rowLR(String left, String right, int width) {
    final space = width - left.length - right.length;
    if (space <= 0) return '$left $right';
    return '$left${' ' * space}$right';
  }

  static String _fmtNum(int amount) {
    final s = amount.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return amount < 0 ? '-$buf' : '$buf';
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  static String _fmtDate(DateTime dt) =>
      '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

  static String _fmtDateTimeFull(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year} $hh:$mm';
  }

  static String _statusLabel(Transaction tx) {
    switch (tx.status) {
      case 'lunas':
        return tx.changeAmount > 0 ? 'Sudah bayar' : 'Lunas';
      case 'kurang_bayar':
        return 'Kurang bayar';
      case 'tempo':
        return 'Bayar tempo';
      case 'void':
        return 'DIBATALKAN';
      default:
        return tx.status;
    }
  }

  // ── ASCII sanitizer ──────────────────────────────────────────────────────

  static String _toAscii(String s) {
    const map = {
      '—': '-', '–': '-',
      '‘': "'", '’': "'",
      '“': '"', '”': '"',
      '…': '...', '×': 'x', '·': '.',
      '«': '"', '»': '"', '•': '*',
      '❤': '<3', '°': 'deg',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'í': 'i', 'î': 'i', 'ï': 'i',
      'É': 'E', 'È': 'E', 'Ê': 'E',
      'À': 'A', 'Â': 'A', 'Ä': 'A',
      'Ó': 'O', 'Ô': 'O', 'Ö': 'O',
      'Ú': 'U', 'Û': 'U', 'Ü': 'U',
      'ñ': 'n', 'Ñ': 'N',
      'ç': 'c', 'Ç': 'C',
    };
    final buf = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final mapped = map[ch];
      if (mapped != null) {
        buf.write(mapped);
      } else if (rune >= 0x20 && rune <= 0x7E) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }
}
