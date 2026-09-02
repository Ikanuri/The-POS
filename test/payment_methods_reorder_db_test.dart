import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Test DB murni utk reorder metode pembayaran (fitur baru "urutan metode
/// pembayaran"): [AppDatabase.reorderPaymentMethods] menulis ulang
/// `sortOrder` sesuai urutan baru, dan SEMUA query lain yang membaca
/// `paymentMethods` dengan `orderBy(sortOrder)` ikut terurut sesuai itu.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  Future<List<PaymentMethod>> sortedActive() => (db.select(db.paymentMethods)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .get();

  test(
      'reorderPaymentMethods menulis ulang sortOrder & query lain ikut terurut',
      () async {
    // Seed default sudah menyisipkan "Tunai" (sortOrder 0). Tambah 2 metode
    // lain dengan sortOrder awal 1 & 2 (urutan: Tunai, BCA, OVO).
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-bca', type: 'bank', name: 'BCA', sortOrder: const Value(1)));
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-ovo',
        type: 'ewallet',
        name: 'OVO',
        sortOrder: const Value(2)));

    final before = await sortedActive();
    expect(before.map((m) => m.id).toList(),
        ['pm-tunai', 'pm-bca', 'pm-ovo']);

    // Owner drag OVO ke posisi PALING ATAS → urutan baru: OVO, Tunai, BCA.
    await db.reorderPaymentMethods(['pm-ovo', 'pm-tunai', 'pm-bca']);

    final after = await sortedActive();
    expect(after.map((m) => m.id).toList(), ['pm-ovo', 'pm-tunai', 'pm-bca']);
    // sortOrder ditulis persis sesuai index urutan baru (0,1,2).
    expect(after.map((m) => m.sortOrder).toList(), [0, 1, 2]);

    await db.close();
  });

  test('paymentMethodsMaxSortOrder mengikuti baris tertinggi saat ini',
      () async {
    // Hanya seed default ("Tunai", sortOrder 0) → max = 0.
    expect(await db.paymentMethodsMaxSortOrder(), 0);

    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-bca', type: 'bank', name: 'BCA', sortOrder: const Value(5)));
    expect(await db.paymentMethodsMaxSortOrder(), 5);

    await db.close();
  });
}
