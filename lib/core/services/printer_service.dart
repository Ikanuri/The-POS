import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';

/// Nomor urut nota saja, tanpa kode kasir & tanggal. localId berformat
/// "KASIR-YYYYMMDD-NNNN" → "5". Defensif untuk data lama tanpa format.
String shortTxNo(String localId) {
  final parts = localId.split('-');
  final seq = parts.length >= 2 ? parts.last : localId;
  final trimmed = seq.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return trimmed.isEmpty ? seq : trimmed;
}

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
      log.add(PrintLogEntry(step, ok: ok, detail: detail));
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
      return (false, log);
    }
  }

  // ── Print struk ──────────────────────────────────────────────────────────

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
    String employeeName = '',
    List<TransactionPayment> payments = const [],
    String storeWhatsapp = '',
    String storeTelegram = '',
    String receiptHeader = '',
    String receiptFooter = '',
    Map<String, String?> parentOf = const {},
  }) async {
    final mac = await getSavedMac();
    if (mac == null || mac.isEmpty) return false;

    final connected = await connect(mac);
    if (!connected) return false;

    final settings = await loadSettings();
    final bytes = await _buildBytes(
      tx: tx,
      items: items,
      payments: payments,
      productNames: productNames,
      unitNames: unitNames,
      customer: customer,
      employeeName: employeeName,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      storeWhatsapp: storeWhatsapp,
      storeTelegram: storeTelegram,
      receiptHeader: receiptHeader,
      receiptFooter: receiptFooter,
      strukNote: strukNote,
      parentOf: parentOf,
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
    String employeeName = '',
    List<TransactionPayment> payments = const [],
    String storeWhatsapp = '',
    String storeTelegram = '',
    String receiptHeader = '',
    String receiptFooter = '',
    Map<String, String?> parentOf = const {},
    required PrinterSettings settings,
  }) async {
    final w = settings.charWidth;
    final profile = await CapabilityProfile.load();
    final paperSize =
        settings.paperSize == '80' ? PaperSize.mm80 : PaperSize.mm58;
    final gen = Generator(paperSize, profile);
    final out = <int>[];

    // Margin kecil kiri-kanan agar isi struk sedikit lebih ke tengah (tidak
    // menempel di tepi kiri kertas). [innerW] dipakai untuk perhitungan kolom
    // kiri-kanan supaya angka di kanan tidak melewati tepi kertas.
    final margin = w >= 42 ? 2 : 1;
    final innerW = w - margin * 2;
    final pad = ' ' * margin;
    List<int> bodyText(String s, {PosStyles styles = const PosStyles()}) =>
        gen.text('$pad$s', styles: styles);
    List<int> bodyLR(String l, String r,
            {PosStyles styles = const PosStyles()}) =>
        gen.text('$pad${_rowLR(l, r, innerW)}', styles: styles);
    List<int> bodySep() => gen.text('$pad${'-' * innerW}');

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
      // Sedikit jarak setelah nama toko (mirip jarak antar baris kontak).
      out.addAll(gen.feed(1));
    }
    if (storeAddress.isNotEmpty) {
      out.addAll(gen.text(_toAscii(storeAddress),
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (storePhone.isNotEmpty) {
      out.addAll(gen.text('Telp: ${_toAscii(storePhone)}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (storeWhatsapp.isNotEmpty) {
      out.addAll(gen.text('WA: ${_toAscii(storeWhatsapp)}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (storeTelegram.isNotEmpty) {
      out.addAll(gen.text('Telegram: ${_toAscii(storeTelegram)}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    // Teks header bebas (bisa multi-baris).
    if (receiptHeader.isNotEmpty) {
      for (final line in receiptHeader.split('\n')) {
        out.addAll(gen.text(_toAscii(line),
            styles: const PosStyles(align: PosAlign.center)));
      }
    }
    out.addAll(bodySep());

    // ── Info transaksi: tanggal + jam | nomor nota ────────────────────────
    // Jam tampil di sebelah tanggal. Kode transaksi cukup nomor urut nota
    // (kode kasir & tanggal tidak diulang di sini).
    final dtStr = _fmtDateTimeFull(tx.createdAt);
    if (settings.showTxNumber) {
      out.addAll(bodyLR(dtStr, '#${shortTxNo(tx.localId)}'));
    } else {
      out.addAll(bodyText(dtStr));
    }

    if (settings.showCustomer) {
      final custName = customer?.name ?? tx.customerName;
      if (custName != null && custName.isNotEmpty) {
        // Nama pelanggan: tebal & melebar (double-width) agar menonjol.
        out.addAll(bodyText(_toAscii(custName),
            styles: const PosStyles(bold: true, width: PosTextSize.size2)));
        // Alamat (bila pelanggan terdaftar) di bawah nama, teks biasa.
        final addr = customer?.address;
        if (addr != null && addr.trim().isNotEmpty) {
          out.addAll(bodyText(_toAscii(addr.trim())));
        }
      }
    }
    out.addAll(bodySep());

    // ── Item ─────────────────────────────────────────────────────────────
    int productCount = 0;
    String? lastBatch;
    String? lastRetur;
    for (final item in _orderItems(items, parentOf)) {
      final isVar = _parentItemOf(item, items, parentOf) != null;
      if (!isVar) productCount++;

      // Pembatas batch "Tambah Belanjaan" (Gaya A): "----- Tambahan HH:MM
      // -----" rata tengah, sebelum barang susulan. Hanya utk item induk;
      // varian ikut batch induknya.
      if (!isVar && item.addedAt != null) {
        final a = item.addedAt!;
        final hhmm =
            '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}';
        if (hhmm != lastBatch) {
          lastBatch = hhmm;
          final label = '----- Tambahan $hhmm -----';
          final left = label.length >= innerW ? 0 : (innerW - label.length) ~/ 2;
          out.addAll(bodyText('${' ' * left}$label'));
        }
      }
      // Item 49g — pembatas "----- Retur HH:MM -----" sebelum baris retur
      // nota lunas (qty negatif, item ASLI di atasnya tetap utuh).
      if (!isVar && item.returnedAt != null) {
        final r = item.returnedAt!;
        final hhmm =
            '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}';
        if (hhmm != lastRetur) {
          lastRetur = hhmm;
          final label = '----- Retur $hhmm -----';
          final left = label.length >= innerW ? 0 : (innerW - label.length) ~/ 2;
          out.addAll(bodyText('${' ' * left}$label'));
        }
      }

      final rawName = _toAscii(productNames[item.productId] ?? 'Produk');
      final prefix = isVar ? '  > ' : '';
      out.addAll(bodyText('$prefix$rawName',
          styles: const PosStyles(bold: true)));

      if (item.itemNote != null && item.itemNote!.isNotEmpty) {
        // Item 49c — catatan barang bisa multi-baris (maxLines:2 di UI);
        // split dulu supaya tiap baris tercetak sendiri (`_toAscii` buang
        // karakter \n mentah, jadi kalau digabung sebelum split baris-baris
        // itu akan nyambung jadi satu teks tanpa pemisah).
        for (final line in item.itemNote!.split('\n')) {
          out.addAll(bodyText(_toAscii(line)));
        }
      }

      final uName = _toAscii(unitNames[item.productUnitId] ?? 'pcs');
      final qtyStr = item.qty % 1 == 0
          ? item.qty.toInt().toString()
          : item.qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
      final qtyLine = '  $qtyStr $uName x ${_fmtNum(item.priceAtSale)}';
      out.addAll(bodyLR(qtyLine, _fmtNum(item.subtotal)));
    }
    out.addAll(bodySep());

    // ── Pegawai (di atas jumlah produk) ───────────────────────────────────
    // "Pegawai:" normal, nama bold. Pakai gen.row agar bisa beda gaya dalam
    // satu baris (kosong bila tidak diinput → tidak tampil apa pun).
    final empName = employeeName.trim();
    if (empName.isNotEmpty) {
      out.addAll(gen.row([
        PosColumn(text: 'Pegawai:', width: 3),
        PosColumn(
            text: ' ${_toAscii(empName)}',
            width: 9,
            styles: const PosStyles(bold: true)),
      ]));
    }

    // ── Jumlah produk ─────────────────────────────────────────────────────
    // Bug nyata dilaporkan user (foto struk cetak): baris ini dulu pakai
    // bodyText polos (teks 1 baris, angka nempel langsung setelah label)
    // — TIDAK sejajar dgn baris "Pegawai:" di atasnya yang pakai gen.row
    // 2-kolom (width 3+9). Samakan pola kolomnya supaya kedua value
    // sejajar di posisi yang sama.
    if (settings.showProductCount) {
      out.addAll(gen.row([
        PosColumn(text: 'Produk:', width: 3),
        PosColumn(text: ' $productCount', width: 9),
      ]));
    }
    if (empName.isNotEmpty || settings.showProductCount) {
      out.addAll(bodySep());
    }

    // ── Total ─────────────────────────────────────────────────────────────
    // Helper: nominal bold + double-width, right-aligned within body margin.
    final maxCharsWide = w ~/ 2 - margin;
    List<int> wideNominal(String text) {
      final lp = maxCharsWide - text.length;
      final padded = lp > 0 ? '${' ' * lp}$text' : text;
      return bodyText(padded,
          styles: const PosStyles(bold: true, width: PosTextSize.size2));
    }

    // Item 49g — nota yg PERNAH diretur pakai footer breakdown, pengecualian
    // yg disengaja dari pola 3-baris biasa (Item 49b).
    final hasRetur = items.any((i) => i.returnedAt != null);
    if (hasRetur) {
      final totalAwal =
          items.where((i) => i.qty > 0).fold<int>(0, (s, i) => s + i.subtotal);
      final returAmount = -items
          .where((i) => i.qty < 0)
          .fold<int>(0, (s, i) => s + i.subtotal);
      out.addAll(bodyLR('Total awal', 'Rp ${_fmtNum(totalAwal)}'));
      out.addAll(bodyLR('Retur', '- Rp ${_fmtNum(returAmount)}'));
      out.addAll(bodyText('Total akhir', styles: const PosStyles(bold: true)));
      out.addAll(wideNominal('Rp ${_fmtNum(tx.total)}'));
    } else {
      out.addAll(bodyText('Total', styles: const PosStyles(bold: true)));
      out.addAll(wideNominal('Rp ${_fmtNum(tx.total)}'));
    }

    if (settings.showPaymentDetail) {
      // `tx.paid`/`tx.changeAmount` mentah bisa SALAH kalau kembalian yang
      // sudah pernah diberikan dipakai ulang sbg pembayaran baru (mis. tambah
      // belanjaan) — uang yang sama ke-hitung dobel di `paid` tanpa pernah
      // dikurangi saat keluar sbg kembalian sebelumnya (akar masalah sama
      // dgn Item 23, sudah diperbaiki di `receipt_screen.dart`/nota gabungan,
      // sekarang dikonsistenkan ke struk cetak tunggal). "Kembali" HARUS
      // dari pembayaran TERAKHIR saja (bukan akumulasi seluruh riwayat nota).
      final sumChangeGiven =
          payments.where((p) => !p.voided).fold<int>(0, (s, p) => s + p.changeGiven);
      final netPaid = tx.paid - sumChangeGiven;

      TransactionPayment? latestWithChange;
      for (final p in payments) {
        if (p.voided || p.changeGiven <= 0) continue;
        if (latestWithChange == null ||
            p.paidAt.isAfter(latestWithChange.paidAt)) {
          latestWithChange = p;
        }
      }
      // "Bayar" HARUS Total + Kembalian (bukan netPaid mentah) saat ada
      // baris Kembalian — supaya "Total = Bayar - Kembalian" konsisten di
      // struk. netPaid dipakai HANYA saat tak ada kembalian (dipasangkan
      // dgn Sisa) — lihat dibayarDisplay() di receipt_screen.dart utk
      // penjelasan lengkap bug yg diperbaiki di sini.
      final bayar = latestWithChange != null
          ? tx.total + latestWithChange.changeGiven
          : (netPaid > 0 ? netPaid : 0);
      out.addAll(bodyLR('Bayar', 'Rp ${_fmtNum(bayar)}'));

      // Item 49b — ringkasan 3-baris (state akhir akumulatif): Total /
      // Bayar / Kembali-ATAU-Sisa. Baris "Uang Diterima" (uang tender
      // kotor, Item 9 lama) DIHAPUS — riwayat pembayaran (timeline di
      // bawah, bila ada) sudah simpan info itu.
      if (latestWithChange != null) {
        out.addAll(bodyText('Kembali', styles: const PosStyles(bold: true)));
        out.addAll(wideNominal('Rp ${_fmtNum(latestWithChange.changeGiven)}'));
      } else if (tx.status == 'kurang_bayar' || tx.status == 'tempo') {
        final remaining = tx.total - netPaid;
        out.addAll(bodyText('Sisa', styles: const PosStyles(bold: true)));
        out.addAll(wideNominal('Rp ${_fmtNum(remaining > 0 ? remaining : 0)}'));
      }

      if (hasRetur) {
        final refundTotal = -payments
            .where((p) => !p.voided && p.amount < 0)
            .fold<int>(0, (s, p) => s + p.amount);
        if (refundTotal > 0) {
          final refundMethod = payments
              .where((p) => !p.voided && p.amount < 0)
              .lastOrNull
              ?.method;
          out.addAll(bodyLR('Refund ${_methodShort(refundMethod ?? '')}',
              'Rp ${_fmtNum(refundTotal)}'));
        }
      }
    }

    if (settings.showStatusText) {
      out.addAll(bodyLR('', _statusLabel(tx)));
    }

    // ── Timeline pembayaran ───────────────────────────────────────────────
    // Sembunyikan hanya untuk tunai seketika (paidAt == createdAt persis).
    // Item 49f — baris audit-trail internal (method 'edit'/'retur', amount
    // selalu 0, dipakai returnUnpaidTransactionItems/editUnpaidTransactionItem
    // sbg jejak internal) BUKAN utk konsumsi pelanggan — _methodShort tak
    // kenal method itu shg tampil sbg string mentah "edit"/"retur" di struk
    // fisik. Difilter di sini (share pakai pola sama, in-app tetap tampilkan
    // semua).
    final visiblePayments =
        payments.where((p) => p.method != 'edit' && p.method != 'retur');
    final showTimeline = visiblePayments.length > 1 ||
        (visiblePayments.length == 1 &&
            visiblePayments.first.paidAt != tx.createdAt);
    if (showTimeline) {
      out.addAll(bodySep());
      out.addAll(bodyText('Pembayaran:', styles: const PosStyles(bold: true)));
      for (final p in visiblePayments) {
        final left = '${_fmtDateTimeFull(p.paidAt)} ${_methodShort(p.method)}';
        out.addAll(bodyLR(left, 'Rp ${_fmtNum(p.amount)}'));
      }
    }

    // ── Footer ────────────────────────────────────────────────────────────
    // Item 49c — catatan nota/toko bisa multi-baris (maxLines:3 di UI);
    // split per '\n' dulu (pola sama dgn receiptHeader di atas) supaya tiap
    // baris tercetak sendiri — `_toAscii` membuang karakter \n mentah.
    if (strukNote != null && strukNote.isNotEmpty) {
      out.addAll(bodySep());
      for (final line in strukNote.split('\n')) {
        out.addAll(gen.text(_toAscii(line),
            styles: const PosStyles(align: PosAlign.center)));
      }
    }
    // "Catatan di Struk" (Informasi Toko) — fallback ke "Terima kasih!" bila
    // belum diisi user, sama seperti hint field-nya & struk in-app/share.
    out.addAll(bodySep());
    final footerText =
        receiptFooter.isNotEmpty ? receiptFooter : 'Terima kasih!';
    for (final line in footerText.split('\n')) {
      out.addAll(gen.text(_toAscii(line),
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

  static String _methodShort(String m) {
    switch (m) {
      case 'tunai':
        return 'Tunai';
      case 'transfer':
        return 'Transfer';
      case 'qris':
        return 'QRIS';
      case 'ewallet':
        return 'E-Wallet';
      default:
        return m;
    }
  }

  // ── Print label produk (barcode) ───────────────────────────────────────────

  /// Cetak label 1 satuan/varian produk (nama, satuan+varian, harga,
  /// barcode) ke printer thermal yang sudah tersambung — reuse printer
  /// struk 58/80mm yang sama, TANPA hardware/dependency baru. Barcode
  /// digambar via command EAN-13 native printer (`Generator.barcode`),
  /// bukan raster gambar — lebih ringan & tajam drpd capture widget.
  static Future<bool> printProductLabel({
    required String productName,
    required String unitQty,
    required String variantLabel,
    required int price,
    required String barcode,
  }) async {
    final mac = await getSavedMac();
    if (mac == null || mac.isEmpty) return false;

    final connected = await connect(mac);
    if (!connected) return false;

    final settings = await loadSettings();
    final bytes = await _buildLabelBytes(
      productName: productName,
      unitQty: unitQty,
      variantLabel: variantLabel,
      price: price,
      barcode: barcode,
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

  static Future<Uint8List> _buildLabelBytes({
    required String productName,
    required String unitQty,
    required String variantLabel,
    required int price,
    required String barcode,
    required PrinterSettings settings,
  }) async {
    final profile = await CapabilityProfile.load();
    final paperSize =
        settings.paperSize == '80' ? PaperSize.mm80 : PaperSize.mm58;
    final gen = Generator(paperSize, profile);
    final out = <int>[];

    out.addAll(gen.text(_toAscii(productName),
        styles: const PosStyles(bold: true, align: PosAlign.center)));

    final line2 =
        variantLabel.isEmpty ? unitQty : '$unitQty - ${_toAscii(variantLabel)}';
    out.addAll(gen.text(line2,
        styles: const PosStyles(bold: true, align: PosAlign.center)));

    out.addAll(gen.text('Rp ${_fmtNum(price)}',
        styles: const PosStyles(bold: true, align: PosAlign.center)));

    // EAN-13 butuh persis 12/13 digit numerik — barcode non-standar (mis.
    // hasil scan lama yg bukan 13 digit) tidak digambar sbg barcode grafis,
    // cukup dicetak sbg teks polos supaya tidak throw.
    final digits = barcode.split('').map(int.tryParse).toList();
    if ((barcode.length == 12 || barcode.length == 13) &&
        digits.every((d) => d != null)) {
      out.addAll(gen.barcode(Barcode.ean13(digits.cast<int>()),
          height: 80, textPos: BarcodeText.below));
    } else {
      out.addAll(gen.text(barcode,
          styles: const PosStyles(align: PosAlign.center)));
    }

    out.addAll(gen.feed(2));
    out.addAll(gen.cut());
    return Uint8List.fromList(out);
  }

  // ── Print struk gabungan (gabung nota) ────────────────────────────────────

  /// Cetak struk gabungan beberapa nota: header toko sekali, item per-nota
  /// (terpisah dengan separator), lalu total akumulatif di footer.
  static Future<bool> printMergedReceipt({
    required List<Transaction> txs,
    required Map<String, List<TransactionItem>> itemsByTx,
    Map<String, List<TransactionPayment>> paymentsByTx = const {},
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
    required String customerName,
    String customerAddress = '',
    bool showEmployee = true,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String storeWhatsapp = '',
    String storeTelegram = '',
    String receiptHeader = '',
    String receiptFooter = '',
    Map<String, String?> parentOf = const {},
    DateTime? lastPaymentAt,
  }) async {
    final mac = await getSavedMac();
    if (mac == null || mac.isEmpty) return false;
    final connected = await connect(mac);
    if (!connected) return false;

    final settings = await loadSettings();
    final bytes = await _buildMergedBytes(
      txs: txs,
      itemsByTx: itemsByTx,
      paymentsByTx: paymentsByTx,
      productNames: productNames,
      unitNames: unitNames,
      customerName: customerName,
      customerAddress: customerAddress,
      showEmployee: showEmployee,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      storeWhatsapp: storeWhatsapp,
      storeTelegram: storeTelegram,
      receiptHeader: receiptHeader,
      receiptFooter: receiptFooter,
      parentOf: parentOf,
      lastPaymentAt: lastPaymentAt,
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

  static Future<Uint8List> _buildMergedBytes({
    required List<Transaction> txs,
    required Map<String, List<TransactionItem>> itemsByTx,
    Map<String, List<TransactionPayment>> paymentsByTx = const {},
    required Map<String, String> productNames,
    required Map<String, String> unitNames,
    required String customerName,
    String customerAddress = '',
    bool showEmployee = true,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    String storeWhatsapp = '',
    String storeTelegram = '',
    String receiptHeader = '',
    String receiptFooter = '',
    Map<String, String?> parentOf = const {},
    DateTime? lastPaymentAt,
    required PrinterSettings settings,
  }) async {
    final w = settings.charWidth;
    final profile = await CapabilityProfile.load();
    final paperSize =
        settings.paperSize == '80' ? PaperSize.mm80 : PaperSize.mm58;
    final gen = Generator(paperSize, profile);
    final out = <int>[];

    // ── Header toko (sekali) ──────────────────────────────────────────────
    if (storeName.isNotEmpty) {
      out.addAll(gen.text(_toAscii(storeName),
          styles: const PosStyles(
              bold: true,
              align: PosAlign.center,
              height: PosTextSize.size2,
              width: PosTextSize.size2)));
      // Sedikit jarak setelah nama toko (mirip jarak antar baris kontak).
      out.addAll(gen.feed(1));
    }
    if (storeAddress.isNotEmpty) {
      out.addAll(gen.text(_toAscii(storeAddress),
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (storePhone.isNotEmpty) {
      out.addAll(gen.text('Telp: ${_toAscii(storePhone)}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (storeWhatsapp.isNotEmpty) {
      out.addAll(gen.text('WA: ${_toAscii(storeWhatsapp)}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (storeTelegram.isNotEmpty) {
      out.addAll(gen.text('Telegram: ${_toAscii(storeTelegram)}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (receiptHeader.isNotEmpty) {
      for (final line in receiptHeader.split('\n')) {
        out.addAll(gen.text(_toAscii(line),
            styles: const PosStyles(align: PosAlign.center)));
      }
    }
    out.addAll(gen.text(_sep(w)));
    out.addAll(gen.text(_toAscii(customerName),
        styles: const PosStyles(bold: true, width: PosTextSize.size2)));
    if (customerAddress.isNotEmpty) {
      out.addAll(gen.text(_toAscii(customerAddress)));
    }

    // ── Per-nota (terpisah) ───────────────────────────────────────────────
    var grandTotal = 0;
    var grandPaid = 0;
    var grandSisa = 0;
    for (final tx in txs) {
      grandTotal += tx.total;
      final pays = paymentsByTx[tx.id] ?? const <TransactionPayment>[];
      final sumChangeGiven = pays
          .where((p) => !p.voided)
          .fold<int>(0, (s, p) => s + p.changeGiven);
      // NET (dikurangi kembalian yg dipakai ulang sbg pembayaran) — bukan
      // `tx.paid` mentah, sama akar masalah dgn Item 23 di struk tunggal.
      final rawNetPaid = tx.paid - sumChangeGiven;
      final netPaid = rawNetPaid > 0 ? rawNetPaid : 0;
      final txSisa = tx.total - netPaid;
      grandPaid += netPaid;
      grandSisa += txSisa > 0 ? txSisa : 0;
      final items = itemsByTx[tx.id] ?? const <TransactionItem>[];
      out.addAll(gen.text(_sep(w)));
      out.addAll(gen.text(
          _rowLR('#${shortTxNo(tx.localId)}', _fmtDateTimeFull(tx.createdAt), w),
          styles: const PosStyles(bold: true)));
      // Pegawai di bawah id nota (bila diinput & toggle aktif).
      final empName = (showEmployee ? tx.employeeName?.trim() : null) ?? '';
      if (empName.isNotEmpty) {
        out.addAll(gen.row([
          PosColumn(text: 'Pegawai:', width: 3),
          PosColumn(
              text: ' ${_toAscii(empName)}',
              width: 9,
              styles: const PosStyles(bold: true)),
        ]));
      }
      // Spasi antara header (id / pegawai) dan produk pertama.
      out.addAll(gen.feed(1));
      for (final item in _orderItems(items, parentOf)) {
        final isVar = _parentItemOf(item, items, parentOf) != null;
        final rawName = _toAscii(productNames[item.productId] ?? 'Produk');
        final prefix = isVar ? '  > ' : '';
        out.addAll(
            gen.text('$prefix$rawName', styles: const PosStyles(bold: true)));
        if (item.itemNote != null && item.itemNote!.isNotEmpty) {
          // Item 49c — sama seperti struk tunggal, split per baris dulu.
          for (final line in item.itemNote!.split('\n')) {
            out.addAll(gen.text(_toAscii(line)));
          }
        }
        final uName = _toAscii(unitNames[item.productUnitId] ?? 'pcs');
        final qtyStr = item.qty % 1 == 0
            ? item.qty.toInt().toString()
            : item.qty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
        final qtyLine = '  $qtyStr $uName x ${_fmtNum(item.priceAtSale)}';
        out.addAll(gen.text(_rowLR(qtyLine, _fmtNum(item.subtotal), w)));
      }
      out.addAll(gen.feed(1));
      out.addAll(gen.text(
          _rowLR('Subtotal nota', 'Rp ${_fmtNum(tx.total)}', w),
          styles: const PosStyles(bold: true)));
      if (txSisa > 0) {
        out.addAll(
            gen.text(_rowLR('  Sisa', 'Rp ${_fmtNum(txSisa)}', w)));
      }
    }

    // ── Total akumulatif (layout identik footer struk biasa) ────────────
    out.addAll(gen.text(_sep(w)));

    final maxCharsWide = w ~/ 2;
    List<int> wideNominal(String text) {
      final lp = maxCharsWide - text.length;
      final padded = lp > 0 ? '${' ' * lp}$text' : text;
      return gen.text(padded,
          styles: const PosStyles(bold: true, width: PosTextSize.size2));
    }

    // Item 49b — ringkasan 3-baris (state akhir akumulatif): Total nota
    // gabungan / Terbayar / Kembalian-ATAU-Sisa. Baris "Uang Diterima"
    // (uang tender kotor, Item 9 lama) DIHAPUS, "Sisa" jadi kondisional
    // (bukan selalu tampil apa pun kondisinya) — konsisten dgn struk
    // tunggal & in-app/share.
    TransactionPayment? latestWithChange;
    for (final pays in paymentsByTx.values) {
      for (final p in pays) {
        if (p.voided || p.changeGiven <= 0) continue;
        if (latestWithChange == null ||
            p.paidAt.isAfter(latestWithChange.paidAt)) {
          latestWithChange = p;
        }
      }
    }
    out.addAll(gen.text('Total Tagihan',
        styles: const PosStyles(bold: true)));
    out.addAll(wideNominal('Rp ${_fmtNum(grandTotal)}'));
    // "Terbayar" HARUS Total + Kembalian saat ada kembalian (bukan grandPaid
    // net) — supaya "Total Tagihan = Terbayar - Kembalian" konsisten, sama
    // fix dgn struk tunggal di atas.
    final grandBayar = latestWithChange != null
        ? grandTotal + latestWithChange.changeGiven
        : grandPaid;
    out.addAll(gen.text(_rowLR('Terbayar', 'Rp ${_fmtNum(grandBayar)}', w)));

    if (latestWithChange != null) {
      out.addAll(gen.text('Kembalian', styles: const PosStyles(bold: true)));
      out.addAll(wideNominal('Rp ${_fmtNum(latestWithChange.changeGiven)}'));
    } else if (grandSisa > 0) {
      out.addAll(gen.text('Sisa', styles: const PosStyles(bold: true)));
      out.addAll(wideNominal('Rp ${_fmtNum(grandSisa)}'));
    }
    if (lastPaymentAt != null) {
      out.addAll(gen.text(
          _rowLR('', 'Pelunasan: ${_fmtDateTimeFull(lastPaymentAt)}', w)));
    }

    out.addAll(gen.text(_sep(w)));
    // "Catatan di Struk" (Informasi Toko) — fallback ke "Terima kasih!" bila
    // belum diisi user, sama seperti hint field-nya. Item 49c — split per
    // baris dulu (bisa multi-baris, sama pola dgn struk tunggal di atas).
    final mergedFooterText =
        receiptFooter.isNotEmpty ? receiptFooter : 'Terima kasih!';
    for (final line in mergedFooterText.split('\n')) {
      out.addAll(gen.text(_toAscii(line),
          styles: const PosStyles(align: PosAlign.center)));
    }
    out.addAll(gen.feed(3));
    out.addAll(gen.cut());
    return Uint8List.fromList(out);
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
