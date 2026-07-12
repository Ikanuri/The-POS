import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/produk/produk_list_screen.dart';

import 'helpers/pump_app.dart';

/// Poin 25b — geser item produk ke kiri untuk nonaktifkan, pola sama seperti
/// hapus pelanggan. BUKAN hard-delete (tidak ada fungsi itu di DB) — swipe
/// ini cuma jalur lebih cepat ke aksi "Nonaktifkan" yang sudah ada di
/// produk_form_screen.dart (isActive=false, riwayat transaksi tetap aman).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'geser produk ke kiri lalu konfirmasi → produk dinonaktifkan '
      '(isActive=false), riwayat tetap aman', (tester) async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'));

    await pumpWithFakeApp(tester, db: db, child: const ProdukListScreen());
    expect(find.text('Sedap Goreng'), findsOneWidget);

    await tester.drag(find.text('Sedap Goreng'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    // Dialog konfirmasi muncul.
    expect(find.text('Nonaktifkan Produk?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Nonaktifkan'));
    await tester.pumpAndSettle();

    final row =
        await (db.select(db.products)..where((t) => t.id.equals('p1')))
            .getSingle();
    expect(row.isActive, isFalse);

    // Produk nonaktif hilang dari daftar aktif (watchProducts filter aktif).
    expect(find.text('Sedap Goreng'), findsNothing);

    await drain(tester);
  });

  testWidgets('geser lalu Batal → produk TETAP aktif, tidak berubah',
      (tester) async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Teh Botol'));

    await pumpWithFakeApp(tester, db: db, child: const ProdukListScreen());
    await tester.drag(find.text('Teh Botol'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Batal'));
    await tester.pumpAndSettle();

    final row =
        await (db.select(db.products)..where((t) => t.id.equals('p1')))
            .getSingle();
    expect(row.isActive, isTrue);
    expect(find.text('Teh Botol'), findsOneWidget);

    await drain(tester);
  });

  testWidgets(
      'device TANPA izin edit (kasir tanpa input_stok) → tidak bisa geser '
      'sama sekali', (tester) async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Kopi Sachet'));

    const kasirNoPerm = DeviceIdentity(
      storeUuid: 's',
      storeKey: 'k',
      storeName: 'Toko',
      deviceName: 'Kasir',
      deviceCode: 'K1',
      deviceRole: 'kasir',
    );
    await pumpWithFakeApp(tester,
        db: db, device: kasirNoPerm, child: const ProdukListScreen());

    // Tanpa Dismissible, drag horizontal tidak memicu apa pun / tidak error.
    await tester.drag(find.text('Kopi Sachet'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Nonaktifkan Produk?'), findsNothing);

    await drain(tester);
  });
}
