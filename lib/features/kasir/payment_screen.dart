import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/providers/device_provider.dart';
import '../../core/theme/app_theme.dart';
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
  final _custCtrl = TextEditingController();

  List<PaymentMethod> _methods = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Prefill dari aksi "Tambah Item" di riwayat transaksi
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefill = ref.read(prefillCustomerProvider);
      if (prefill != null && prefill.isNotEmpty) {
        setState(() {
          _custNameManual = prefill;
          _custCtrl.text = prefill;
        });
        ref.read(prefillCustomerProvider.notifier).state = null;
      }
    });
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
    if (mounted) {
      setState(() {
        _custSuggestions = results;
        _custDropdownOpen = results.isNotEmpty;
      });
    }
  }

  int get _cartTotal => ref.read(cartProvider.notifier).totalAmount;

  int get _total => _totalOverride ?? _cartTotal;

  int get _paid =>
      _selectedMethodType == 'tunai' ? _tendered : _total;

  int get _change => (_paid - _total).clamp(0, double.maxFinite.toInt());

  int get _shortfall =>
      _selectedMethodType == 'tunai' && _tendered > 0 && _tendered < _total
          ? _total - _tendered
          : 0;

  bool get _canConfirm {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return false;
    if (_selectedMethodType == 'tunai') return _tendered > 0;
    return true;
  }

  void _keypadPress(String key) {
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

  Future<void> _editTotal() async {
    final ctrl = TextEditingController(text: _total.toString());
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
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  prefixText: 'Rp ', border: OutlineInputBorder()),
              onTap: () => ctrl.selection = TextSelection(
                  baseOffset: 0, extentOffset: ctrl.text.length),
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
            onPressed: () => ctx.pop(int.tryParse(ctrl.text)),
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
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final db = ref.read(databaseProvider);
      final device = ref.read(deviceProvider);
      final now = DateTime.now();

      final txCount = await db.countTodayTransactions(device.deviceCode);
      final localId =
          '${device.deviceCode}-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(txCount + 1).toString().padLeft(4, '0')}';

      final paidAmount = _selectedMethodType == 'tempo' ? 0 : _paid;
      final status = paidAmount < _total ? 'kurang_bayar' : 'lunas';

      // Customer resolution
      final customerId = _selectedCustomer?.id;
      final customerName = _selectedCustomer == null
          ? (_custNameManual.trim().isEmpty ? null : _custNameManual.trim())
          : null;

      // Loyalty points
      int pointsEarned = 0;
      final loyaltyThresholdStr =
          await db.getSetting('loyalty_point_threshold');
      final loyaltyThreshold = int.tryParse(loyaltyThresholdStr ?? '') ?? 0;
      if (customerId != null && loyaltyThreshold > 0) {
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

      final itemCompanions = cart
          .map((item) => TransactionItemsCompanion.insert(
                id: _uuid.v4(),
                transactionId: txId,
                productId: item.productId,
                productUnitId: item.productUnitId,
                qty: item.qty,
                priceAtSale: item.price,
                originalPrice: item.originalPrice,
                priceOverridden: Value(item.priceOverridden),
                costAtSale: Value(item.costPrice),
                itemNote: Value(item.itemNote),
                subtotal: item.subtotal,
              ))
          .toList();

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

      // Stock ledger entries
      final stockEntries = <StockLedgerCompanion>[];
      for (final item in cart) {
        if (item.qty > 0) {
          final currentStock = await db.currentStock(item.productUnitId);
          stockEntries.add(StockLedgerCompanion.insert(
            id: _uuid.v4(),
            productUnitId: item.productUnitId,
            type: 'sale',
            qtyChange: -item.qty,
            stockAfter: currentStock - item.qty,
            note: Value(localId),
            createdAt: Value(now),
          ));
        }
      }

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
        stockEntries: stockEntries,
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
      body: ListView(
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
                ...cart.map((item) => ListTile(
                      dense: true,
                      title: Text(item.productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                          '${item.unitName} × ${item.qty % 1 == 0 ? item.qty.toInt() : item.qty}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: Text(formatRupiah(item.subtotal),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    )),
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
                            _selectedCustomer!.name[0].toUpperCase(),
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
                          children: _custSuggestions
                              .take(5)
                              .map((c) => ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: scheme.primaryContainer,
                                      child: Text(c.name[0].toUpperCase(),
                                          style: TextStyle(
                                              color: scheme.onPrimaryContainer,
                                              fontSize: 10)),
                                    ),
                                    title: Text(c.name,
                                        style:
                                            const TextStyle(fontSize: 13)),
                                    onTap: () {
                                      setState(() {
                                        _selectedCustomer = c;
                                        _custCtrl.text = c.name;
                                        _custDropdownOpen = false;
                                      });
                                    },
                                  ))
                              .toList(),
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
            children: _methods.map((m) {
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
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Cash input — keypad ala mockup
          if (_selectedMethodType == 'tunai') ...[
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Diterima',
                            style:
                                TextStyle(color: scheme.onSurfaceVariant)),
                        Text(
                          formatRupiah(_tendered),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_tendered > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _change > 0
                      ? scheme.primaryContainer
                      : _shortfall > 0
                          ? scheme.errorContainer
                          : scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _change > 0
                          ? 'Kembalian'
                          : _shortfall > 0
                              ? 'Sisa / Hutang'
                              : '✓ Uang Pas',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _change > 0
                            ? scheme.onPrimaryContainer
                            : _shortfall > 0
                                ? scheme.onErrorContainer
                                : scheme.onTertiaryContainer,
                      ),
                    ),
                    if (_change > 0 || _shortfall > 0)
                      Text(
                        formatRupiah(_change > 0 ? _change : _shortfall),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: _change > 0
                              ? scheme.onPrimaryContainer
                              : scheme.onErrorContainer,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('Uang Pas'),
                  backgroundColor: scheme.primaryContainer,
                  side: BorderSide.none,
                  onPressed: () => setState(() => _tendered = _total),
                ),
                ...{10000, 20000, 50000, 100000}
                    .where((d) => d >= _total)
                    .take(3)
                    .map((d) => ActionChip(
                          label: Text(formatRupiah(d)),
                          onPressed: () =>
                              setState(() => _tendered = d),
                        )),
              ],
            ),
            const SizedBox(height: 8),
            _Keypad(onPress: _keypadPress),
          ],

          if (_selectedMethodType == 'qris') ...[
            _QrisDisplay(methods: _methods, selectedId: _selectedMethodId),
          ],

          if (_selectedMethodType == 'tempo') ...[
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: scheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Transaksi tempo: pembayaran dicatat 0, status kurang_bayar. Tagih via Riwayat Transaksi.',
                        style: TextStyle(
                            color: scheme.onErrorContainer, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: FilledButton(
          onPressed: (_isSaving || !_canConfirm) ? null : _confirm,
          style:
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(_confirmLabel(), style: const TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  String _confirmLabel() {
    if (_selectedMethodType != 'tunai') return 'Konfirmasi Transaksi';
    if (_change > 0) return 'Kembali ${formatRupiah(_change)}';
    if (_shortfall > 0) return 'Catat Hutang ${formatRupiah(_shortfall)}';
    if (_tendered > 0) return 'Konfirmasi Bayar';
    return 'Masukkan Jumlah Bayar';
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
