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
final laciMejaPendingProvider =
    FutureProvider.family<LaciMejaPending, (String?, String?)>((ref, key) async {
  final (customerId, customerName) = key;
  final db = ref.watch(databaseProvider);
  // Ikut ter-refresh begitu ada entri Laci Meja berubah.
  ref.watch(laciMejaOpenCountProvider);
  return db.getLaciMejaPending(
      customerId: customerId, customerName: customerName);
});

/// Hutang akumulatif pelanggan keranjang aktif (total rupiah + jumlah nota
/// belum lunas) — permintaan user: pengingat hutang muncul DI CART BAR
/// (di bawah nominal Total), bukan cuma di modal checkout spt sebelumnya.
/// Null/(0,0) kalau pembeli tidak terdaftar (hutang selalu terikat
/// `customerId`, pembeli lepas tidak bisa punya nota tempo).
/// `.autoDispose` DISENGAJA: hutang hanya berubah saat nota tempo baru dibuat
/// (checkout -> keranjang & pelanggan ikut dibersihkan) atau dilunasi di layar
/// lain. Dgn autoDispose, angka selalu di-fetch ulang tiap pelanggan dipilih
/// lagi — tidak ada cache basi yang menempel sepanjang umur app.
final cartCustomerDebtProvider = FutureProvider.autoDispose
    .family<(int total, int count), String?>((ref, customerId) async {
  if (customerId == null || customerId.isEmpty) return (0, 0);
  return ref.watch(databaseProvider).getCustomerOutstandingDebt(customerId);
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

/// Nama pelanggan TERKINI per `transaction_id` untuk SELURUH entri Laci Meja
/// yang sedang tampil (ketiga kategori sekaligus, satu query) — supaya nama
/// di dashboard selalu ikut nota rujukannya, bukan salinan beku saat entri
/// dicatat. Lihat dok `AppDatabase.getCustomerNamesForTransactions` untuk
/// laporan bug & alasan pendekatannya.
///
/// Nota yang tidak punya nama apa pun ("Umum") sengaja TIDAK masuk map —
/// pemanggil jatuh ke salinan beku lamanya lebih dulu, baru "Umum".
final laciMejaCustomerNamesProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final leftBehind = ref.watch(leftBehindItemsProvider).valueOrNull ?? [];
  final borrowed = ref.watch(borrowedItemsProvider).valueOrNull ?? [];
  final preorder = ref.watch(preorderEntriesProvider).valueOrNull ?? [];
  final ids = <String>{
    ...leftBehind.map((e) => e.transactionId),
    ...borrowed.map((e) => e.transactionId),
    // Pre-order `transactionId` NULLABLE (titip wadah tanpa beli apa pun).
    ...preorder.map((e) => e.transactionId).whereType<String>(),
  }.toList();
  return ref.watch(databaseProvider).getCustomerNamesForTransactions(ids);
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
