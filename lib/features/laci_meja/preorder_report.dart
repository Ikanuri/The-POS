import '../../core/database/app_database.dart';
import 'laci_meja_date_utils.dart';
import 'preorder_calc.dart';

/// Susulan dashboard Laci Meja tab Pre-order (permintaan user) — tombol
/// "salin laporan" yang merangkum antrian pre-order TERBUKA jadi teks siap
/// tempel (WhatsApp/nota manual/dsb).
///
/// Fungsi MURNI (tanpa `BuildContext`/Riverpod) supaya bisa ditest langsung
/// terhadap data, terpisah dari widget tombolnya sendiri (lihat
/// `laci_meja_dashboard_screen.dart` untuk pemanggilnya + `Clipboard.setData`).
///
/// Format SUDAH DISETUJUI user, jangan didesain ulang tanpa diminta:
/// - **Format A** (satu produk — dipakai kalau [productFilter] terisi, ATAU
///   kalau seluruh entri terbuka di [items] kebetulan cuma dari SATU produk
///   walau filter "Semua Produk" sedang aktif): judul "LAPORAN PRE-ORDER —
///   {produk}", tiap entri 3 baris (nama, "Pesan .. - Sisa .. - .. jaminan -
///   status", "Dipesan .. (N hari lalu) - Dipenuhi M dari N").
/// - **Format B** (>1 produk beda, filter "Semua Produk") — judul generik
///   "LAPORAN PRE-ORDER TERBUKA", dikelompokkan per produk dgn header
///   "=== Produk (N pesanan[, Q satuan][, D jaminan]) ===" (nomor urut
///   entri BERKELANJUTAN lintas kelompok, bukan reset), tiap entri jadi SATU
///   baris ringkas "N. Nama: Sisa .. [dari ..] - .. jaminan - status
///   (dipesan dd/MM, N hari lalu[, dipenuhi M/N])".
///
/// Keputusan yang diambil sendiri saat implementasi (dicatat juga di
/// `docs/HANDOFF.md`):
/// - Header grup "=== Produk (...) ===" HANYA menyertakan token qty/jaminan
///   agregat kalau grup itu >1 entri (kalau cuma 1 entri, aggregatnya
///   sekadar duplikat baris entri itu sendiri — dihilangkan biar tidak
///   berulang, contoh yang disetujui user: "Beras 25kg (1 pesanan)" tanpa
///   angka qty/jaminan sama sekali karena grup itu cuma 1 entri).
/// - "N jaminan" — baik per-entri, header grup, maupun total atas/bawah —
///   memakai jaminan SISA (`sisaDeposit` dari `preorder_calc.dart`, SATU
///   logic yang sama dipakai dashboard `_preorderTile`/`_buildPreorderList`),
///   BUKAN `depositQty` mentah. `depositQty` mentah cuma dipakai utk qty
///   yang MEMANG menampilkan angka pesanan awal (mis. total qty barang di
///   header, beda konsep dari jaminan wadah).
///
///   BUG YANG SUDAH DIPERBAIKI: versi sebelumnya (komentar lama di sini
///   sempat mengklaim ini "keputusan disetujui user") memakai `depositQty`
///   MENTAH tanpa dikurangi walau pre-order sudah dipenuhi sebagian —
///   klaim itu SALAH, itu cuma kebetulan dari contoh dummy yang dipakai
///   asisten sesi sebelumnya saat implementasi (bukan keputusan desain user
///   sungguhan), yang kebetulan tidak menunjukkan kasus "dipenuhi
///   sebagian" jadi lolos tanpa ketahuan sampai user sendiri menyadarinya
///   (entri "Dipenuhi 2 dari 5" salah tampil "5 jaminan" mentah, bukan
///   "3 jaminan" sisa — padahal 2 wadah sudah kembali). Perilaku APLIKASI
///   (dashboard, mengurangi jaminan seiring dipenuhi) itu yang BENAR;
///   laporan salin-teks sekarang ikut itu. Lihat CHANGELOG.
/// - Status "Tempo"/"Lunas" memakai `e.paid` (field yang SAMA PERSIS dipakai
///   `_preorderTile` dashboard — field ini sengaja diperbaiki dari bug lama
///   yang salah pakai `depositQty > 0`, lihat komentar di
///   `laci_meja_dashboard_screen.dart`), BUKAN query terpisah ke
///   `transactions.status` — sudah ada sinyal benar & teruji, tidak perlu
///   hitung ulang dari sumber lain. Tapi tetap disembunyikan kalau
///   `transactionId` null (pre-order titip wadah tanpa nota rujukan sama
///   sekali — tidak ada apa pun utk "lunas/tempo"-kan), sesuai spek.
/// - Nama pelanggan ad-hoc (tanpa `customerId`) diberi akhiran " (Umum)"
///   supaya laporan teks (tanpa ikon pembeda spt di dashboard) tetap bisa
///   membedakan pelanggan terdaftar vs ad-hoc — kecuali kalau namanya
///   memang sudah "Umum" (tidak diduplikasi jadi "Umum (Umum)").
String buildPreorderReportText({
  required List<PreorderEntry> items,
  required String? productFilter,
  required Map<String, double> takenQty,
  required Map<String, ({String productName, String unitName})>
      productUnitLabels,
  required Map<String, String> customerNames,
  required DateTime now,
}) {
  final scope = productFilter == null
      ? items
      : items.where((e) => e.productId == productFilter).toList();

  String productNameOf(PreorderEntry e) =>
      productUnitLabels[e.productUnitId]?.productName ?? e.productId;
  String unitNameOf(PreorderEntry e) =>
      productUnitLabels[e.productUnitId]?.unitName ?? '';
  double takenOf(PreorderEntry e) => takenQty[e.id] ?? 0;
  double sisaOf(PreorderEntry e) =>
      (e.qtyOrdered - takenOf(e)).clamp(0.0, e.qtyOrdered);
  double sisaDepositOf(PreorderEntry e) => sisaDeposit(e, takenOf(e));

  String customerLabelOf(PreorderEntry e) {
    final live =
        e.transactionId == null ? null : customerNames[e.transactionId];
    String label;
    if (live != null && live.isNotEmpty) {
      label = live;
    } else {
      final fb = e.customerName.trim();
      label = fb.isNotEmpty ? fb : 'Umum';
    }
    final adhoc = e.customerId == null || e.customerId!.isEmpty;
    if (adhoc && label != 'Umum') label = '$label (Umum)';
    return label;
  }

  String? statusOf(PreorderEntry e) {
    if (e.transactionId == null) return null;
    return e.paid ? 'Lunas' : 'Tempo';
  }

  final distinctProducts = scope.map((e) => e.productId).toSet();
  final useFormatB =
      scope.isEmpty || (productFilter == null && distinctProducts.length > 1);

  final entryCount = scope.length;
  final totalDeposit = scope.fold<double>(0, (s, e) => s + sisaDepositOf(e));
  final printed = _fmtDateTimeLong(now);

  final buf = StringBuffer();

  if (!useFormatB) {
    final title =
        scope.isEmpty ? '' : productNameOf(scope.first);
    final totalQty = scope.fold<double>(0, (s, e) => s + e.qtyOrdered);
    final unitWord = scope.isEmpty ? '' : unitNameOf(scope.first);
    buf.writeln('LAPORAN PRE-ORDER — $title');
    buf.writeln('Dicetak: $printed');
    final qtyPart = unitWord.isEmpty
        ? _fmtNum(totalQty)
        : '${_fmtNum(totalQty)} $unitWord';
    buf.writeln(
        'Total terbuka: $entryCount entri, $qtyPart, **${_fmtNum(totalDeposit)} jaminan**');
    buf.writeln();

    final blocks = <String>[];
    for (var i = 0; i < scope.length; i++) {
      final e = scope[i];
      final sisa = sisaOf(e);
      final entryDeposit = sisaDepositOf(e);
      final depositStr =
          entryDeposit > 0 ? ' - ${_fmtNum(entryDeposit)} jaminan' : '';
      final status = statusOf(e);
      final statusStr = status != null ? ' - $status' : '';
      final line2 = 'Pesan ${_fmtNum(e.qtyOrdered)} ${productNameOf(e)} - '
          'Sisa ${_fmtNum(sisa)}$depositStr$statusStr';
      final taken = takenOf(e);
      final dipenuhiStr = taken > 0
          ? ' - Dipenuhi ${_fmtNum(taken)} dari ${_fmtNum(e.qtyOrdered)}'
          : '';
      final days = calendarDaysSince(e.createdAt, now: now);
      final line3 =
          'Dipesan ${_fmtDateTimeLong(e.createdAt)} ($days hari lalu)$dipenuhiStr';
      blocks.add('${i + 1}. ${customerLabelOf(e)}\n   $line2\n   $line3');
    }
    buf.write(blocks.join('\n\n'));
  } else {
    buf.writeln('LAPORAN PRE-ORDER TERBUKA');
    buf.writeln('Dicetak: $printed');
    buf.writeln(
        'Total terbuka: $entryCount entri, **${_fmtNum(totalDeposit)} jaminan**');
    buf.writeln();

    // Kelompok per produk, urutan grup = urutan kemunculan PERTAMA produk
    // itu di `scope` (yang sudah FIFO by createdAt dari query DB) — LinkedHashMap
    // bawaan Dart Map menjaga urutan insert.
    final groups = <String, List<PreorderEntry>>{};
    for (final e in scope) {
      groups.putIfAbsent(e.productId, () => []).add(e);
    }

    var num = 0;
    final groupBlocks = <String>[];
    for (final groupEntries in groups.values) {
      final first = groupEntries.first;
      final name = productNameOf(first);
      final unitWord = unitNameOf(first);
      final count = groupEntries.length;
      String headerLine;
      if (count > 1) {
        final qtySum = groupEntries.fold<double>(0, (s, e) => s + e.qtyOrdered);
        final depositSum =
            groupEntries.fold<double>(0, (s, e) => s + sisaDepositOf(e));
        final parts = <String>['$count pesanan'];
        final qtyPart = unitWord.isEmpty
            ? _fmtNum(qtySum)
            : '${_fmtNum(qtySum)} $unitWord';
        parts.add(qtyPart);
        if (depositSum > 0) parts.add('${_fmtNum(depositSum)} jaminan');
        headerLine = '=== $name (${parts.join(', ')}) ===';
      } else {
        headerLine = '=== $name (1 pesanan) ===';
      }

      final lines = <String>[headerLine];
      for (final e in groupEntries) {
        num++;
        final sisa = sisaOf(e);
        final taken = takenOf(e);
        final sisaStr = taken > 0
            ? 'Sisa ${_fmtNum(sisa)} dari ${_fmtNum(e.qtyOrdered)}'
            : 'Sisa ${_fmtNum(sisa)}';
        final entryDeposit = sisaDepositOf(e);
        final depositStr =
            entryDeposit > 0 ? ' - ${_fmtNum(entryDeposit)} jaminan' : '';
        final status = statusOf(e);
        final statusStr = status != null ? ' - $status' : '';
        final days = calendarDaysSince(e.createdAt, now: now);
        final dipenuhiStr = taken > 0
            ? ', dipenuhi ${_fmtNum(taken)}/${_fmtNum(e.qtyOrdered)}'
            : '';
        final metaStr =
            ' (dipesan ${_fmtDateShort(e.createdAt)}, $days hari lalu$dipenuhiStr)';
        lines.add(
            '$num. ${customerLabelOf(e)}: $sisaStr$depositStr$statusStr$metaStr');
      }
      groupBlocks.add(lines.join('\n'));
    }
    buf.write(groupBlocks.join('\n\n'));
  }

  buf.write('\n\n**Total jaminan: ${_fmtNum(totalDeposit)}**');
  return buf.toString();
}

/// Angka bulat tanpa ".0" (pola sama `_n`/`_fmt` di dashboard) — qty di sini
/// hampir selalu bilangan bulat, tapi kolomnya `real` jadi tetap bisa
/// pecahan.
String _fmtNum(double v) => v % 1 == 0 ? v.toInt().toString() : '$v';

/// "dd/MM/yyyy HH:mm" — dirakit MANUAL (BUKAN `DateFormat` ber-locale),
/// lihat gotcha `LocaleDataException` di CLAUDE.md (app ini tidak pernah
/// memanggil `initializeDateFormatting`).
String _fmtDateTimeLong(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

/// "dd/MM" — dipakai baris ringkas Format B.
String _fmtDateShort(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}';
}
