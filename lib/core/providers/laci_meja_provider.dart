import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import 'device_provider.dart';

/// Item 52 ("Laci Meja") — badge gabungan 3 kategori, dipakai bottom nav
/// (Item 52) & kartu dashboard.
final laciMejaOpenCountProvider = StreamProvider<int>((ref) {
  return ref.watch(databaseProvider).watchLaciMejaOpenCount();
});

final leftBehindItemsProvider = StreamProvider<List<LeftBehindItem>>((ref) {
  return ref.watch(databaseProvider).watchLeftBehindItems();
});

final borrowedItemsProvider = StreamProvider<List<BorrowedItem>>((ref) {
  return ref.watch(databaseProvider).watchBorrowedItems();
});

final preorderEntriesProvider = StreamProvider<List<PreorderEntry>>((ref) {
  return ref.watch(databaseProvider).watchPreorderEntries();
});

/// Item 40 pattern: device BUKAN owner -> baris ditandai `locallyModified`,
/// menunggu persetujuan owner via sync (lihat dok `AppDatabase.
/// dumpLaciMejaProposals`). Device owner tidak pernah set true.
final laciMejaLocallyModifiedProvider = Provider<bool>((ref) {
  return !ref.watch(deviceProvider).isOwner;
});

/// Item 52 susulan — ringkasan Laci Meja yang masih menggantung utk
/// pelanggan keranjang aktif, dipakai pengingat di cart bar (pola sama dgn
/// pengingat hutang di modal checkout). Key: (customerId, customerName) —
/// pelanggan terdaftar dicocokkan lewat id, pembeli lepas lewat nama.
final laciMejaPendingProvider = FutureProvider.family<
    ({int titip, int ketinggalan, int pinjaman, int preorder}),
    (String?, String?)>((ref, key) async {
  final (customerId, customerName) = key;
  final db = ref.watch(databaseProvider);
  // Ikut ter-refresh begitu ada entri Laci Meja berubah.
  ref.watch(laciMejaOpenCountProvider);
  if (customerId != null && customerId.isNotEmpty) {
    return db.getLaciMejaPendingForCustomer(customerId);
  }
  if (customerName != null && customerName.trim().isNotEmpty) {
    return db.getLaciMejaPendingForName(customerName);
  }
  return (titip: 0, ketinggalan: 0, pinjaman: 0, preorder: 0);
});

/// Item 52 susulan (permintaan user) — qty+satuan per baris nota yang
/// ditandai titip/ketinggalan, dipakai dashboard Laci Meja. Ikut ter-refresh
/// mengikuti `leftBehindItemsProvider` (bukan `.autoDispose` — dashboard
/// kadang di-pop lalu dibuka lagi, cache singkat ini murah & aman dipakai
/// ulang).
final leftBehindQtyUnitProvider = FutureProvider<
    Map<String, ({double qty, String unitName})>>((ref) async {
  final items = ref.watch(leftBehindItemsProvider).valueOrNull ?? [];
  final ids = items.map((e) => e.transactionItemId).whereType<String>().toList();
  return ref.watch(databaseProvider).getQtyUnitForTransactionItems(ids);
});

/// Item 52 redesain — nama produk+satuan per `product_unit_id` yang muncul
/// di daftar Pre-order dashboard, dipakai menampilkan "qty produk - jaminan"
/// per baris (dikelompokkan per nota).
final preorderProductUnitLabelsProvider = FutureProvider<
    Map<String, ({String productName, String unitName})>>((ref) async {
  final items = ref.watch(preorderEntriesProvider).valueOrNull ?? [];
  final ids = items.map((e) => e.productUnitId).toSet().toList();
  return ref.watch(databaseProvider).getProductUnitLabelsFor(ids);
});
