import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/models/cart_item.dart';
import '../../core/providers/device_provider.dart';
import '../../core/providers/low_stock_alert_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_formatters.dart';
import 'cart_meta_provider.dart';
import 'discount_allocation.dart';
import 'cart_provider.dart';
import 'receipt_screen.dart' show netRemainingOwed;

const _uuid = Uuid();

/// C-5: apakah transaksi ini boleh lanjut walau stok kurang. Owner SELALU
/// boleh (konsisten dengan izin lain — override harga, input stok, dst —
/// yang semuanya tanpa syarat untuk owner). Asisten butuh izin eksplisit
/// `asisten_stok_minus`. Kasir mengikuti setting global `allow_negative_stock`.
/// Diekstrak dari `_confirm()` supaya bisa diuji langsung tanpa perlu
/// mendorong seluruh alur widget PaymentScreen.
Future<bool> resolveAllowNegativeStock(
    AppDatabase db, DeviceIdentity device) async {
  if (device.isOwner) return true;
  var allow = (await db.getSetting('allow_negative_stock')) == '1';
  if (!allow && device.deviceRole == 'asisten') {
    allow = await db.isPermissionEnabled('asisten_stok_minus');
  }
  return allow;
}

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, this.addToTxId});

  /// Bila terisi, layar bayar berada dalam mode "bayar selisih" untuk
  /// transaksi [addToTxId] — menambah item ke transaksi yang sudah ada.
  final String? addToTxId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String get _cartId => widget.addToTxId ?? kMainCartId;
  bool get _isAddMode => widget.addToTxId != null;
  String _selectedMethodId = 'pm-tunai';
  String _selectedMethodType = 'tunai';

  /// Uang diterima (tunai), diinput via keypad.
  int _tendered = 0;

  /// Override total (diskon manual / pembulatan). null = pakai total keranjang.
  int? _totalOverride;

  // Customer state
  Customer? _selectedCustomer;
  String _custNameManual = '';
  bool _custDropdownOpen = false;
  List<Customer> _custSuggestions = [];
  Map<String, (int, int)> _custDebts = {};
  final _custCtrl = TextEditingController();
  // Untuk menggulir field pelanggan ke atas viewport agar dropdown saran tidak
  // tertutup keyboard saat mengetik.
  final _custFieldKey = GlobalKey();

  List<PaymentMethod> _methods = [];
  bool _isSaving = false;

  // Pegawai yang melayani — dipilih dari daftar (modal sheet, tanpa keyboard).
  List<Employee> _employees = [];
  Employee? _selectedEmployee;

  /// Mode tambah belanjaan: kembalian pembayaran terakhir transaksi asli,
  /// bila masih belum diambil — ditampilkan sebagai info di kalkulator bayar
  /// (Poin 1) supaya kasir tahu ada uang kembalian yang bisa dipakai untuk
  /// item susulan. Murni informasi + centang manual, TIDAK memengaruhi
  /// jumlah yang diinput kasir (kasir tetap input manual, konsisten dengan
  /// simulasi fisik: kembalian sudah diberikan, pelanggan bayar lagi pakai
  /// uang itu).
  ({String id, int amount})? _unclaimedChange;
  bool _unclaimedChangeTaken = false;

  /// Mode tambah belanjaan: sisa tagihan nota ASLI (sebelum item susulan
  /// ini), bila nota itu masih kurang bayar. `_total`/kalkulator kasir
  /// SENGAJA tidak digabung dengan angka ini (bisa merusak alokasi
  /// diskon/pembulatan per-item lewat `allocateCartTotal`) — murni info
  /// terpisah supaya kasir tidak terkecoh "Total" kalkulator itu HANYA
  /// harga item baru, bukan total yang perlu ditagih ke pelanggan.
  int? _existingShortfall;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final methods = await (db.select(db.paymentMethods)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    final employees = await db.getEmployees();

    // Pra-isi pelanggan & pegawai dari metadata keranjang (dipilih di cart bar
    // kasir). Mode tambah belanjaan mengikuti transaksi asli → tidak pra-isi.
    final meta =
        _isAddMode ? const CartMeta() : ref.read(cartMetaProvider(_cartId));
    Customer? preCustomer;
    Map<String, (int, int)> preDebts = {};
    if (meta.customerId != null) {
      preCustomer = await (db.select(db.customers)
            ..where((t) => t.id.equals(meta.customerId!)))
          .getSingleOrNull();
      if (preCustomer != null) {
        preDebts[preCustomer.id] =
            await db.getCustomerOutstandingDebt(preCustomer.id);
      }
    }
    Employee? preEmployee;
    if (meta.employeeId != null) {
      for (final e in employees) {
        if (e.id == meta.employeeId) {
          preEmployee = e;
          break;
        }
      }
    }

    ({String id, int amount})? unclaimedChange;
    int? existingShortfall;
    if (_isAddMode) {
      final origTx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(widget.addToTxId!)))
          .getSingleOrNull();
      if (origTx != null) {
        final origPayments = await db.getPaymentsForTx(widget.addToTxId!);
        final lastPay = origPayments.isEmpty ? null : origPayments.last;
        if (lastPay != null &&
            lastPay.changeGiven > 0 &&
            !lastPay.changeTaken) {
          unclaimedChange = (id: lastPay.id, amount: lastPay.changeGiven);
        }
        final shortfall = netRemainingOwed(origTx, origPayments);
        if (shortfall > 0) existingShortfall = shortfall;
      }
    }

    if (mounted) {
      setState(() {
        _methods = methods;
        _employees = employees;
        _unclaimedChange = unclaimedChange;
        _unclaimedChangeTaken = false;
        _existingShortfall = existingShortfall;
        if (methods.isNotEmpty) {
          _selectedMethodId = methods.first.id;
          _selectedMethodType = methods.first.type;
        }
        if (preCustomer != null) {
          _selectedCustomer = preCustomer;
          _custCtrl.text = preCustomer.name;
          _custDebts = preDebts;
        } else if (meta.customerName != null && meta.customerName!.isNotEmpty) {
          // Nama manual tanpa record pelanggan.
          _custNameManual = meta.customerName!;
          _custCtrl.text = meta.customerName!;
        }
        _selectedEmployee = preEmployee;
      });
    }
  }

  /// Centang "Pakai kembalian" di kalkulator bayar (mode tambah belanjaan) —
  /// menulis langsung ke baris pembayaran sumbernya, aksi yang SAMA persis
  /// dengan centang kembalian di Ringkasan struk (lihat receipt_screen.dart
  /// `_toggleChangeTaken`). Murni penanda "sudah dipakai/diambil", tidak
  /// memengaruhi jumlah yang diinput kasir.
  Future<void> _toggleUnclaimedChangeTaken(bool value) async {
    final change = _unclaimedChange;
    if (change == null) return;
    final db = ref.read(databaseProvider);
    await (db.update(db.transactionPayments)
          ..where((t) => t.id.equals(change.id)))
        .write(TransactionPaymentsCompanion(changeTaken: Value(value)));
    if (mounted) setState(() => _unclaimedChangeTaken = value);
  }

  /// Tulis balik pilihan pelanggan/pegawai ke metadata keranjang agar tetap
  /// konsisten bila pengguna kembali ke layar kasir. Tidak untuk mode tambah
  /// belanjaan (keranjang susulan tidak menyimpan pelanggan).
  void _syncMetaCustomer() {
    if (_isAddMode) return;
    ref.read(cartMetaProvider(_cartId).notifier).setCustomer(
          _selectedCustomer?.id,
          _selectedCustomer?.name ??
              (_custNameManual.trim().isEmpty ? null : _custNameManual.trim()),
        );
  }

  void _syncMetaEmployee() {
    if (_isAddMode) return;
    ref
        .read(cartMetaProvider(_cartId).notifier)
        .setEmployee(_selectedEmployee?.id, _selectedEmployee?.name);
  }

  /// Pilih pegawai via modal sheet — tanpa keyboard sehingga tidak menutupi
  /// field lain. Mengembalikan pilihan (atau membersihkan bila "Tanpa pegawai").
  Future<void> _pickEmployee() async {
    FocusScope.of(context).unfocus();
    final scheme = Theme.of(context).colorScheme;
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
                  Text('Pilih Pegawai',
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
                      child: Text(
                        'Belum ada pegawai. Tambah lewat "Kelola".',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
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
                        trailing: _selectedEmployee?.id == e.id
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
    if (result == null) return; // dibatalkan (dismiss)
    setState(() {
      _selectedEmployee = result is Employee ? result : null;
    });
    _syncMetaEmployee();
  }

  Future<void> _searchCustomers(String q) async {
    if (q.isEmpty) {
      setState(() {
        _custSuggestions = [];
        _custDropdownOpen = false;
      });
      return;
    }
    final db = ref.read(databaseProvider);
    final results = await db.searchCustomers(q);
    // Ambil hutang akumulatif per pelanggan untuk ditampilkan di dropdown.
    final debts = <String, (int, int)>{};
    for (final c in results) {
      debts[c.id] = await db.getCustomerOutstandingDebt(c.id);
    }
    if (mounted) {
      setState(() {
        _custSuggestions = results;
        _custDebts = debts;
        _custDropdownOpen = results.isNotEmpty;
      });
      if (_custDropdownOpen) _scrollCustIntoView(delayMs: 50);
    }
  }

  /// Gulir field pelanggan ke atas viewport agar field + dropdown saran tampak
  /// di atas keyboard. Diberi sedikit delay agar keyboard sempat terpasang.
  void _scrollCustIntoView({int delayMs = 0}) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      final ctx = _custFieldKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  int get _cartTotal => ref.read(cartProvider(_cartId).notifier).totalAmount;

  int get _total => _totalOverride ?? _cartTotal;

  int get _paid => _selectedMethodType == 'tunai' ? _tendered : _total;

  int get _change => (_paid - _total).clamp(0, double.maxFinite.toInt());

  Future<void> _editTotal() async {
    final ctrl =
        TextEditingController(text: ThousandsSeparatorFormatter.format(_total));
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Total'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total keranjang: ${formatRupiah(_cartTotal)}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            const Text('Untuk diskon manual / pembulatan.',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: const [ThousandsSeparatorFormatter()],
              decoration: const InputDecoration(
                  prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          if (_totalOverride != null)
            TextButton(
              onPressed: () => ctx.pop(-1),
              child: const Text('Reset'),
            ),
          TextButton(onPressed: () => ctx.pop(), child: const Text('Batal')),
          FilledButton(
            onPressed: () =>
                ctx.pop(ThousandsSeparatorFormatter.parseValue(ctrl.text)),
            child: const Text('Terapkan'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      _totalOverride = result == -1 ? null : result.clamp(0, 99999999);
    });
  }

  Future<void> _confirm() async {
    if (_isSaving) return;
    final cart = ref.read(cartProvider(_cartId));
    if (cart.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);

      // C-5: Cek stok sebelum transaksi jika setting "izinkan stok minus" OFF.
      final device = ref.read(deviceProvider);
      final allowNegative = await resolveAllowNegativeStock(db, device);
      if (!allowNegative) {
        final notifier = ref.read(cartProvider(_cartId).notifier);
        final shortages = <String>[];
        for (final item in cart) {
          final effQty = notifier.effectiveQtyFor(item);
          if (effQty <= 0) continue;
          // Lewati unit non-stok (varian/jasa) — stoknya memang tidak dilacak.
          final unit = await (db.select(db.productUnits)
                ..where((t) => t.id.equals(item.productUnitId)))
              .getSingleOrNull();
          if (unit?.isNonStock ?? false) continue;
          final stock = await db.currentStock(item.productUnitId);
          if (stock < effQty) {
            shortages.add(
                '${item.productName}: stok ${stock % 1 == 0 ? stock.toInt() : stock}, butuh ${effQty % 1 == 0 ? effQty.toInt() : effQty}');
          }
        }
        if (shortages.isNotEmpty && mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Stok tidak cukup:\n${shortages.join('\n')}'),
            duration: const Duration(seconds: 4),
          ));
          return;
        }
      }
      // Mode tambah belanjaan: tambahkan item ke transaksi yang sudah ada,
      // bukan membuat transaksi baru.
      if (_isAddMode) {
        await _confirmAddItems(db, cart);
        return;
      }

      final notifier = ref.read(cartProvider(_cartId).notifier);
      final now = DateTime.now();

      // Item 55 — pakai nomor yang SUDAH direservasi sejak keranjang mulai
      // diisi/ditahan (stabil, sama dgn yg tampil di cart bar/kartu
      // tertahan/QR transfer) — bukan generate baru di sini. Fallback ke
      // `generateUniqueLocalId` HANYA kalau entah bagaimana belum sempat
      // direservasi (seharusnya tidak terjadi di alur normal).
      final reservedId = ref.read(cartMetaProvider(_cartId)).reservedLocalId;
      final localId = reservedId ??
          await db.generateUniqueLocalId(device.deviceCode, now);

      final isTempo = _selectedMethodType == 'tempo';
      final paidAmount = isTempo ? 0 : _paid;
      final status =
          isTempo ? 'tempo' : (paidAmount < _total ? 'kurang_bayar' : 'lunas');

      // Customer resolution
      final customerId = _selectedCustomer?.id;
      final customerName = _selectedCustomer == null
          ? (_custNameManual.trim().isEmpty ? null : _custNameManual.trim())
          : null;

      // Loyalty points — dihitung dari total transaksi (bukan jumlah yang
      // sudah dibayar), berlaku SAMA utk tempo maupun tunai/langsung lunas.
      // Aturan: setiap kelipatan [threshold] rupiah → [pointsPer] poin.
      // Tempo TIDAK dikecualikan lagi (dulu poin selalu 0 utk tempo walau
      // total melebihi threshold) — kalau transaksi ini nanti di-void,
      // `voidTransaction` sudah generik membalikkan poin berdasarkan
      // `pointsEarned` tersimpan, tidak peduli payment method-nya.
      int pointsEarned = 0;
      final loyaltyThreshold =
          int.tryParse(await db.getSetting('loyalty_point_threshold') ?? '') ??
              0;
      final loyaltyPointsPer =
          int.tryParse(await db.getSetting('loyalty_points_per') ?? '') ?? 1;
      if (customerId != null && loyaltyThreshold > 0) {
        pointsEarned = (_total / loyaltyThreshold).floor() *
            (loyaltyPointsPer < 1 ? 1 : loyaltyPointsPer);
      }

      final txId = _uuid.v4();

      // Effective qty memakai satu sumber kebenaran di cart provider (A-13).
      double effQty(CartItem item) => notifier.effectiveQtyFor(item);

      // Bila total di-override manual (diskon), alokasikan selisihnya secara
      // proporsional ke tiap baris agar Σ subtotal == total tersimpan dan
      // struk konsisten. HPP (costAtSale) tidak diutak-atik → laba akurat.
      // Lewati item induk placeholder (effectiveQty == 0) — ditangani di
      // dalam allocateCartTotal.
      final allocatedLines = allocateCartTotal(
        items: cart,
        effectiveQtyOf: effQty,
        total: _total,
        cartTotal: _cartTotal,
      );

      // Item baru diteruskan ke `checkedItemIds` transaksi bila sudah
      // dicentang di keranjang (checklist verifikasi sebelum bayar) — Struk
      // melanjutkan dari titik yang sama, bukan mulai dari nol.
      final checkedTxItemIds = <String>[];
      final itemCompanions = <TransactionItemsCompanion>[
        for (final l in allocatedLines)
          () {
            final id = _uuid.v4();
            if (l.item.checked) checkedTxItemIds.add(id);
            return TransactionItemsCompanion.insert(
              id: id,
              transactionId: txId,
              productId: l.item.productId,
              productUnitId: l.item.productUnitId,
              qty: l.effectiveQty,
              priceAtSale: l.unitPrice,
              originalPrice: l.item.originalPrice,
              priceOverridden: Value(l.priceOverridden),
              costAtSale: Value(l.item.costPrice),
              itemNote: Value(l.item.itemNote),
              subtotal: l.subtotal,
            );
          }(),
      ];

      final txCompanion = TransactionsCompanion.insert(
        id: txId,
        localId: localId,
        kasirId: Value(device.deviceCode),
        customerId: Value(customerId),
        customerName: Value(customerName),
        status: status,
        total: _total,
        paid: paidAmount,
        changeAmount: _change,
        paymentMethod: _selectedMethodType,
        employeeName: Value(_selectedEmployee?.name),
        pointsEarned: Value(pointsEarned),
        createdAt: Value(now),
        checkedItemIds: checkedTxItemIds.isEmpty
            ? const Value.absent()
            : Value(jsonEncode(checkedTxItemIds)),
      );

      final paymentCompanions = paidAmount > 0
          ? [
              TransactionPaymentsCompanion.insert(
                id: _uuid.v4(),
                transactionId: txId,
                amount: paidAmount,
                method: _selectedMethodType,
                paidAt: Value(now),
                kasirId: Value(device.deviceCode),
                // Transaksi baru → tidak ada pembayaran sebelumnya, jadi
                // kembalian pembayaran ini = kembalian keseluruhan (_change).
                changeGiven: Value(_change),
              ),
            ]
          : <TransactionPaymentsCompanion>[];

      // Stock items — only deduct stock for items with effective qty > 0.
      final stockItems = cart
          .where((item) => effQty(item) > 0)
          .map((item) => (
                productUnitId: item.productUnitId,
                qty: effQty(item),
                note: localId,
              ))
          .toList();

      LoyaltyPointLedgerCompanion? loyaltyEntry;
      if (customerId != null && pointsEarned > 0) {
        loyaltyEntry = LoyaltyPointLedgerCompanion.insert(
          id: _uuid.v4(),
          customerId: customerId,
          type: 'earn',
          points: pointsEarned,
          note: Value(localId),
          createdAt: Value(now),
        );
      }

      await db.saveTransaction(
        tx: txCompanion,
        items: itemCompanions,
        payments: paymentCompanions,
        stockItems: stockItems,
        now: now,
        loyaltyEntry: loyaltyEntry,
      );
      // Item 55 — nomor sudah "dikonsumsi" jadi transaction.local_id
      // sungguhan, lepaskan dari reservasi (kalau memang berasal dari
      // reservasi, bukan fallback generateUniqueLocalId).
      if (reservedId != null) await db.releaseLocalId(reservedId);

      // Item 46 — peringatan stok menipis dari produk yang baru terjual,
      // disimpan untuk ditampilkan sbg banner saat pengguna kembali ke kasir
      // (setelah alur struk), bukan sekarang (masih di layar bayar/struk).
      final soldProductIds = cart
          .where((item) => effQty(item) > 0)
          .map((item) => item.productId)
          .toSet();
      final lowStock = await db.lowStockAlertsForProducts(soldProductIds);
      if (lowStock.isNotEmpty) {
        ref.read(pendingLowStockAlertsProvider.notifier).state = lowStock;
      }

      ref.read(cartProvider(_cartId).notifier).clear();
      ref.read(cartMetaProvider(_cartId).notifier).clear();
      if (mounted) {
        context.pushReplacement('/kasir/struk/$txId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Konfirmasi tambah belanjaan: bangun item susulan dari keranjang lalu
  /// panggil [AppDatabase.addItemsToTransaction]. Pelanggan/pegawai mengikuti
  /// transaksi asli (tidak diubah). Total selisih dibayar via metode terpilih.
  Future<void> _confirmAddItems(AppDatabase db, List<CartItem> cart) async {
    final device = ref.read(deviceProvider);
    final notifier = ref.read(cartProvider(_cartId).notifier);
    final now = DateTime.now();
    final txId = widget.addToTxId!;

    final isTempo = _selectedMethodType == 'tempo';
    final paidAmount = isTempo ? 0 : _paid;

    double effQty(CartItem item) => notifier.effectiveQtyFor(item);

    // Alokasi diskon proporsional bila total selisih di-override.
    final allocatedLines = allocateCartTotal(
      items: cart,
      effectiveQtyOf: effQty,
      total: _total,
      cartTotal: _cartTotal,
    );

    final itemCompanions = <TransactionItemsCompanion>[
      for (final l in allocatedLines)
        TransactionItemsCompanion.insert(
          id: _uuid.v4(),
          transactionId: txId,
          productId: l.item.productId,
          productUnitId: l.item.productUnitId,
          qty: l.effectiveQty,
          priceAtSale: l.unitPrice,
          originalPrice: l.item.originalPrice,
          priceOverridden: Value(l.priceOverridden),
          costAtSale: Value(l.item.costPrice),
          itemNote: Value(l.item.itemNote),
          subtotal: l.subtotal,
        ),
    ];

    final stockItems = cart
        .where((item) => effQty(item) > 0)
        .map((item) => (
              productUnitId: item.productUnitId,
              qty: effQty(item),
              note: 'tambah',
            ))
        .toList();

    final payment = paidAmount > 0
        ? TransactionPaymentsCompanion.insert(
            id: _uuid.v4(),
            transactionId: txId,
            amount: paidAmount,
            method: _selectedMethodType,
            paidAt: Value(now),
            kasirId: Value(device.deviceCode),
            note: const Value('Tambah belanjaan'),
          )
        : null;

    await db.addItemsToTransaction(
      txId: txId,
      items: itemCompanions,
      stockItems: stockItems,
      payment: payment,
      kasirId: device.deviceCode,
    );

    // Bug dilaporkan user: poin loyalitas tidak ikut bertambah saat tambah
    // belanjaan menaikkan total nota — `awardLoyaltyPointsIfEligible` sudah
    // dibuat kumulatif (selisih target vs pointsEarned tersimpan), tinggal
    // dipanggil lagi di sini dengan total yang sudah termasuk item susulan.
    final updatedTx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingleOrNull();
    if (updatedTx?.customerId != null) {
      await db.awardLoyaltyPointsIfEligible(
          txId: txId, customerId: updatedTx!.customerId!);
    }

    notifier.clear();
    ref.read(cartMetaProvider(_cartId).notifier).clear();
    if (mounted) {
      // Pop kembali ke ReceiptScreen (bukan context.go) agar await
      // context.push() di ReceiptScreen ter-resolve dan _load() dipanggil.
      // context.go me-reuse widget dengan page key sama tanpa initState.
      var count = 0;
      Navigator.of(context).popUntil((_) {
        if (count >= 2) return true;
        count++;
        return false;
      });
    }
  }

  @override
  void dispose() {
    _custCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider(_cartId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isAddMode ? 'Bayar Selisih' : 'Pembayaran')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Order summary
                Card(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          children: [
                            Text('Ringkasan Pesanan',
                                style: Theme.of(context).textTheme.titleSmall),
                            const Spacer(),
                            Text('${cart.length} item',
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      ...() {
                        // effectiveQty helper for display (same logic as transaction save)
                        double itemEffQty(CartItem item) {
                          if (item.isVariant) return item.qty;
                          final varSum = cart
                              .where((c) =>
                                  c.isVariant &&
                                  c.parentProductId == item.productId)
                              .fold(0.0, (s, c) => s + c.qty);
                          return (item.qty - varSum)
                              .clamp(0.0, double.infinity);
                        }

                        return orderCartItems(cart).map((item) {
                          final eq = itemEffQty(item);
                          final isPlaceholder = !item.isVariant && eq == 0;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.only(
                                left: item.isVariant ? 32 : 16, right: 16),
                            title: Row(
                              children: [
                                if (item.isVariant)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(Icons.subdirectory_arrow_right,
                                        size: 13,
                                        color: scheme.onSurfaceVariant),
                                  ),
                                Expanded(
                                  child: Text(item.productName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: item.isVariant
                                              ? scheme.onSurfaceVariant
                                              : null)),
                                ),
                              ],
                            ),
                            subtitle: isPlaceholder
                                ? Text('via varian',
                                    style: TextStyle(
                                        fontSize: 11, color: scheme.primary))
                                : Text(
                                    '${item.unitName} × ${eq % 1 == 0 ? eq.toInt() : eq}',
                                    style: const TextStyle(fontSize: 11)),
                            trailing: isPlaceholder
                                ? null
                                : Text(formatRupiah((item.price * eq).round()),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                          );
                        });
                      }(),
                      const Divider(height: 1),
                      InkWell(
                        onTap: _editTotal,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Text('Total',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 6),
                                  Icon(Icons.edit,
                                      size: 13, color: scheme.tertiary),
                                  const Spacer(),
                                  Text(
                                    formatRupiah(_total),
                                    style: TextStyle(
                                        color: _totalOverride != null
                                            ? scheme.tertiary
                                            : scheme.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16),
                                  ),
                                ],
                              ),
                              if (_totalOverride != null)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Asli ${formatRupiah(_cartTotal)} · diubah manual',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant,
                                          fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Pelanggan & pegawai mengikuti transaksi asli saat tambah
                // belanjaan — tidak ditampilkan/diubah di mode bayar selisih.
                if (!_isAddMode) ...[
                  // Pelanggan & Pegawai sejajar — dua kartu bersebelahan,
                  // masing2 lebih ringkas drpd ditumpuk vertikal. Dropdown
                  // saran pelanggan & peringatan hutang tetap muat di setengah
                  // lebar sendiri (lihat komentar di Expanded pelanggan).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Customer picker
                            Text('Pelanggan',
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_selectedCustomer != null) ...[
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor:
                                                scheme.primaryContainer,
                                            child: Text(
                                              (_selectedCustomer!.name.isEmpty
                                                      ? '?'
                                                      : _selectedCustomer!
                                                          .name[0])
                                                  .toUpperCase(),
                                              style: TextStyle(
                                                  color:
                                                      scheme.onPrimaryContainer,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(_selectedCustomer!.name,
                                                style: TextStyle(
                                                    color: scheme.primary)),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close,
                                                size: 18),
                                            onPressed: () {
                                              setState(() {
                                                _selectedCustomer = null;
                                                _custCtrl.clear();
                                                _custNameManual = '';
                                              });
                                              _syncMetaCustomer();
                                            },
                                          ),
                                        ],
                                      ),
                                      if ((_custDebts[_selectedCustomer!.id]
                                                  ?.$1 ??
                                              0) >
                                          0)
                                        Container(
                                          margin: const EdgeInsets.only(top: 8),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: scheme.errorContainer,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.warning_amber_rounded,
                                                  size: 16,
                                                  color:
                                                      scheme.onErrorContainer),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Pelanggan ini memiliki hutang ${formatRupiah(_custDebts[_selectedCustomer!.id]!.$1)} di ${_custDebts[_selectedCustomer!.id]!.$2} nota',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: scheme
                                                          .onErrorContainer),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ] else ...[
                                      TextField(
                                        key: _custFieldKey,
                                        controller: _custCtrl,
                                        decoration: InputDecoration(
                                          hintText:
                                              'Cari pelanggan atau ketik nama…',
                                          prefixIcon: const Icon(
                                              Icons.person_outline,
                                              size: 18),
                                          isDense: true,
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          suffixText: _custCtrl.text.isEmpty
                                              ? 'Umum'
                                              : null,
                                          suffixStyle: TextStyle(
                                              color: scheme.onSurfaceVariant,
                                              fontStyle: FontStyle.italic),
                                        ),
                                        // Saat field difokus, gulir ke atas agar dropdown saran
                                        // muncul di atas keyboard (beri jeda untuk animasi keyboard).
                                        onTap: () =>
                                            _scrollCustIntoView(delayMs: 300),
                                        onChanged: (v) {
                                          setState(() {
                                            _custNameManual = v;
                                          });
                                          _searchCustomers(v);
                                        },
                                      ),
                                      if (_custDropdownOpen)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                scheme.surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                                color: scheme.outlineVariant),
                                          ),
                                          constraints: const BoxConstraints(
                                              maxHeight: 240),
                                          child: ListView.builder(
                                            shrinkWrap: true,
                                            padding: EdgeInsets.zero,
                                            itemCount: _custSuggestions.length,
                                            itemBuilder: (context, index) {
                                              final c = _custSuggestions[index];
                                              final debt = _custDebts[c.id];
                                              final hasDebt =
                                                  debt != null && debt.$1 > 0;
                                              // Alamat di bawah nama — disambiguasi
                                              // pelanggan dengan nama sama.
                                              final address = c.address?.trim();
                                              final hasAddress =
                                                  address != null &&
                                                      address.isNotEmpty;
                                              return ListTile(
                                                dense: true,
                                                leading: CircleAvatar(
                                                  radius: 12,
                                                  backgroundColor:
                                                      scheme.primaryContainer,
                                                  child: Text(
                                                      (c.name.isEmpty
                                                              ? '?'
                                                              : c.name[0])
                                                          .toUpperCase(),
                                                      style: TextStyle(
                                                          color: scheme
                                                              .onPrimaryContainer,
                                                          fontSize: 10)),
                                                ),
                                                title: Text(c.name,
                                                    style: const TextStyle(
                                                        fontSize: 13)),
                                                subtitle: (!hasAddress &&
                                                        !hasDebt)
                                                    ? null
                                                    : Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (hasAddress)
                                                            Text(address,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: scheme
                                                                        .onSurfaceVariant)),
                                                          if (hasDebt)
                                                            Text(
                                                                'Hutang: ${formatRupiah(debt.$1)} (${debt.$2} nota)',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        11,
                                                                    color: scheme
                                                                        .error)),
                                                        ],
                                                      ),
                                                onTap: () {
                                                  setState(() {
                                                    _selectedCustomer = c;
                                                    _custCtrl.text = c.name;
                                                    _custDropdownOpen = false;
                                                  });
                                                  _syncMetaCustomer();
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Pegawai picker — dipilih dari daftar (tanpa
                            // keyboard, sehingga tidak menutupi field lain).
                            Text('Pegawai',
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _pickEmployee,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(Icons.badge_outlined,
                                          size: 18,
                                          color: scheme.onSurfaceVariant),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _selectedEmployee?.name ??
                                              'Pilih pegawai',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: _selectedEmployee != null
                                                ? scheme.primary
                                                : scheme.onSurfaceVariant,
                                            fontWeight:
                                                _selectedEmployee != null
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                            fontStyle: _selectedEmployee == null
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                          ),
                                        ),
                                      ),
                                      if (_selectedEmployee != null)
                                        IconButton(
                                          icon:
                                              const Icon(Icons.close, size: 18),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () {
                                            setState(
                                                () => _selectedEmployee = null);
                                            _syncMetaEmployee();
                                          },
                                        )
                                      else
                                        Icon(Icons.expand_more,
                                            color: scheme.onSurfaceVariant),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Payment method
                Text('Metode Pembayaran',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._methods.map((m) {
                      final selected = m.id == _selectedMethodId;
                      return ChoiceChip(
                        label: Text(m.name),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            _selectedMethodId = m.id;
                            _selectedMethodType = m.type;
                          });
                        },
                        selectedColor: scheme.primaryContainer,
                      );
                    }),
                    // Bayar Nanti (tempo) TIDAK lagi dipilih lewat chip di sini —
                    // sudah punya tombol khusus sendiri di bar bawah.
                  ],
                ),
                const SizedBox(height: 16),

                if (_selectedMethodType == 'qris') ...[
                  _QrisDisplay(
                      methods: _methods, selectedId: _selectedMethodId),
                ],

                if (_selectedMethodType == 'tempo') ...[
                  Card(
                    color: scheme.tertiaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.schedule,
                              color: scheme.onTertiaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Bayar Nanti: barang diserahkan / dipesan sekarang, '
                              'dibayar belakangan. Dicatat sebagai hutang penuh '
                              '(${formatRupiah(_total)}). Tagih lewat Riwayat Transaksi.',
                              style: TextStyle(
                                  color: scheme.onTertiaryContainer,
                                  fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_selectedCustomer == null) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: scheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: scheme.onErrorContainer, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pilih pelanggan terdaftar agar hutang bisa dilacak '
                                'akumulatif. Tanpa pelanggan, hutang hanya tercatat di nota ini.',
                                style: TextStyle(
                                    color: scheme.onErrorContainer,
                                    fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton(
                onPressed:
                    (_isSaving || !_bayarEnabled) ? null : _onBayarPressed,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppTheme.payGreen,
                  foregroundColor: Colors.white,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_bayarLabel(), style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed:
                    (_isSaving || !_bayarEnabled) ? null : _onBayarNantiPressed,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  // Mode gelap: scheme.error terlalu pucat — pakai merah solid
                  // yang sama dgn stepper state merah (tombol minus).
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFFD64545)
                          : Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                child:
                    const Text('Bayar Nanti', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tombol "Bayar" aktif: keranjang tidak kosong. Untuk tunai, jumlah uang
  /// diinput nanti di sheet keypad — jadi tidak butuh _tendered di sini.
  bool get _bayarEnabled => ref.read(cartProvider(_cartId)).isNotEmpty;

  String _bayarLabel() => 'Bayar ${formatRupiah(_total)}';

  /// Tap "Bayar": untuk tunai buka sheet keypad (slide-up) lalu konfirmasi
  /// dengan tombol ✓; untuk metode lain langsung konfirmasi.
  Future<void> _onBayarPressed() async {
    FocusScope.of(context).unfocus();
    if (_selectedMethodType == 'tunai') {
      final result = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CashKeypadSheet(
          total: _total,
          initial: _tendered,
          unclaimedChangeAmount: _unclaimedChange?.amount,
          unclaimedChangeTaken: _unclaimedChangeTaken,
          onToggleUnclaimedChangeTaken:
              _unclaimedChange == null ? null : _toggleUnclaimedChangeTaken,
          existingShortfall: _existingShortfall,
        ),
      );
      if (result == null) return; // dibatalkan
      setState(() => _tendered = result);
    }
    await _confirm();
  }

  /// Tap "Bayar Nanti": catat sebagai hutang penuh (tempo), tanpa keypad
  /// tunai — dedicated button, bukan lagi lewat chip Metode Pembayaran.
  Future<void> _onBayarNantiPressed() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedMethodId = 'pm-tempo';
      _selectedMethodType = 'tempo';
      _tendered = 0;
    });
    await _confirm();
  }
}

/// Sheet keypad tunai yang slide-up saat tombol "Bayar" ditekan.
/// Input jumlah uang lalu konfirmasi dengan tombol ✓ di pojok kanan bawah.
/// Pop mengembalikan jumlah uang diterima; null bila dibatalkan.
class _CashKeypadSheet extends StatefulWidget {
  const _CashKeypadSheet({
    required this.total,
    required this.initial,
    this.unclaimedChangeAmount,
    this.unclaimedChangeTaken = false,
    this.onToggleUnclaimedChangeTaken,
    this.existingShortfall,
  });
  final int total;
  final int initial;

  /// Mode tambah belanjaan (Poin 1): kembalian pembayaran terakhir transaksi
  /// asli yang masih belum diambil — null bila bukan mode tambah belanjaan
  /// atau tidak ada kembalian nganggur. Murni informasi, tidak memengaruhi
  /// [total]/nominal yang diinput kasir.
  final int? unclaimedChangeAmount;
  final bool unclaimedChangeTaken;
  final ValueChanged<bool>? onToggleUnclaimedChangeTaken;

  /// Mode tambah belanjaan: sisa tagihan nota ASLI (sebelum item susulan
  /// ini) — null bila bukan mode tambah belanjaan atau nota sudah lunas.
  /// Murni informasi (supaya kasir tahu [total] di sini HANYA harga item
  /// baru, bukan total yang perlu ditagih) — tidak memengaruhi [total]
  /// atau alokasi diskon/pembulatan item.
  final int? existingShortfall;

  @override
  State<_CashKeypadSheet> createState() => _CashKeypadSheetState();
}

class _CashKeypadSheetState extends State<_CashKeypadSheet> {
  late int _tendered = widget.initial;

  /// Mirror lokal `widget.unclaimedChangeTaken` — sheet ini dibuka via
  /// `showModalBottomSheet`, yang builder-nya cuma dievaluasi SEKALI saat
  /// dibuka. `setState` di parent (`_PaymentScreenState`) TIDAK memicu
  /// rebuild sheet yang sudah terbuka, jadi kalau Checkbox baca langsung
  /// `widget.unclaimedChangeTaken`, tampilannya beku di nilai awal walau
  /// tulis-DB via callback berhasil — centang kelihatan "tidak bisa"
  /// walau sebenarnya sudah tersimpan. State lokal ini memberi feedback
  /// visual instan; penulisan DB tetap lewat callback ke parent.
  late bool _changeTaken = widget.unclaimedChangeTaken;

  void _toggleChangeTaken(bool value) {
    setState(() => _changeTaken = value);
    widget.onToggleUnclaimedChangeTaken?.call(value);
  }

  /// Total yang SUNGGUHAN perlu dilunasi kasir — harga item susulan
  /// ditambah sisa tagihan lama (kalau ada). Kembalian/kurang HARUS
  /// dihitung terhadap ini, bukan [widget.total] mentah (item susulan
  /// saja) — kalau tidak, kasir yang mengetik persis "Total yang perlu
  /// ditagih" akan melihat pill "Kembalian" palsu sebesar sisa tagihan
  /// lama, padahal setelah dikonfirmasi tidak ada kembalian sungguhan
  /// (formula DB `_computePaymentChangeGiven` sudah benar; ini murni
  /// preview di sheet yang dulu belum ikut dikoreksi).
  int get _effectiveTotal => widget.total + (widget.existingShortfall ?? 0);

  int get _change =>
      (_tendered - _effectiveTotal).clamp(0, double.maxFinite.toInt());
  int get _shortfall => _tendered > 0 && _tendered < _effectiveTotal
      ? _effectiveTotal - _tendered
      : 0;

  void _press(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _tendered = 0;
        case '⌫':
          _tendered = _tendered ~/ 10;
        case '00':
          _tendered = (_tendered * 100).clamp(0, 99999999);
        case '000':
          _tendered = (_tendered * 1000).clamp(0, 99999999);
        default:
          final d = int.tryParse(key);
          if (d != null) {
            _tendered = (_tendered * 10 + d).clamp(0, 99999999);
          }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color pillBg;
    final Color pillFg;
    final String pillLabel;
    if (_change > 0) {
      pillBg = AppTheme.changeBg(isDark);
      pillFg = AppTheme.changeFg(isDark);
      pillLabel = 'Kembalian';
    } else if (_shortfall > 0) {
      pillBg = AppTheme.debtBg(isDark);
      pillFg = AppTheme.debtFg(isDark);
      pillLabel = 'Sisa / Hutang';
    } else {
      pillBg = AppTheme.changeBg(isDark);
      pillFg = AppTheme.changeFg(isDark);
      pillLabel = '✓ Uang Pas';
    }

    return Material(
      color: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13),
                      children: [
                        const TextSpan(text: 'Total '),
                        TextSpan(
                          text: formatRupiah(widget.total),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (widget.existingShortfall != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('+ Sisa tagihan sebelumnya',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.onSurfaceVariant)),
                      ),
                      const SizedBox(width: 8),
                      Text(formatRupiah(widget.existingShortfall!),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: AppTheme.debtFg(isDark))),
                    ],
                  ),
                ),
                // Jumlahnya sudah dihitungkan — kasir tinggal baca angka
                // ini, tidak perlu jumlah manual "Total + Sisa" sendiri.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text('Total yang perlu ditagih',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(formatRupiah(_effectiveTotal),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppTheme.debtFg(isDark))),
                    ],
                  ),
                ),
              ],
              if (widget.unclaimedChangeAmount != null)
                InkWell(
                  onTap: widget.onToggleUnclaimedChangeTaken == null
                      ? null
                      : () => _toggleChangeTaken(!_changeTaken),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _changeTaken,
                                  onChanged: widget
                                              .onToggleUnclaimedChangeTaken ==
                                          null
                                      ? null
                                      : (v) => _toggleChangeTaken(v ?? false),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text('Pakai kembalian',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: scheme.onSurfaceVariant)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(formatRupiah(widget.unclaimedChangeAmount!),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                                color: AppTheme.changeFg(isDark))),
                      ],
                    ),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Diterima',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  Text(
                    formatRupiah(_tendered),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 22),
                  ),
                ],
              ),
              if (_tendered > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: pillBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(pillLabel,
                          style: TextStyle(
                              fontWeight: FontWeight.w600, color: pillFg)),
                      if (_change > 0 || _shortfall > 0)
                        Text(
                          formatRupiah(_change > 0 ? _change : _shortfall),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: pillFg),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...{10000, 20000, 50000, 100000}
                      .where((d) => d >= _effectiveTotal)
                      .take(3)
                      .map((d) => ActionChip(
                            label: Text(formatRupiah(d)),
                            onPressed: () => setState(() => _tendered = d),
                          )),
                ],
              ),
              const SizedBox(height: 10),
              _Keypad(onPress: _press),
              const SizedBox(height: 10),
              // Item 26b — "Uang Pas" di kiri (sekunder) & "Bayar" di kanan
              // (primer) sebaris paling bawah, supaya tidak jauh secara
              // visual dari tombol konfirmasi saat kasir buru-buru.
              Row(
                children: [
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () =>
                          setState(() => _tendered = _effectiveTotal),
                      style: OutlinedButton.styleFrom(
                          // Override tema global (`outlinedButtonTheme` di
                          // AppTheme set minimumSize lebar penuh by default)
                          // — di sini sengaja SEMPIT (bukan Expanded).
                          minimumSize: const Size(0, 56),
                          padding: const EdgeInsets.symmetric(horizontal: 16)),
                      child: const Text('Uang Pas',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: _tendered > 0
                            ? () => Navigator.of(context).pop(_tendered)
                            : null,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _shortfall > 0
                                  ? 'Catat Hutang ${formatRupiah(_shortfall)}'
                                  : _change > 0
                                      ? 'Bayar · Kembali ${formatRupiah(_change)}'
                                      : 'Bayar',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onPress});
  final ValueChanged<String> onPress;

  // Item 49a — "000" pindah ke baris paling bawah, setelah "00" (gaya
  // kalkulator: 0/00/000 sebaris sama besar, bukan "0" dilebarkan 2x).
  static const _rows = [
    ['1', '2', '3', '⌫'],
    ['4', '5', '6', 'C'],
    ['7', '8', '9'],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Aksen soft keypad (permintaan user): angka 1-9 hijau soft; tombol nol
    // (0/00/000) biru bertahap makin gelap; C/⌫ tetap netral. Softness setara
    // dgn latar aksi (C/⌫) yg sudah ada.
    // Biru bertahap: 0 termuda → 000 tertua.
    final blueLight = [
      const Color(0xFFE7EEF5),
      const Color(0xFFD3E1EE),
      const Color(0xFFBFD4E7),
    ];
    final blueDark = [
      const Color(0x268AABC4),
      const Color(0x408AABC4),
      const Color(0x598AABC4),
    ];
    Color? keyBg(String k, bool isAction) {
      if (isAction) return scheme.surfaceContainerHighest;
      final blueIdx = k == '0' ? 0 : (k == '00' ? 1 : (k == '000' ? 2 : -1));
      if (blueIdx >= 0) return (isDark ? blueDark : blueLight)[blueIdx];
      return AppTheme.changeBg(isDark); // 1-9 → hijau soft
    }

    Color keyFg(String k, bool isAction) {
      if (isAction) return scheme.onSurfaceVariant;
      final isZero = k == '0' || k == '00' || k == '000';
      return isZero ? AppTheme.scanFg(isDark) : AppTheme.changeFg(isDark);
    }

    Widget key(String k, {int flex = 1}) {
      final isAction = k == 'C' || k == '⌫';
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: keyBg(k, isAction),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: scheme.outlineVariant, width: 0.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onPress(k),
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    k,
                    style: TextStyle(
                      fontSize: k.length > 1 && !isAction ? 16 : 20,
                      fontWeight: FontWeight.w600,
                      color: keyFg(k, isAction),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in _rows) Row(children: [for (final k in row) key(k)]),
        Row(children: [key('0'), key('00'), key('000')]),
      ],
    );
  }
}

class _QrisDisplay extends StatelessWidget {
  const _QrisDisplay({required this.methods, required this.selectedId});
  final List<PaymentMethod> methods;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    final method = methods.where((m) => m.id == selectedId).firstOrNull;
    if (method?.qrValue == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'QR QRIS belum dikonfigurasi. Atur di Pengaturan → Metode Pembayaran.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Scan QRIS', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            // Render payload QRIS statis sebagai QR yang bisa discan pembeli.
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: method!.qrValue!,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
