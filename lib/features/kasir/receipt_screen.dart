import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/services/printer_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/item_count_badge.dart';
import '../../core/widgets/status_watermark_stamp.dart';
import 'widgets/debt_payment_dialog.dart';
import 'widgets/tx_history_sheet.dart';

/// Sisa tagihan yang BENAR: `total - paid` mentah bisa understate kalau
/// kembalian yang sudah pernah diberikan (baris pembayaran manapun) dipakai
/// ulang sebagai pembayaran baru — uang yang sama ke-hitung dobel di `paid`
/// tanpa pernah dikurangi saat keluar sbg kembalian sebelumnya. `tx.paid` &
/// `tx.changeAmount` MENTAH (kolom header, dipakai apa adanya utk rekonsiliasi
/// internal) TIDAK diubah — tapi SEMUA tampilan ke user (Ringkasan on-screen,
/// struk cetak/gambar tunggal, nota gabungan) pakai fungsi net di file ini
/// ([netPaidDisplay]/[latestChangeGiven]), BUKAN kolom mentahnya langsung.
/// Pembayaran yang DIBATALKAN ("Batalkan Pembayaran") tetap ada di [payments]
/// (jejak audit, tampil dicoret di Riwayat Pembayaran) tapi tidak boleh ikut
/// hitungan finansial mana pun — `tx.paid` sendiri sudah dijaga tidak
/// menghitungnya (lihat `AppDatabase._reconcileTransactionTotals`), di sini
/// cukup jaga `sumChangeGiven` konsisten dengan itu.
int netRemainingOwed(Transaction tx, List<TransactionPayment> payments) {
  final sumChangeGiven = payments
      .where((p) => !p.voided)
      .fold<int>(0, (s, p) => s + p.changeGiven);
  final remaining = tx.total - tx.paid + sumChangeGiven;
  return remaining > 0 ? remaining : 0;
}

/// Dibayar bersih — pasangan [netRemainingOwed] supaya "Total = Dibayar +
/// Sisa Tagihan" konsisten di Ringkasan on-screen (`paid` mentah dipakai
/// apa adanya tetap di struk cetak/gambar, TIDAK di sini).
int netPaidDisplay(Transaction tx, List<TransactionPayment> payments) {
  final sumChangeGiven = payments
      .where((p) => !p.voided)
      .fold<int>(0, (s, p) => s + p.changeGiven);
  final net = tx.paid - sumChangeGiven;
  return net > 0 ? net : 0;
}

/// Total uang yang benar-benar diterima kasir (gross, sebelum dikurangi
/// kembalian) — Item 9. Beda dari [netPaidDisplay] yang net demi arithmetic
/// "Total = Dibayar + Sisa" tetap konsisten di layar; ini murni info
/// tambahan supaya tidak membingungkan pembeli ("kok cuma tercatat 300rb
/// padahal saya kasih 400rb").
int grossReceived(List<TransactionPayment> payments) =>
    payments.where((p) => !p.voided).fold<int>(0, (s, p) => s + p.amount);

/// Kembalian yang BENAR untuk struk cetak/gambar (`_ReceiptPaper`): dari
/// pembayaran TERAKHIR yang tidak dibatalkan — BUKAN akumulasi
/// `tx.changeAmount`, yang bisa salah kalau kembalian yang sudah pernah
/// diberikan dipakai ulang sbg pembayaran baru (mis. tambah belanjaan) —
/// akar masalah sama dgn [netRemainingOwed]. Dipakai juga oleh
/// `printer_service.dart` (struk cetak ESC/POS) via logika sepadan.
int latestChangeGiven(List<TransactionPayment> payments) {
  TransactionPayment? latest;
  for (final p in payments) {
    if (p.voided || p.changeGiven <= 0) continue;
    if (latest == null || p.paidAt.isAfter(latest.paidAt)) latest = p;
  }
  return latest?.changeGiven ?? 0;
}

class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key, required this.transactionId});
  final String transactionId;

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  Transaction? _tx;
  List<TransactionItem> _items = [];
  List<TransactionPayment> _payments = [];
  Map<String, String> _productNames = {};
  Map<String, String> _unitNames = {};
  Map<String, String?> _parentOf = {}; // productId → parentProductId
  Customer? _customer;
  bool _loading = true;

  // Store settings — loaded in _load() agar header on-screen konsisten dgn print.
  String _storeAddress = '';
  String _storePhone = '';
  String _storeWhatsapp = '';
  String _storeTelegram = '';
  String _receiptHeader = '';

  // Pegawai: daftar untuk edit, + toggle tampil di struk share/cetak.
  List<Employee> _employees = [];
  bool _showEmployeeOnReceipt = true;

  /// Inline edit nama pembeli langsung di struk.
  bool _editingCustomer = false;
  final TextEditingController _custCtrl = TextEditingController();
  List<Customer> _custSuggestions = [];

  /// Toggle tampilkan laba per item — persisted via SharedPreferences.
  bool _showProfit = true;

  /// Checklist verifikasi serah-terima barang — persisted ke
  /// `transactions.checkedItemIds` (dulu murni lokal/tidak disimpan).
  final Map<String, bool> _checked = {};
  bool get _allChecked =>
      _items.isNotEmpty && _items.every((i) => _checked[i.id] == true);
  Set<String> get _checkedIds =>
      _checked.entries.where((e) => e.value).map((e) => e.key).toSet();

  Future<void> _persistChecked() async {
    final db = ref.read(databaseProvider);
    await (db.update(db.transactions)
          ..where((t) => t.id.equals(widget.transactionId)))
        .write(TransactionsCompanion(
      checkedItemIds: Value(jsonEncode(_checkedIds.toList())),
    ));
  }

  /// Timeline pembayaran SELALU ditampilkan bila ada minimal 1 pembayaran —
  /// ini satu-satunya tempat tombol "Batalkan Pembayaran" muncul (lihat
  /// `_buildPaymentTimeline`). Sebelumnya disembunyikan untuk penjualan
  /// tunai seketika (1 pembayaran, tidak dibatalkan) demi menghindari
  /// duplikasi info baris tanggal — tapi itu berarti nota yang LANGSUNG
  /// lunas saat dibuat (kasus paling umum) tidak pernah bisa dibatalkan
  /// pembayarannya sama sekali. Fungsi lebih penting dari menghindari 1
  /// baris tanggal yang sedikit redundan.
  bool get _showPaymentTimeline {
    final tx = _tx;
    return tx != null && _payments.isNotEmpty;
  }

  /// Kembalian di Ringkasan SELALU dari pembayaran TERAKHIR yang TIDAK
  /// dibatalkan (bukan akumulatif) — `_payments` sudah terurut ASC by
  /// paidAt dari `getPaymentsForTx`.
  TransactionPayment? get _latestPayment =>
      _payments.where((p) => !p.voided).lastOrNull;

  /// Item induk dari sebuah baris (null bila baris ini bukan varian atau
  /// induknya tidak ada di transaksi ini).
  TransactionItem? _parentItemOf(TransactionItem item) {
    final pid = _parentOf[item.productId];
    if (pid == null) return null;
    for (final it in _items) {
      if (it.productId == pid && _parentOf[it.productId] == null) return it;
    }
    return null;
  }

  List<TransactionItem> get _topLevelItems =>
      _items.where((i) => _parentItemOf(i) == null).toList();

  List<TransactionItem> _childrenOf(TransactionItem parent) =>
      _items.where((i) => _parentItemOf(i)?.id == parent.id).toList();

  void _setParentChecked(TransactionItem parent, bool v) {
    setState(() {
      _checked[parent.id] = v;
      for (final c in _childrenOf(parent)) {
        _checked[c.id] = v;
      }
    });
    unawaited(_persistChecked());
  }

  void _setChildChecked(TransactionItem parent, TransactionItem child, bool v) {
    setState(() {
      _checked[child.id] = v;
      final kids = _childrenOf(parent);
      _checked[parent.id] = kids.every((c) => _checked[c.id] == true);
    });
    unawaited(_persistChecked());
  }

  /// Qty sebuah item di receipt. transaction_items SELALU menyimpan qty
  /// efektif (layar bayar menulis `l.eq`; induk placeholder eff 0 tidak
  /// disimpan) — jadi tidak boleh dikurangi qty varian lagi. Pengurangan
  /// ganda membuat induk yang dijual bersama varian tampil "via varian"
  /// dengan nominal hilang, padahal qty dasarnya > 0.
  double _itemEffQty(TransactionItem item) => item.qty;

  /// Susun baris item untuk struk in-app. Bila ada item susulan (addedAt != null,
  /// fitur tambah belanjaan), sisipkan pembatas "Tambahan <jam>" sebelum batch
  /// item susulan. Khusus tampilan in-app — share/cetak tetap menyatu.
  List<Widget> _buildItemRows(ColorScheme scheme,
      {bool showProfit = false, bool editable = false}) {
    final rows = <Widget>[];
    String? lastBatchLabel;
    for (final parent in _topLevelItems) {
      final added = parent.addedAt;
      if (added != null) {
        final label =
            '${added.hour.toString().padLeft(2, '0')}:${added.minute.toString().padLeft(2, '0')}';
        if (label != lastBatchLabel) {
          lastBatchLabel = label;
          rows.add(_AddedSeparator(time: label, scheme: scheme));
        }
      }
      rows.add(_itemCheckRow(parent, scheme,
          isVariant: false, showProfit: showProfit, editable: editable));
      for (final child in _childrenOf(parent)) {
        rows.add(_itemCheckRow(child, scheme,
            isVariant: true,
            parent: parent,
            showProfit: showProfit,
            editable: editable));
      }
    }
    return rows;
  }

  Widget _itemCheckRow(TransactionItem item, ColorScheme scheme,
      {required bool isVariant,
      TransactionItem? parent,
      bool showProfit = false,
      bool editable = false}) {
    final checked = _checked[item.id] ?? false;
    final hasChildren = !isVariant && _childrenOf(item).isNotEmpty;
    final effQty = _itemEffQty(item);
    final isPlaceholder = !isVariant && effQty == 0 && hasChildren;
    final laba = showProfit && effQty > 0
        ? ((item.priceAtSale - item.costAtSale) * effQty).round()
        : 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profitColor =
        isDark ? const Color(0xFF81C784) : const Color(0xFF388E3C);

    void onCheckChanged(bool? v) {
      final nv = v ?? false;
      if (isVariant && parent != null) {
        _setChildChecked(parent, item, nv);
      } else if (hasChildren) {
        _setParentChecked(item, nv);
      } else {
        setState(() => _checked[item.id] = nv);
      }
      unawaited(_persistChecked());
    }

    return GestureDetector(
      onLongPress: isPlaceholder ? null : () => _editItemNote(item),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: isVariant ? 28 : 4, right: 12),
        // Item 5 — tap item (bukan checkbox) buka modal edit, HANYA saat
        // nota belum lunas (checkbox tetap harus bisa dipakai independen —
        // beda gesture, beda tujuan). Placeholder induk-via-varian tidak
        // punya baris nyata utk diedit.
        onTap: (!isPlaceholder && editable) ? () => _openEditItemSheet(item) : null,
        leading: Checkbox(value: checked, onChanged: onCheckChanged),
        title: Row(
          children: [
            if (isVariant)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.subdirectory_arrow_right,
                    size: 13, color: scheme.onSurfaceVariant),
              ),
            Expanded(
              child: Text(
                _productNames[item.productId] ?? item.productId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isVariant ? 12 : 13,
                  fontWeight: isVariant ? FontWeight.w500 : FontWeight.w700,
                  decoration: checked ? TextDecoration.lineThrough : null,
                  color: checked
                      ? scheme.onSurfaceVariant
                      : (isVariant ? scheme.onSurfaceVariant : null),
                ),
              ),
            ),
          ],
        ),
        subtitle: isPlaceholder
            ? Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'via varian',
                  style: TextStyle(fontSize: 11, color: scheme.primary),
                ),
              )
            : Padding(
                padding: EdgeInsets.only(left: isVariant ? 17 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                        children: [
                          // Jumlah qty + satuan di-bold (mudah dibaca), tapi
                          // TIDAK lebih tebal dari nama produk (w700 induk /
                          // w500 varian). Bagian "× harga" tetap berat normal.
                          TextSpan(
                            text: '${effQty % 1 == 0 ? effQty.toInt() : effQty} '
                                '${_unitNames[item.productUnitId] ?? ''}',
                            style: TextStyle(
                                fontWeight: isVariant
                                    ? FontWeight.w500
                                    : FontWeight.w600),
                          ),
                          TextSpan(
                            text: ' × ${formatRupiah(item.priceAtSale)}',
                          ),
                          if (item.priceOverridden &&
                              item.originalPrice != item.priceAtSale) ...[
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: formatRupiah(item.originalPrice),
                              style: TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: scheme.onSurfaceVariant.withOpacity(0.6),
                              ),
                            ),
                          ],
                          if (showProfit && effQty > 0)
                            TextSpan(
                              text: laba >= 0
                                  ? '\nLaba: ${formatRupiah(laba)}'
                                  : '\nRugi: ${formatRupiah(-laba)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: laba >= 0 ? profitColor : scheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (item.itemNote != null)
                      _Blockquote(
                        text: item.itemNote!,
                        color: scheme.outlineVariant,
                      ),
                  ],
                ),
              ),
        trailing: isPlaceholder
            ? null
            : Text(
                formatRupiah((item.priceAtSale * effQty).round()),
                style: TextStyle(
                    fontSize: isVariant ? 12 : 13, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Future<void> _editItemNote(TransactionItem item) async {
    final ctrl = TextEditingController(text: item.itemNote ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_productNames[item.productId] ?? 'Catatan Barang'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Catatan barang…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          if (item.itemNote != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Hapus'),
            ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.transactionItems)..where((t) => t.id.equals(item.id)))
        .write(TransactionItemsCompanion(
      itemNote: Value(result.isEmpty ? null : result),
    ));
    await _load();
  }

  /// Item 5 — modal edit item nota BELUM LUNAS: ubah harga, qty (cuma bisa
  /// dikurangi/dihapus — bukan ditambah), catatan. Dipanggil dari tap item
  /// di `_itemCheckRow` (gated `editable`, cuma saat `isKurangBayar`).
  Future<void> _openEditItemSheet(TransactionItem item) async {
    final priceCtrl = TextEditingController(
        text: ThousandsSeparatorFormatter.format(item.priceAtSale));
    final noteCtrl = TextEditingController(text: item.itemNote ?? '');
    var qty = item.qty;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_productNames[item.productId] ?? 'Edit Barang',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Nota belum lunas — perubahan langsung menyesuaikan total & hutang.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ThousandsSeparatorFormatter()],
                  decoration: const InputDecoration(
                      labelText: 'Harga', prefixText: 'Rp ',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Jumlah', style: TextStyle(color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed:
                          qty <= 0 ? null : () => setSheet(() => qty -= 1),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        qty % 1 == 0 ? qty.toInt().toString() : qty.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      // Kalau nota SUDAH ada pembayaran (paid > 0), sengaja
                      // TIDAK bisa melebihi qty asli — cuma kurangi/hapus,
                      // bukan tambah barang baru (itu sudah ada jalur
                      // "Tambah Belanjaan" terpisah). Khusus nota yang
                      // BELUM ada pembayaran sama sekali (paid == 0), qty
                      // boleh dinaikkan bebas — tidak ada risiko rekonsiliasi
                      // pembayaran krn memang belum ada uang masuk.
                      onPressed: (_tx!.paid > 0 && qty >= item.qty)
                          ? null
                          : () => setSheet(() => qty += 1),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Catatan barang',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => setSheet(() => qty = 0),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Hapus Barang Ini'),
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(qty <= 0 ? 'Hapus' : 'Simpan Perubahan'),
                ),
              ],
            ),
          ),
        );
      },
    );

    priceCtrl.dispose();
    if (saved != true || !mounted) return;

    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    final newPrice = ThousandsSeparatorFormatter.parseValue(priceCtrl.text);
    final newNote = noteCtrl.text.trim();
    noteCtrl.dispose();

    try {
      await db.editUnpaidTransactionItem(
        txId: widget.transactionId,
        transactionItemId: item.id,
        newQty: qty,
        newPrice: newPrice,
        newNote: newNote,
        kasirId: device.deviceCode,
      );
    } catch (_) {
      if (mounted) {
        AppTheme.showSnack(context, 'Gagal menyimpan perubahan', isError: true);
      }
      return;
    }
    await _load();
  }

  Future<void> _editInternalNote() async {
    final ctrl = TextEditingController(text: _tx!.internalNote ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Catatan Internal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Hanya terlihat di aplikasi, tidak muncul di struk cetak/share.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Tulis catatan…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.transactions)
          ..where((t) => t.id.equals(widget.transactionId)))
        .write(TransactionsCompanion(
      internalNote: Value(result.isEmpty ? null : result),
    ));
    await _load();
  }

  Future<void> _editStrukNote() async {
    final ctrl = TextEditingController(text: _tx!.strukNote ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Catatan Nota'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Muncul di semua jenis struk (aplikasi, share, cetak).',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Tulis catatan…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Simpan')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.transactions)
          ..where((t) => t.id.equals(widget.transactionId)))
        .write(TransactionsCompanion(
      strukNote: Value(result.isEmpty ? null : result),
    ));
    await _load();
  }

  /// Toggle centang "kembalian sudah diambil" untuk SATU baris pembayaran
  /// (kembalian sekarang per-pembayaran, bukan per-transaksi — nota dengan
  /// beberapa pembayaran bisa punya beberapa kembalian terpisah) — dipakai
  /// untuk nota yang barangnya diambil belakangan, mencegah kasir memberi
  /// kembalian dua kali.
  Future<void> _toggleChangeTaken(String paymentId, bool value) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.transactionPayments)
          ..where((t) => t.id.equals(paymentId)))
        .write(TransactionPaymentsCompanion(changeTaken: Value(value)));
    await _load();
  }

  /// Item 4 — "Batalkan Pembayaran". Sama gerbang izin dgn `showVoidTransaction
  /// Dialog` (`batal_transaksi`) — ini juga aksi finansial yang membatalkan
  /// sesuatu yang sudah tercatat. Beda dari void transaksi: item & stok
  /// TIDAK disentuh, baris pembayaran TETAP ada (jejak audit, ditandai
  /// dibatalkan) — lihat `AppDatabase.voidPayment`.
  Future<void> _voidPayment(TransactionPayment payment) async {
    final db = ref.read(databaseProvider);
    final device = ref.read(deviceProvider);
    if (device.deviceRole == 'kasir') {
      final allowed = await db.isPermissionEnabled('batal_transaksi');
      if (!allowed) {
        if (mounted) {
          AppTheme.showSnack(
              context, 'Tidak punya izin membatalkan pembayaran',
              isError: true);
        }
        return;
      }
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan Pembayaran?'),
        content: Text(
          'Pembayaran ${formatRupiah(payment.amount)} (${_methodLabel(payment.method)}) '
          'pada ${_formatDateTime(payment.paidAt)} akan dibatalkan. Nota '
          'kembali berstatus belum lunas — barang & stok TIDAK berubah.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Batalkan Pembayaran'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await db.voidPayment(payment.id);
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _custCtrl.dispose();
    super.dispose();
  }

  // ── Inline edit pelanggan ──────────────────────────────────────────────
  void _enterEditCustomer() {
    final tx = _tx;
    if (tx == null) return;
    _custCtrl.text = _customer?.name ?? tx.customerName ?? '';
    _custCtrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _custCtrl.text.length);
    setState(() {
      _editingCustomer = true;
      _custSuggestions = [];
    });
  }

  Future<void> _onCustQueryChanged(String v) async {
    final found = await ref.read(databaseProvider).searchCustomers(v.trim());
    if (mounted) setState(() => _custSuggestions = found.take(5).toList());
  }

  /// Konfirmasi nama bebas (pembeli umum) — dipanggil saat tap di luar field.
  void _commitFreeName() {
    if (!_editingCustomer) return;
    final tx = _tx;
    if (tx == null) return;
    final name = _custCtrl.text.trim();
    final original = _customer?.name ?? tx.customerName ?? '';
    // Tidak berubah → tutup tanpa menyentuh data (jaga pelanggan terdaftar).
    if (name == original) {
      setState(() {
        _editingCustomer = false;
        _custSuggestions = [];
      });
      return;
    }
    _saveCustomer(name: name.isEmpty ? null : name, id: null);
  }

  Future<void> _saveCustomer({String? name, String? id}) async {
    final db = ref.read(databaseProvider);
    // `changeTransactionCustomer` menangani poin loyalitas otomatis: kalau
    // pelanggan LAMA sudah dapat poin & pelanggan berubah (termasuk balik
    // ke Umum, id == null), poin lama ditarik balik dulu sebelum pelanggan
    // BARU (kalau ada) dihitung ulang & diberi poin dari 0.
    await db.changeTransactionCustomer(
      txId: widget.transactionId,
      newCustomerId: id,
      newCustomerName: name,
    );
    Customer? customer;
    if (id != null) {
      customer = await (db.select(db.customers)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
    }
    final updatedTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(widget.transactionId)))
        .getSingleOrNull();
    if (mounted) {
      setState(() {
        _editingCustomer = false;
        _custSuggestions = [];
        _customer = customer;
        if (updatedTx != null) _tx = updatedTx;
      });
    }
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(widget.transactionId)))
        .getSingleOrNull();
    if (tx == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    final items = await (db.select(db.transactionItems)
          ..where((t) => t.transactionId.equals(widget.transactionId)))
        .get();
    final payments = await db.getPaymentsForTx(widget.transactionId);

    Customer? customer;
    if (tx.customerId != null) {
      customer = await (db.select(db.customers)
            ..where((t) => t.id.equals(tx.customerId!)))
          .getSingleOrNull();
    }

    // Load product + unit names
    final productNames = <String, String>{};
    final unitNames = <String, String>{};
    final parentOf = <String, String?>{};
    for (final item in items) {
      if (!productNames.containsKey(item.productId)) {
        final p = await (db.select(db.products)
              ..where((t) => t.id.equals(item.productId)))
            .getSingleOrNull();
        productNames[item.productId] = p?.name ?? item.productId;
        parentOf[item.productId] = p?.parentProductId;
      }
      if (!unitNames.containsKey(item.productUnitId)) {
        final u = await (db.select(db.productUnits)
              ..where((t) => t.id.equals(item.productUnitId)))
            .getSingleOrNull();
        if (u?.unitTypeId != null) {
          final ut = await (db.select(db.unitTypes)
                ..where((t) => t.id.equals(u!.unitTypeId!)))
              .getSingleOrNull();
          unitNames[item.productUnitId] = ut?.name ?? '';
        }
      }
    }

    final checkedIds = <String>{};
    if (tx.checkedItemIds != null) {
      try {
        checkedIds.addAll((jsonDecode(tx.checkedItemIds!) as List).cast<String>());
      } catch (_) {
        // Data rusak/format lama — abaikan, mulai dari kosong.
      }
    }

    final storeAddress = await db.getSetting('store_address') ?? '';
    final storePhone = await db.getSetting('store_phone') ?? '';
    final storeWhatsapp = await db.getSetting('store_whatsapp') ?? '';
    final storeTelegram = await db.getSetting('store_telegram') ?? '';
    final receiptHeader = await db.getSetting('receipt_header') ?? '';
    final showEmp = await db.getSetting('receipt_show_employee');
    final employees = await db.getEmployees();
    final prefs = await SharedPreferences.getInstance();
    final showProfit = prefs.getBool('receipt_show_profit') ?? true;

    if (mounted) {
      setState(() {
        _showProfit = showProfit;
        _tx = tx;
        _items = items;
        _payments = payments;
        _checked
          ..clear()
          ..addEntries(checkedIds.map((id) => MapEntry(id, true)));
        _productNames = productNames;
        _unitNames = unitNames;
        _parentOf = parentOf;
        _customer = customer;
        _storeAddress = storeAddress;
        _storePhone = storePhone;
        _storeWhatsapp = storeWhatsapp;
        _storeTelegram = storeTelegram;
        _receiptHeader = receiptHeader;
        _showEmployeeOnReceipt = showEmp == null || showEmp == '1';
        _employees = employees;
        _loading = false;
      });
    }
  }

  /// Nama pegawai untuk struk share/cetak: kosong bila toggle mati atau tak
  /// diinput (struk menampilkan nothing bila kosong).
  String get _employeeForReceipt =>
      _showEmployeeOnReceipt ? (_tx?.employeeName ?? '') : '';

  /// Edit / hapus pegawai pada nota ini (modal sheet, tanpa keyboard).
  Future<void> _pickEmployee() async {
    final scheme = Theme.of(context).colorScheme;
    final db = ref.read(databaseProvider);
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('Pegawai yang Melayani',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/pengaturan/pegawai');
                    },
                    icon: const Icon(Icons.settings_outlined, size: 16),
                    label: const Text('Kelola'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.block_outlined),
                    title: const Text('Tanpa pegawai'),
                    onTap: () => Navigator.pop(ctx, 'none'),
                  ),
                  if (_employees.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Belum ada pegawai. Tambah lewat "Kelola".',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  ..._employees.map((e) => ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: scheme.primaryContainer,
                          child: Text(
                            (e.name.isEmpty ? '?' : e.name[0]).toUpperCase(),
                            style: TextStyle(
                                color: scheme.onPrimaryContainer, fontSize: 12),
                          ),
                        ),
                        title: Text(e.name),
                        trailing: _tx?.employeeName == e.name
                            ? Icon(Icons.check, color: scheme.primary)
                            : null,
                        onTap: () => Navigator.pop(ctx, e),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result == null) return; // dismiss
    final newName = result is Employee ? result.name : null;
    await (db.update(db.transactions)
          ..where((t) => t.id.equals(widget.transactionId)))
        .write(TransactionsCompanion(employeeName: Value(newName)));
    final updated = await (db.select(db.transactions)
          ..where((t) => t.id.equals(widget.transactionId)))
        .getSingleOrNull();
    if (mounted && updated != null) setState(() => _tx = updated);
  }

  String _customerDisplay(Transaction tx) {
    if (_customer != null) return _customer!.name;
    if (tx.customerName != null) return tx.customerName!;
    return 'Umum';
  }

  /// Field inline edit pelanggan. Tap di luar → simpan nama bebas (umum);
  /// tap nama di dropdown → simpan pelanggan terdaftar.
  Widget _buildCustomerEditor(ColorScheme scheme) {
    return TapRegion(
      onTapOutside: (_) => _commitFreeName(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _custCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nama pembeli',
                    hintStyle:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    prefixText: 'Pelanggan: ',
                    prefixStyle:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    border: UnderlineInputBorder(
                        borderSide: BorderSide(color: scheme.outlineVariant)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide:
                            BorderSide(color: scheme.primary, width: 1.5)),
                    contentPadding: const EdgeInsets.only(bottom: 2),
                  ),
                  onChanged: _onCustQueryChanged,
                  onTap: () => _custCtrl.selection = TextSelection(
                      baseOffset: 0, extentOffset: _custCtrl.text.length),
                ),
              ),
            ],
          ),
          if (_custSuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in _custSuggestions)
                    InkWell(
                      onTap: () => _saveCustomer(id: c.id, name: null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        child: Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 14, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(c.name,
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  // Alamat di bawah nama — disambiguasi
                                  // pelanggan dengan nama sama.
                                  if ((c.address ?? '').trim().isNotEmpty)
                                    Text(c.address!.trim(),
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: scheme.onSurfaceVariant),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                ],
                              ),
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

  String _methodLabel(String method) => switch (method) {
        'tunai' => 'Tunai',
        'transfer' => 'Transfer',
        'qris' => 'QRIS',
        'ewallet' => 'E-Wallet',
        'tempo' => 'Tempo',
        _ => method,
      };

  Future<void> _showTambahBayar(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final remaining = netRemainingOwed(_tx!, _payments);
    final db = ref.read(databaseProvider);
    final result = await showDebtPaymentDialog(context, db,
        remaining: remaining, title: 'Bayar', prefillRemaining: false);

    if (result != null && result.amount > 0 && mounted) {
      final device = ref.read(deviceProvider);
      // Uang diterima dicatat PENUH (paid boleh > total → kembalian
      // diturunkan dari paid - total), lewat satu jalur DB yang konsisten
      // dengan _reconcileTransactionTotals — kalau paid di-cap dan kembalian
      // disimpan terpisah, rekonsiliasi (sync/tambah belanjaan/retur) akan
      // menimpanya kembali ke 0 dan info "Kembali Rp X" hilang.
      final change = await db.addPaymentToTransaction(
        txId: widget.transactionId,
        amount: result.amount,
        method: result.method,
        kasirId: device.deviceCode,
      );
      await _load();
      if (change > 0) {
        messenger.showSnackBar(
            SnackBar(content: Text('Kembalian ${formatRupiah(change)}')));
      }
    }
  }

  Future<void> _showVoid(BuildContext context) async {
    final ok = await showVoidTransactionDialog(context, ref, _tx!);
    if (ok && mounted) await _load();
  }

  Future<void> _showReturSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    final returnQty = <String, double>{for (final i in _items) i.id: 0};

    // Nota belum lunas (tempo/kurang_bayar): retur mengedit nota ASLI langsung
    // (kurangi/hapus baris item, hutang berkurang) — tidak ada nota retur
    // terpisah & tidak ada refund tunai, karena memang belum ada uang masuk.
    // Nota sudah lunas: tetap nota retur terpisah + refund (uang sudah
    // benar-benar berpindah).
    final isUnpaidTx = _tx!.status == 'tempo' || _tx!.status == 'kurang_bayar';

    // Qty yang sudah pernah diretur sebelumnya (cegah double-retur). Untuk
    // nota belum lunas ini selalu kosong (baris sudah dikurangi in-place),
    // tapi aman dipanggil di kedua jalur.
    final alreadyReturned = await db.getReturnedQtyByUnit(_tx!.id);

    // Load metode pembayaran untuk pilihan refund.
    final paymentMethods = await (db.select(db.paymentMethods)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();

    if (!context.mounted) return;

    // Sisa qty yang masih boleh diretur per baris item.
    double remainingFor(TransactionItem item) =>
        (item.qty - (alreadyReturned[item.productUnitId] ?? 0))
            .clamp(0.0, item.qty);

    // Default refund = metode aktif pertama yang bertipe sama dengan
    // transaksi asal. Dropdown di-key pakai `id` metode (unik), BUKAN `type`:
    // dua metode setipe (mis. dua rekening bank) membuat nilai dropdown
    // duplikat → assertion Flutter gagal dan sheet retur tidak bisa dipakai.
    const fallbackTunaiId = '__tunai__';
    var refundMethodId = paymentMethods
            .where((m) => m.type == _tx!.paymentMethod)
            .firstOrNull
            ?.id ??
        paymentMethods.where((m) => m.type == 'tunai').firstOrNull?.id ??
        fallbackTunaiId;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            int refund = 0;
            var anyQtySelected = false;
            for (final i in _items) {
              final q = returnQty[i.id] ?? 0;
              if (q > 0) anyQtySelected = true;
              refund += (i.priceAtSale * q).round();
            }
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Retur Barang',
                        style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Pilih jumlah barang yang dikembalikan.',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: _items.map((item) {
                          final maxQty = remainingFor(item);
                          final q = returnQty[item.id] ?? 0;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                _productNames[item.productId] ?? item.productId,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                'Maks ${maxQty % 1 == 0 ? maxQty.toInt() : maxQty} · ${formatRupiah(item.priceAtSale)}',
                                style: const TextStyle(fontSize: 11)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      size: 20),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: q <= 0
                                      ? null
                                      : () => setSheet(
                                          () => returnQty[item.id] = q - 1),
                                ),
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    q % 1 == 0 ? q.toInt().toString() : '$q',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      size: 20),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: q >= maxQty
                                      ? null
                                      : () => setSheet(
                                          () => returnQty[item.id] = q + 1),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const Divider(),
                    if (isUnpaidTx)
                      // Nota belum lunas: tidak ada uang yang dikembalikan —
                      // jelaskan bahwa ini mengurangi hutang, bukan refund.
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: scheme.onTertiaryContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Nota ini belum lunas — retur akan mengurangi '
                                'hutang, bukan uang tunai kembali.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onTertiaryContainer),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // Pilihan metode refund — hanya relevan bila nota sudah
                      // lunas (uang benar-benar perlu dikembalikan).
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Text('Kembalikan via',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurfaceVariant)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isDense: true,
                                  value: refundMethodId,
                                  items: [
                                    ...paymentMethods
                                        .map((m) => DropdownMenuItem(
                                              value: m.id,
                                              child: Text(m.name,
                                                  style: const TextStyle(
                                                      fontSize: 13)),
                                            )),
                                    if (!paymentMethods
                                        .any((m) => m.type == 'tunai'))
                                      const DropdownMenuItem(
                                        value: fallbackTunaiId,
                                        child: Text('Tunai',
                                            style: TextStyle(fontSize: 13)),
                                      ),
                                  ],
                                  onChanged: (v) => setSheet(() =>
                                      refundMethodId = v ?? fallbackTunaiId),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // "Total Dikurangi dari Hutang" lebih panjang dari
                        // "Total Refund" — dibungkus Expanded + ellipsis agar
                        // tidak meluber di layar sempit; nominal di kanan
                        // (lebih penting) selalu tampil utuh.
                        Expanded(
                          child: Text(
                              isUnpaidTx
                                  ? 'Total Dikurangi dari Hutang'
                                  : 'Total Refund',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        Text(formatRupiah(refund),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scheme.error)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      // Gate pada "ada qty dipilih", BUKAN "refund > 0" — item
                      // seharga Rp0 (mis. promo/bonus) valid diretur meski
                      // nominalnya nol.
                      onPressed: !anyQtySelected
                          ? null
                          : () => Navigator.of(ctx).pop(true),
                      style:
                          FilledButton.styleFrom(backgroundColor: scheme.error),
                      child: const Text('Konfirmasi Retur'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) return;

    final device = ref.read(deviceProvider);

    if (isUnpaidTx) {
      // Nota belum lunas: edit nota asli langsung, tidak ada nota retur
      // terpisah / refund tunai (lihat returnUnpaidTransactionItems).
      final returns = [
        for (final item in _items)
          if ((returnQty[item.id] ?? 0) > 0)
            (transactionItemId: item.id, qty: returnQty[item.id]!),
      ];
      if (returns.isEmpty) return;

      await db.returnUnpaidTransactionItems(
        txId: _tx!.id,
        returns: returns,
        kasirId: device.deviceCode,
      );
      // Nota asli berubah (item & total berkurang) — muat ulang agar layar
      // tidak menampilkan data basi.
      await _load();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
            content:
                Text('Retur dicatat, hutang berkurang, stok dikembalikan')));
      }
      return;
    }

    final localId = await db.generateUniqueLocalId(device.deviceCode);
    if (!mounted) return;

    final returnItems = [
      for (final item in _items)
        if ((returnQty[item.id] ?? 0) > 0)
          (
            productUnitId: item.productUnitId,
            productId: item.productId,
            qty: returnQty[item.id]!,
            price: item.priceAtSale,
            costPrice: item.costAtSale,
            itemNote: item.itemNote,
          ),
    ];
    if (returnItems.isEmpty) return;

    // Terjemahkan id metode terpilih kembali ke `type` (yang disimpan DB).
    final refundMethod =
        paymentMethods.where((m) => m.id == refundMethodId).firstOrNull?.type ??
            'tunai';
    await db.addReturnTransaction(
      originalTxId: _tx!.id,
      localId: localId,
      returnItems: returnItems,
      kasirId: device.deviceCode,
      refundMethod: refundMethod,
    );
    if (mounted) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Retur dicatat, stok dikembalikan')));
    }
  }

  Future<void> _printReceipt() async {
    final mac = await PrinterService.getSavedMac();
    if (mac == null || mac.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Printer belum dikonfigurasi'),
          action: SnackBarAction(
            label: 'Pengaturan',
            onPressed: () => context.push('/pengaturan/printer'),
          ),
        ),
      );
      return;
    }
    // Pastikan izin Bluetooth runtime sudah ada agar tidak menggantung.
    final granted = await PrinterService.ensurePermissions();
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Izin Bluetooth ditolak'),
          action: SnackBarAction(
            label: 'Pengaturan',
            onPressed: () => context.push('/pengaturan/printer'),
          ),
        ),
      );
      return;
    }
    final prefs = await _getStorePrefs();
    final ok = await PrinterService.printReceipt(
      tx: _tx!,
      items: _items,
      payments: _payments,
      productNames: _productNames,
      unitNames: _unitNames,
      customer: _customer,
      employeeName: _employeeForReceipt,
      storeName: prefs.name,
      storeAddress: prefs.address,
      storePhone: prefs.phone,
      storeWhatsapp: prefs.whatsapp,
      storeTelegram: prefs.telegram,
      receiptHeader: prefs.header,
      strukNote: _tx!.strukNote,
      parentOf: _parentOf,
    );
    if (!mounted) return;
    AppTheme.showSnack(
        context, ok ? 'Struk berhasil dicetak' : 'Gagal mencetak struk',
        isError: !ok);
  }

  Future<
      ({
        String name,
        String address,
        String phone,
        String whatsapp,
        String telegram,
        String header,
      })> _getStorePrefs() async {
    final db = ref.read(databaseProvider);
    return (
      name: await db.getSetting('store_name') ?? '',
      address: await db.getSetting('store_address') ?? '',
      phone: await db.getSetting('store_phone') ?? '',
      whatsapp: await db.getSetting('store_whatsapp') ?? '',
      telegram: await db.getSetting('store_telegram') ?? '',
      header: await db.getSetting('receipt_header') ?? '',
    );
  }

  Future<void> _showShareSheet() async {
    final prefs = await _getStorePrefs();
    final device = ref.read(deviceProvider);
    if (!mounted) return;

    final boundaryKey = GlobalKey();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Bagikan Struk', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: _ReceiptPaper(
                      tx: _tx!,
                      items: _items,
                      payments: _payments,
                      productNames: _productNames,
                      unitNames: _unitNames,
                      customerName: _customerDisplay(_tx!),
                      customerAddress: _customer?.address?.trim() ?? '',
                      employeeName: _employeeForReceipt,
                      storeName:
                          prefs.name.isNotEmpty ? prefs.name : device.storeName,
                      storeAddress: prefs.address,
                      storePhone: prefs.phone,
                      storeWhatsapp: prefs.whatsapp,
                      storeTelegram: prefs.telegram,
                      receiptHeader: prefs.header,
                      parentOf: _parentOf,
                      checkedIds: _checkedIds,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _captureAndShare(ctx, boundaryKey),
                icon: const Icon(Icons.share),
                label: const Text('Bagikan Gambar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureAndShare(
      BuildContext sheetCtx, GlobalKey boundaryKey) async {
    try {
      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/struk_${_tx!.localId}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'Struk #${shortTxNo(_tx!.localId)}',
      );
      if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
    } catch (e) {
      if (sheetCtx.mounted) {
        ScaffoldMessenger.of(sheetCtx).showSnackBar(
          SnackBar(content: Text('Gagal membagikan: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceProvider);
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_tx == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Struk')),
        body: const Center(child: Text('Transaksi tidak ditemukan')),
      );
    }

    final tx = _tx!;
    final isKurangBayar = tx.status == 'kurang_bayar' || tx.status == 'tempo';
    final isVoid = tx.status == 'void';
    final isRetur = tx.internalNote?.startsWith('RETUR:') ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Struk'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/kasir'),
        ),
        actions: [
          if (device.canSeeReports)
            PopupMenuButton<String>(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Pengaturan Struk',
              onSelected: (v) async {
                if (v == 'toggle_profit') {
                  final prefs = await SharedPreferences.getInstance();
                  final next = !_showProfit;
                  await prefs.setBool('receipt_show_profit', next);
                  setState(() => _showProfit = next);
                }
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem<String>(
                  value: 'toggle_profit',
                  checked: _showProfit,
                  child: const Text('Tampilkan Laba',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Bagikan Struk',
            onPressed: _tx == null ? null : () => _showShareSheet(),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Cetak Struk',
            onPressed: _tx == null ? null : () => _printReceipt(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Struk header — desain cermin dari nota cetak
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Identitas toko — centered, seperti header nota cetak
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    children: [
                      Text(
                        device.storeName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5),
                      ),
                      if (_storeAddress.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(_storeAddress,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                      if (_storePhone.isNotEmpty ||
                          _storeWhatsapp.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (_storePhone.isNotEmpty) 'Telp: $_storePhone',
                            if (_storeWhatsapp.isNotEmpty)
                              'WA: $_storeWhatsapp',
                          ].join('   '),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                      if (_storeTelegram.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Telegram: $_storeTelegram',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                      if (_receiptHeader.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(_receiptHeader,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, color: scheme.outlineVariant),
                // Info transaksi
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.badge_outlined,
                              size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          // Nama device bebas diisi user saat setup — bisa panjang.
                          // Dibungkus Expanded + ellipsis agar tanggal di kanan
                          // (info lebih penting) tidak ikut terdorong meluber.
                          Expanded(
                            child: Text('Kasir: ${device.deviceName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                          ),
                          const SizedBox(width: 6),
                          Text(_formatDateTime(tx.createdAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Pelanggan — tap untuk inline edit
                      _editingCustomer
                          ? _buildCustomerEditor(scheme)
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _enterEditCustomer,
                              child: Row(
                                children: [
                                  Icon(Icons.person_outline,
                                      size: 14, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text('Pelanggan: ',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: scheme.onSurfaceVariant)),
                                  Expanded(
                                    child: Text(
                                      _customerDisplay(tx),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _customer != null ||
                                                tx.customerName != null
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                        fontWeight: _customer != null ||
                                                tx.customerName != null
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        fontStyle: (_customer == null &&
                                                tx.customerName == null)
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.edit_outlined,
                                      size: 12, color: scheme.primary),
                                ],
                              ),
                            ),
                      // Alamat pelanggan terdaftar, di bawah baris nama.
                      if (!_editingCustomer &&
                          (_customer?.address?.trim().isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(left: 20, top: 2),
                          child: Text(
                            _customer!.address!.trim(),
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      // Pegawai yang melayani — hanya tampil bila diinput.
                      // Tap untuk ganti / hapus (input awal di layar bayar).
                      if (tx.employeeName?.trim().isNotEmpty ?? false) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _pickEmployee,
                          child: Row(
                            children: [
                              Icon(Icons.badge_outlined,
                                  size: 14, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text('Pegawai: ',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant)),
                              Expanded(
                                child: Text(
                                  tx.employeeName!.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              Icon(Icons.edit_outlined,
                                  size: 12, color: scheme.primary),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Verifikasi serah-terima barang — kontrol kecil bergaya lingkaran
          // solid, persis ItemCountBadge (cuma warna hijau) sesuai desain
          // final yang disepakati user (PLAN.md Item 29).
          if (_items.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    final target = !_allChecked;
                    for (final i in _items) {
                      _checked[i.id] = target;
                    }
                  });
                  unawaited(_persistChecked());
                },
                child: Tooltip(
                  message: _allChecked ? 'Hapus Tanda' : 'Tandai Semua',
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.payGreen,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.payGreen.withOpacity(0.30),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _allChecked ? Icons.remove_done : Icons.done_all,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),

          // Items (varian bersarang di bawah induk, laba inline per item).
          // Badge jumlah item "menempel" di sudut kiri-atas kartu, sengaja
          // dirender di atasnya (Stack, bukan sejajar) via ItemCountBadge
          // elevated — sama gaya dgn badge cart bar kasir.
          Stack(
            clipBehavior: Clip.none,
            children: [
              Card(
                child: Column(
                  children: [
                    // Watermark status Lunas/Tempo — SAMAR, di BELAKANG baris
                    // item (bukan elemen mengambang di sudut) supaya nama &
                    // harga produk tidak pernah tertutup apapun panjang
                    // daftarnya. Desain final PLAN.md Item 29.
                    if (!isVoid)
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // TIDAK dibungkus Positioned.fill — itu memaksa
                          // tinggi watermark mengikuti tinggi Stack (bisa
                          // sependek 1 baris item), bikin teks 3-baris di
                          // dalamnya overflow. Sbg child non-positioned,
                          // watermark cuma dapat batas lebar dari Stack &
                          // bebas menentukan tinggi alaminya sendiri.
                          FractionallySizedBox(
                            widthFactor: 0.46,
                            child: StatusWatermarkStamp(
                              label: isKurangBayar ? 'TEMPO' : 'LUNAS',
                              serial: tx.localId,
                              color: isKurangBayar
                                  ? scheme.error
                                  : AppTheme.payGreen,
                            ),
                          ),
                          Column(
                            children: _buildItemRows(scheme,
                                showProfit:
                                    device.canSeeReports && _showProfit,
                                editable: isKurangBayar && !isVoid),
                          ),
                        ],
                      )
                    else
                      ..._buildItemRows(scheme,
                          showProfit: device.canSeeReports && _showProfit,
                          editable: isKurangBayar && !isVoid),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _SummaryRow('Total', formatRupiah(tx.total),
                              bold: true, color: scheme.primary),
                          if (device.canSeeReports && _showProfit)
                            _buildTotalProfitRow(scheme),
                          if (tx.paid > 0)
                            _SummaryRow('Dibayar',
                                '${_methodLabel(tx.paymentMethod)} · '
                                '${formatRupiah(netPaidDisplay(tx, _payments))}'),
                          // Item 9 — uang tender ASLI dari pembayaran TERAKHIR
                          // (gross, sebelum dikurangi kembalian) supaya tidak
                          // membingungkan pembeli yang kasih lebih ("bayar
                          // 300rb" padahal kasih 400rb). Cuma tampil kalau
                          // memang ada kembalian (kalau pas, "Dibayar" di atas
                          // sudah sama dengan uang diterima).
                          if ((_latestPayment?.changeGiven ?? 0) > 0)
                            _SummaryRow('Uang Diterima',
                                formatRupiah(_latestPayment!.amount)),
                          if ((_latestPayment?.changeGiven ?? 0) > 0)
                            _ChangeTakenRow(
                              amount:
                                  formatRupiah(_latestPayment!.changeGiven),
                              taken: _latestPayment!.changeTaken,
                              color: scheme.tertiary,
                              onChanged: isVoid
                                  ? null
                                  : (v) => _toggleChangeTaken(
                                      _latestPayment!.id, v),
                            ),
                          if (isKurangBayar)
                            _SummaryRow(
                              'Sisa Tagihan',
                              formatRupiah(netRemainingOwed(tx, _payments)),
                              color: scheme.error,
                              bold: true,
                            ),
                          if (tx.pointsEarned > 0)
                            _SummaryRow(
                                'Poin Didapat', '+${tx.pointsEarned} poin',
                                color: scheme.tertiary),
                        ],
                      ),
                    ),
                    // Catatan nota — di bawah total, dalam card yang sama
                    if (tx.strukNote?.isNotEmpty == true ||
                        (!isVoid && !isRetur)) ...[
                      const Divider(height: 1),
                      _buildStrukNoteBlock(scheme, tx,
                          editable: !isVoid && !isRetur),
                    ],
                  ],
                ),
              ),
              if (_items.isNotEmpty)
                Positioned(
                  left: 14,
                  top: -14,
                  child: ItemCountBadge(
                      count: _topLevelItems.length, elevated: true),
                ),
            ],
          ),

          // Catatan internal — card terpisah
          if (!isVoid && !isRetur) ...[
            const SizedBox(height: 8),
            _buildInternalNoteCard(scheme, tx),
          ],

          // Timeline pembayaran — kapan tiap cicilan/pelunasan masuk.
          if (_showPaymentTimeline) ...[
            const SizedBox(height: 8),
            _buildPaymentTimeline(scheme, isVoid: isVoid),
          ],
          const SizedBox(height: 20),

          if ((isKurangBayar && !isVoid) || (!isVoid && !isRetur)) ...[
            Row(
              children: [
                if (isKurangBayar && !isVoid)
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _showTambahBayar(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.changeBg(
                            Theme.of(context).brightness == Brightness.dark),
                        foregroundColor: AppTheme.changeFg(
                            Theme.of(context).brightness == Brightness.dark),
                      ),
                      child: const Text('Bayar'),
                    ),
                  ),
                if (isKurangBayar && !isVoid && !isRetur)
                  const SizedBox(width: 8),
                if (!isVoid && !isRetur)
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        await context.push('/kasir/tambah/${tx.id}');
                        if (mounted) _load();
                      },
                      icon: const Icon(Icons.add_shopping_cart_outlined,
                          size: 18),
                      label: const Text('Tambah Belanjaan'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (!isVoid && !isRetur)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showVoid(context),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Batalkan'),
                    style:
                        OutlinedButton.styleFrom(foregroundColor: scheme.error),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showReturSheet(context),
                    icon:
                        const Icon(Icons.assignment_return_outlined, size: 18),
                    label: const Text('Retur'),
                  ),
                ),
              ],
            ),
          if (isVoid)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, color: scheme.onErrorContainer, size: 18),
                  const SizedBox(width: 8),
                  Text('Transaksi ini telah dibatalkan',
                      style: TextStyle(color: scheme.onErrorContainer)),
                ],
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTotalProfitRow(ColorScheme scheme) {
    var totalLaba = 0;
    for (final item in _items) {
      final effQty = _itemEffQty(item);
      if (effQty <= 0) continue;
      totalLaba += ((item.priceAtSale - item.costAtSale) * effQty).round();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profitColor =
        isDark ? const Color(0xFF81C784) : const Color(0xFF388E3C);
    return _SummaryRow(
      totalLaba >= 0 ? 'Total Laba' : 'Total Rugi',
      formatRupiah(totalLaba.abs()),
      bold: true,
      color: totalLaba >= 0 ? profitColor : scheme.error,
    );
  }

  /// Catatan nota — di bawah total, dalam card yang sama.
  Widget _buildStrukNoteBlock(ColorScheme scheme, Transaction tx,
      {required bool editable}) {
    final hasNote = tx.strukNote?.isNotEmpty == true;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: editable ? _editStrukNote : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: hasNote
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_outlined,
                          size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('Catatan Nota',
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant)),
                      const Spacer(),
                      if (editable)
                        Icon(Icons.edit_outlined,
                            size: 12, color: scheme.primary),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _Blockquote(
                    text: tx.strukNote!,
                    color: scheme.primary.withOpacity(0.3),
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(Icons.receipt_outlined,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Tambah catatan nota…',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic)),
                  ),
                  if (editable)
                    Icon(Icons.edit_outlined, size: 12, color: scheme.primary),
                ],
              ),
      ),
    );
  }

  /// Catatan internal — card terpisah.
  Widget _buildInternalNoteCard(ColorScheme scheme, Transaction tx) {
    final isReturTx = tx.internalNote?.startsWith('RETUR:') ?? false;
    if (isReturTx) return const SizedBox.shrink();
    final hasNote = tx.internalNote?.isNotEmpty == true;
    return Card(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _editInternalNote,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: hasNote
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.note_outlined,
                            size: 13, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('Catatan Internal',
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                        const Spacer(),
                        Icon(Icons.edit_outlined,
                            size: 12, color: scheme.primary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _Blockquote(
                      text: tx.internalNote!,
                      color: scheme.tertiary.withOpacity(0.3),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(Icons.note_outlined,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Tambah catatan internal…',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic)),
                    ),
                    Icon(Icons.edit_outlined, size: 12, color: scheme.primary),
                  ],
                ),
        ),
      ),
    );
  }

  /// Kartu riwayat pembayaran: tiap baris = waktu + metode + nominal.
  Widget _buildPaymentTimeline(ColorScheme scheme, {required bool isVoid}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Riwayat Pembayaran',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            for (final p in _payments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(_formatDateTime(p.paidAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                  decoration: p.voided
                                      ? TextDecoration.lineThrough
                                      : null)),
                        ),
                        const SizedBox(width: 8),
                        Text(_methodLabel(p.method),
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                                decoration: p.voided
                                    ? TextDecoration.lineThrough
                                    : null)),
                        const SizedBox(width: 8),
                        Text(formatRupiah(p.amount),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: p.voided ? scheme.onSurfaceVariant : null,
                                decoration: p.voided
                                    ? TextDecoration.lineThrough
                                    : null)),
                        if (!p.voided && !isVoid)
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            tooltip: 'Batalkan Pembayaran',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            color: scheme.error,
                            onPressed: () => _voidPayment(p),
                          ),
                      ],
                    ),
                    if (p.voided)
                      Text('Dibatalkan',
                          style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: scheme.error)),
                    // Kembalian milik pembayaran INI (bukan akumulatif) —
                    // nempel langsung di bawah nominalnya, satu momen yang
                    // sama (lihat AppDatabase._computePaymentChangeGiven).
                    // Pembayaran yang dibatalkan tidak punya kembalian
                    // relevan lagi (sudah tidak dihitung finansial).
                    if (p.changeGiven > 0 && !p.voided)
                      _ChangeTakenRow(
                        amount: formatRupiah(p.changeGiven),
                        taken: p.changeTaken,
                        color: scheme.tertiary,
                        onChanged: isVoid
                            ? null
                            : (v) => _toggleChangeTaken(p.id, v),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tampilan struk gaya kertas thermal (putih, monospace) untuk
/// di-capture sebagai gambar dan dibagikan.
class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({
    required this.tx,
    required this.items,
    required this.payments,
    required this.productNames,
    required this.unitNames,
    required this.customerName,
    this.customerAddress = '',
    this.employeeName = '',
    required this.storeName,
    required this.storeAddress,
    required this.storePhone,
    this.storeWhatsapp = '',
    this.storeTelegram = '',
    this.receiptHeader = '',
    this.parentOf = const {},
    this.checkedIds = const {},
  });

  final Transaction tx;
  final List<TransactionItem> items;
  final List<TransactionPayment> payments;
  final Map<String, String> productNames;
  final Map<String, String> unitNames;
  final Map<String, String?> parentOf;
  final String customerName;
  final String customerAddress;
  final String employeeName;
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String storeWhatsapp;
  final String storeTelegram;
  final String receiptHeader;
  final Set<String> checkedIds;

  static const _ink = Color(0xFF111111);
  // Item 7 — 'monospace' generik resolve ke font DEFAULT OS yang beda-beda
  // per merek/versi Android (tablet vs HP bisa beda glyph) → tampilan struk
  // share tidak konsisten. Pin font eksplisit (sama mekanisme dgn Hanken
  // Grotesk/Newsreader di AppTheme) supaya identik di semua device.
  static TextStyle get _mono =>
      GoogleFonts.robotoMono(fontSize: 12, color: _ink, height: 1.4);

  TransactionItem? _parentItemOf(TransactionItem item) {
    final pid = parentOf[item.productId];
    if (pid == null) return null;
    for (final it in items) {
      if (it.productId == pid && parentOf[it.productId] == null) return it;
    }
    return null;
  }

  /// Item terurut: induk diikuti varian-variannya.
  List<TransactionItem> get _ordered {
    final out = <TransactionItem>[];
    for (final it in items) {
      if (_parentItemOf(it) == null) {
        out.add(it);
        for (final c in items) {
          if (_parentItemOf(c)?.id == it.id) out.add(c);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final remaining = netRemainingOwed(tx, payments);
    final date =
        '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year} '
        '${tx.createdAt.hour.toString().padLeft(2, '0')}:${tx.createdAt.minute.toString().padLeft(2, '0')}';

    return Container(
      width: 300,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(storeName.toUpperCase(),
              textAlign: TextAlign.center,
              style: _mono.copyWith(fontSize: 16, fontWeight: FontWeight.w900)),
          if (storeAddress.isNotEmpty)
            Text(storeAddress,
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (storePhone.isNotEmpty)
            Text('Telp: $storePhone',
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (storeWhatsapp.isNotEmpty)
            Text('WA: $storeWhatsapp',
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (storeTelegram.isNotEmpty)
            Text('Telegram: $storeTelegram',
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          if (receiptHeader.isNotEmpty)
            Text(receiptHeader,
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          const _DashedLine(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(date, style: _mono),
              Text('#${shortTxNo(tx.localId)}', style: _mono),
            ],
          ),
          Text(customerName,
              style: _mono.copyWith(fontSize: 16, fontWeight: FontWeight.w900)),
          if (customerAddress.isNotEmpty)
            Text(customerAddress, style: _mono.copyWith(fontSize: 11)),
          const _DashedLine(),
          ..._ordered.expand((item) {
            final isVar = _parentItemOf(item) != null;
            final pad = isVar ? '  ' : '';
            final mark = checkedIds.contains(item.id) ? '✓ ' : '';
            final namePrefix = isVar ? '$pad└ ' : '';
            // transaction_items selalu menyimpan qty efektif — jangan
            // dikurangi qty varian lagi (double-subtract membuat induk yang
            // dijual bersama varian tampil kosong).
            final effQty = item.qty;
            final isPlaceholder = !isVar && effQty == 0;
            final qtyStr =
                effQty % 1 == 0 ? effQty.toInt().toString() : effQty.toString();
            return [
              Text('$mark$namePrefix${productNames[item.productId] ?? ''}',
                  style: _mono.copyWith(
                      fontWeight: isVar ? FontWeight.w400 : FontWeight.w700)),
              if (!isPlaceholder)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Jumlah qty + satuan di-bold (biar mudah dibaca), tapi
                    // TIDAK lebih tebal dari nama produk (w700 utk induk, w400
                    // utk varian). Bagian "x harga" tetap berat normal.
                    Text.rich(
                      TextSpan(
                        style: _mono,
                        children: [
                          TextSpan(
                            text:
                                '$pad$qtyStr ${unitNames[item.productUnitId] ?? ''}',
                            style: _mono.copyWith(
                                fontWeight: isVar
                                    ? FontWeight.w400
                                    : FontWeight.w600),
                          ),
                          TextSpan(
                              text: ' x ${_fmtNum(item.priceAtSale)}'),
                        ],
                      ),
                    ),
                    Text(_fmtNum((item.priceAtSale * effQty).round()),
                        style: _mono),
                  ],
                ),
              if (item.itemNote != null)
                Text('$pad* ${item.itemNote}',
                    style: _mono.copyWith(
                        fontSize: 11, fontStyle: FontStyle.italic)),
            ];
          }),
          const _DashedLine(),
          // Pegawai (di atas jumlah produk). "Pegawai: " normal, nama bold.
          if (employeeName.trim().isNotEmpty)
            Text.rich(
              TextSpan(
                style: _mono,
                children: [
                  const TextSpan(text: 'Pegawai: '),
                  TextSpan(
                      text: employeeName.trim(),
                      style: _mono.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          Text('Produk: ${items.length}', style: _mono),
          const _DashedLine(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: _mono.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w900)),
              Text('Rp ${_fmtNum(tx.total)}',
                  style: _mono.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
          if (netPaidDisplay(tx, payments) > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bayar..', style: _mono),
                Text('Rp ${_fmtNum(netPaidDisplay(tx, payments))}',
                    style: _mono),
              ],
            ),
          if (latestChangeGiven(payments) > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Kembali',
                    style: _mono.copyWith(
                        fontSize: 14, fontWeight: FontWeight.w900)),
                Text('Rp ${_fmtNum(latestChangeGiven(payments))}',
                    style: _mono.copyWith(
                        fontSize: 14, fontWeight: FontWeight.w900)),
              ],
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              remaining <= 0
                  ? 'Sudah bayar'
                  : 'Sisa hutang Rp ${_fmtNum(remaining)}',
              style: _mono,
            ),
          ),
          // Timeline pembayaran (mis. hutang dilunasi belakangan / dicicil).
          if (_showTimeline) ...[
            const _DashedLine(),
            Text('Pembayaran:',
                style: _mono.copyWith(fontWeight: FontWeight.w700)),
            ...payments.map((p) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                          '${_fmtDateTime(p.paidAt)} ${_methodShort(p.method)}',
                          style: _mono.copyWith(fontSize: 11)),
                    ),
                    Text('Rp ${_fmtNum(p.amount)}',
                        style: _mono.copyWith(fontSize: 11)),
                  ],
                )),
          ],
          if (tx.strukNote != null) ...[
            const _DashedLine(),
            Text(tx.strukNote!,
                textAlign: TextAlign.center,
                style: _mono.copyWith(fontSize: 11)),
          ],
          const _DashedLine(),
          Text('Terima kasih!',
              textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  bool get _showTimeline {
    if (payments.length > 1) return true;
    if (payments.length == 1) return payments.first.paidAt != tx.createdAt;
    return false;
  }

  String _fmtDateTime(DateTime dt) => '${dt.day}/${dt.month} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _methodShort(String m) => switch (m) {
        'tunai' => 'Tunai',
        'transfer' => 'Transfer',
        'qris' => 'QRIS',
        'ewallet' => 'E-Wallet',
        _ => m,
      };

  String _fmtNum(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// Pembatas "Tambahan <jam>" untuk item susulan (hanya struk in-app).
class _AddedSeparator extends StatelessWidget {
  const _AddedSeparator({required this.time, required this.scheme});
  final String time;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: scheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Tambahan $time',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  const _DashedLine();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final count = (constraints.maxWidth / 7).floor();
          return Text(
            List.filled(count, '-').join(),
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: GoogleFonts.robotoMono(
                fontSize: 12, color: const Color(0xFF777777)),
          );
        },
      ),
    );
  }
}

class _Blockquote extends StatelessWidget {
  const _Blockquote({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(width: 3, color: color)),
        color: color.withOpacity(0.08),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, height: 1.3)),
    );
  }
}

/// Baris "Kembalian" dengan checkbox "sudah diambil" — mencegah kembalian
/// diserahkan dua kali pada nota yang barangnya diambil belakangan.
class _ChangeTakenRow extends StatelessWidget {
  const _ChangeTakenRow({
    required this.amount,
    required this.taken,
    required this.color,
    required this.onChanged,
  });

  final String amount;
  final bool taken;
  final Color color;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!taken),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: taken,
                    onChanged: onChanged == null
                        ? null
                        : (v) => onChanged!(v ?? false),
                  ),
                ),
                const SizedBox(width: 2),
                Text('Kembalian', style: TextStyle(color: color)),
              ],
            ),
            Text(amount, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(
    this.label,
    this.value, {
    this.bold = false,
    this.color,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                  color: color)),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                  color: color)),
        ],
      ),
    );
  }
}
