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
