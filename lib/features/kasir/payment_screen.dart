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
  final _paidCtrl = TextEditingController();
  String _selectedMethodId = 'pm-tunai';
  String _selectedMethodType = 'tunai';
  bool _isPartial = false;

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

  int get _total =>
      ref.read(cartProvider.notifier).totalAmount;

  int get _paid {
    if (_selectedMethodType == 'tunai') {
      return int.tryParse(_paidCtrl.text.replaceAll('.', '')) ?? 0;
    }
    return _total;
  }

  int get _change => (_paid - _total).clamp(0, double.maxFinite.toInt());

  bool get _canConfirm {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return false;
    if (_selectedMethodType == 'tunai') {
      return _paid >= _total || _isPartial;
    }
    return true;
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

      final paidAmount = _selectedMethodType == 'tempo'
          ? 0
          : _isPartial
              ? _paid
              : (_selectedMethodType == 'tunai' ? _paid : _total);
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
    _paidCtrl.dispose();
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Text('Total',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(
                        formatRupiah(_total),
                        style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16),
                      ),
                    ],
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

          // Cash input
          if (_selectedMethodType == 'tunai') ...[
            Text('Jumlah Bayar',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _paidCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: 'Rp ',
                hintText: '0',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: {_total, _total + 1000, _total + 2000, _total + 5000}
                  .toList()
                  .map((v) => ActionChip(
                        label: Text(formatRupiah(v)),
                        onPressed: () {
                          _paidCtrl.text = v.toString();
                          setState(() {});
                        },
                      ))
                  .toList(),
            ),
            if (_paid >= _total) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Kembalian',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  Text(
                    formatRupiah(_change),
                    style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Bayar sebagian (kurang bayar)',
                  style: TextStyle(
                      fontSize: 13, color: scheme.onSurfaceVariant)),
              value: _isPartial,
              onChanged: (v) => setState(() => _isPartial = v ?? false),
            ),
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
              : const Text('Konfirmasi Transaksi',
                  style: TextStyle(fontSize: 16)),
        ),
      ),
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
