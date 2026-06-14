import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/models/cart_item.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_formatters.dart';
import 'cart_provider.dart';

const _uuid = Uuid();

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
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

  List<PaymentMethod> _methods = [];
  bool _isSaving = false;

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
    if (mounted) {
      setState(() {
        _methods = methods;
        if (methods.isNotEmpty) {
          _selectedMethodId = methods.first.id;
          _selectedMethodType = methods.first.type;
        }
      });
    }
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
    }
  }

  int get _cartTotal => ref.read(cartProvider.notifier).totalAmount;

  int get _total => _totalOverride ?? _cartTotal;

  int get _paid =>
      _selectedMethodType == 'tunai' ? _tendered : _total;

  int get _change => (_paid - _total).clamp(0, double.maxFinite.toInt());

  Future<void> _editTotal() async {
    final ctrl = TextEditingController(
        text: ThousandsSeparatorFormatter.format(_total));
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
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);

      // C-5: Cek stok sebelum transaksi jika setting "izinkan stok minus" OFF.
      final allowNegative =
          (await db.getSetting('allow_negative_stock')) == '1';
      if (!allowNegative) {
        final notifier = ref.read(cartProvider.notifier);
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
      final device = ref.read(deviceProvider);
      final notifier = ref.read(cartProvider.notifier);
      final now = DateTime.now();

      // Nomor nota dijamin unik (penjualan & retur berbagi ruang sequence).
      final localId = await db.generateUniqueLocalId(device.deviceCode, now);

      final isTempo = _selectedMethodType == 'tempo';
      final paidAmount = isTempo ? 0 : _paid;
      final status = isTempo
          ? 'tempo'
          : (paidAmount < _total ? 'kurang_bayar' : 'lunas');

      // Customer resolution
      final customerId = _selectedCustomer?.id;
      final customerName = _selectedCustomer == null
          ? (_custNameManual.trim().isEmpty ? null : _custNameManual.trim())
          : null;

      // Loyalty points — tidak diberikan untuk transaksi tempo (belum dibayar).
      int pointsEarned = 0;
      final loyaltyThresholdStr =
          await db.getSetting('loyalty_point_threshold');
      final loyaltyThreshold = int.tryParse(loyaltyThresholdStr ?? '') ?? 0;
      if (customerId != null && loyaltyThreshold > 0 && !isTempo) {
        pointsEarned = (_total / loyaltyThreshold).floor();
      }

      final txId = _uuid.v4();
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
        pointsEarned: Value(pointsEarned),
        createdAt: Value(now),
      );

      // Effective qty memakai satu sumber kebenaran di cart provider (A-13).
      double effQty(CartItem item) => notifier.effectiveQtyFor(item);

      // Bila total di-override manual (diskon), alokasikan selisihnya secara
      // proporsional ke tiap baris agar Σ subtotal == total tersimpan dan
      // struk konsisten. HPP (costAtSale) tidak diutak-atik → laba akurat.
      final discountFactor =
          (_totalOverride != null && _cartTotal > 0) ? _total / _cartTotal : 1.0;
      final applyDiscount = discountFactor != 1.0;

      // Lewati item induk placeholder (effectiveQty == 0) agar tidak masuk
      // ke transaction_items. Induk yang hanya dipakai sebagai header varian
      // di UI tidak perlu dicatat sebagai baris terpisah.
      final lines = cart
          .where((item) => effQty(item) > 0)
          .map((item) {
            final eq = effQty(item);
            return (item: item, eq: eq, base: (item.price * eq).round());
          })
          .toList();
      var lastQtyIdx = -1;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].eq > 0) lastQtyIdx = i;
      }

      final itemCompanions = <TransactionItemsCompanion>[];
      var allocated = 0;
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        int sub;
        if (!applyDiscount) {
          sub = l.base;
        } else if (i == lastQtyIdx) {
          sub = _total - allocated; // baris terakhir menyerap sisa pembulatan
        } else {
          sub = (l.base * discountFactor).round();
          allocated += sub;
        }
        final unitPrice =
            (applyDiscount && l.eq > 0) ? (sub / l.eq).round() : l.item.price;
        itemCompanions.add(TransactionItemsCompanion.insert(
          id: _uuid.v4(),
          transactionId: txId,
          productId: l.item.productId,
          productUnitId: l.item.productUnitId,
          qty: l.eq,
          priceAtSale: unitPrice,
          originalPrice: l.item.originalPrice,
          priceOverridden: Value(l.item.priceOverridden || applyDiscount),
          costAtSale: Value(l.item.costPrice),
          itemNote: Value(l.item.itemNote),
          subtotal: sub,
        ));
      }

      final paymentCompanions = paidAmount > 0
          ? [
              TransactionPaymentsCompanion.insert(
                id: _uuid.v4(),
                transactionId: txId,
                amount: paidAmount,
                method: _selectedMethodType,
                paidAt: Value(now),
                kasirId: Value(device.deviceCode),
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

      ref.read(cartProvider.notifier).clear();
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

  @override
  void dispose() {
    _custCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
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
                              color: scheme.onSurfaceVariant, fontSize: 12)),
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
                                child: Icon(
                                    Icons.subdirectory_arrow_right,
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
                                    fontSize: 11,
                                    color: scheme.primary))
                            : Text(
                                '${item.unitName} × ${eq % 1 == 0 ? eq.toInt() : eq}',
                                style: const TextStyle(fontSize: 11)),
                        trailing: isPlaceholder
                            ? null
                            : Text(
                                formatRupiah((item.price * eq).round()),
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
                                style:
                                    TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(width: 6),
                            Icon(Icons.edit, size: 13, color: scheme.tertiary),
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
                          backgroundColor: scheme.primaryContainer,
                          child: Text(
                            (_selectedCustomer!.name.isEmpty ? '?' : _selectedCustomer!.name[0]).toUpperCase(),
                            style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_selectedCustomer!.name,
                              style: TextStyle(color: scheme.primary)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            setState(() {
                              _selectedCustomer = null;
                              _custCtrl.clear();
                              _custNameManual = '';
                            });
                          },
                        ),
                      ],
                    ),
                    if ((_custDebts[_selectedCustomer!.id]?.$1 ?? 0) > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 16, color: scheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pelanggan ini memiliki hutang ${formatRupiah(_custDebts[_selectedCustomer!.id]!.$1)} di ${_custDebts[_selectedCustomer!.id]!.$2} nota',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ] else ...[
                    TextField(
                      controller: _custCtrl,
                      decoration: InputDecoration(
                        hintText: 'Cari pelanggan atau ketik nama…',
                        prefixIcon: const Icon(Icons.person_outline, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        suffixText: _custCtrl.text.isEmpty ? 'Umum' : null,
                        suffixStyle: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic),
                      ),
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
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          children: _custSuggestions.take(5).map((c) {
                            final debt = _custDebts[c.id];
                            final hasDebt = debt != null && debt.$1 > 0;
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 12,
                                backgroundColor: scheme.primaryContainer,
                                child: Text((c.name.isEmpty ? '?' : c.name[0]).toUpperCase(),
                                    style: TextStyle(
                                        color: scheme.onPrimaryContainer,
                                        fontSize: 10)),
                              ),
                              title: Text(c.name,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: hasDebt
                                  ? Text(
                                      'Hutang: ${formatRupiah(debt.$1)} (${debt.$2} nota)',
                                      style: TextStyle(
                                          fontSize: 11, color: scheme.error))
                                  : null,
                              onTap: () {
                                setState(() {
                                  _selectedCustomer = c;
                                  _custCtrl.text = c.name;
                                  _custDropdownOpen = false;
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

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
              // Bayar Nanti (tempo / pre-order) — selalu tersedia.
              // showCheckmark:false agar ikon jam & centang tidak tumpang tindih
              // saat chip terpilih.
              ChoiceChip(
                showCheckmark: false,
                avatar: Icon(Icons.schedule,
                    size: 16,
                    color: _selectedMethodType == 'tempo'
                        ? scheme.onTertiaryContainer
                        : scheme.onSurfaceVariant),
                label: const Text('Bayar Nanti'),
                selected: _selectedMethodType == 'tempo',
                onSelected: (_) {
                  setState(() {
                    _selectedMethodId = 'pm-tempo';
                    _selectedMethodType = 'tempo';
                    _tendered = 0;
                  });
                },
                selectedColor: scheme.tertiaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_selectedMethodType == 'qris') ...[
            _QrisDisplay(methods: _methods, selectedId: _selectedMethodId),
          ],

          if (_selectedMethodType == 'tempo') ...[
            Card(
              color: scheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.schedule, color: scheme.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bayar Nanti: barang diserahkan / dipesan sekarang, '
                        'dibayar belakangan. Dicatat sebagai hutang penuh '
                        '(${formatRupiah(_total)}). Tagih lewat Riwayat Transaksi.',
                        style: TextStyle(
                            color: scheme.onTertiaryContainer, fontSize: 12),
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
                              color: scheme.onErrorContainer, fontSize: 12),
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
        child: FilledButton(
          onPressed: (_isSaving || !_bayarEnabled) ? null : _onBayarPressed,
          style:
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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
    );
  }

  /// Tombol "Bayar" aktif: keranjang tidak kosong. Untuk tunai, jumlah uang
  /// diinput nanti di sheet keypad — jadi tidak butuh _tendered di sini.
  bool get _bayarEnabled => ref.read(cartProvider).isNotEmpty;

  String _bayarLabel() {
    if (_selectedMethodType == 'tempo') {
      return 'Simpan Hutang ${formatRupiah(_total)}';
    }
    if (_selectedMethodType == 'tunai') {
      return 'Bayar ${formatRupiah(_total)}';
    }
    return 'Konfirmasi ${formatRupiah(_total)}';
  }

  /// Tap "Bayar": untuk tunai buka sheet keypad (slide-up) lalu konfirmasi
  /// dengan tombol ✓; untuk metode lain langsung konfirmasi.
  Future<void> _onBayarPressed() async {
    FocusScope.of(context).unfocus();
    if (_selectedMethodType == 'tunai') {
      final result = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CashKeypadSheet(total: _total, initial: _tendered),
      );
      if (result == null) return; // dibatalkan
      setState(() => _tendered = result);
    }
    await _confirm();
  }

}

/// Sheet keypad tunai yang slide-up saat tombol "Bayar" ditekan.
/// Input jumlah uang lalu konfirmasi dengan tombol ✓ di pojok kanan bawah.
/// Pop mengembalikan jumlah uang diterima; null bila dibatalkan.
class _CashKeypadSheet extends StatefulWidget {
  const _CashKeypadSheet({required this.total, required this.initial});
  final int total;
  final int initial;

  @override
  State<_CashKeypadSheet> createState() => _CashKeypadSheetState();
}

class _CashKeypadSheetState extends State<_CashKeypadSheet> {
  late int _tendered = widget.initial;

  int get _change =>
      (_tendered - widget.total).clamp(0, double.maxFinite.toInt());
  int get _shortfall =>
      _tendered > 0 && _tendered < widget.total ? widget.total - _tendered : 0;

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
                  Text('Total ${formatRupiah(widget.total)}',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 13)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
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
                  ActionChip(
                    label: const Text('Uang Pas'),
                    backgroundColor: scheme.primaryContainer,
                    side: BorderSide.none,
                    onPressed: () => setState(() => _tendered = widget.total),
                  ),
                  ...{10000, 20000, 50000, 100000}
                      .where((d) => d >= widget.total)
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
              SizedBox(
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

  static const _rows = [
    ['1', '2', '3', '⌫'],
    ['4', '5', '6', 'C'],
    ['7', '8', '9', '00'],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String k, {int flex = 1}) {
      final isAction = k == 'C' || k == '⌫';
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: isAction
                ? scheme.surfaceContainerHighest
                : scheme.surface,
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
                      color: isAction
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
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
        for (final row in _rows)
          Row(children: [for (final k in row) key(k)]),
        Row(children: [key('0', flex: 2), key('000', flex: 2)]),
      ],
    );
  }
}

class _QrisDisplay extends StatelessWidget {
  const _QrisDisplay(
      {required this.methods, required this.selectedId});
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
            // QR display placeholder — gunakan qr_flutter jika qrValue tersedia
            Container(
              width: 200,
              height: 200,
              color: Colors.white,
              alignment: Alignment.center,
              child: Text(method!.qrValue!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }
}
