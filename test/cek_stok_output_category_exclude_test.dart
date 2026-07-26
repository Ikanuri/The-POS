import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/cek_stok_screen.dart';

import 'helpers/pump_app.dart';

/// Item 2 (usulan user 25 Juli, "seperti html"): kecualikan kategori
/// tertentu dari teks Order Restock — meniru `skCatExcluded`/
/// `sk-outcat-bar`/`skRenderOutCats` di HTML acuan persis: chip ✓/✕ per
/// kategori, produk kategori dikecualikan TETAP boleh dicentang & tampil
/// di daftar, HANYA tidak ikut ditulis ke teks.
void main() {
  Future<int> addGroup(AppDatabase db, int id, String name) async {
    await db.into(db.productGroups).insert(
        ProductGroupsCompanion.insert(id: Value(id), name: Value(name)));
    return id;
  }

  Future<void> addProduct(AppDatabase db, String name,
      {int? groupId, double stock = -10, bool checked = true}) async {
    final id = 'p-$name';
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: id,
        name: name,
        productGroupId: Value(groupId),
        markedOutOfStock: Value(checked)));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(101), name: 'Pcs'),
        mode: InsertMode.insertOrIgnore);
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: '$id-base',
        productId: id,
        isBaseUnit: const Value(true),
        unitTypeId: const Value(101)));
    await db.adjustStock(productUnitId: '$id-base', newQty: stock);
  }

  String orderText(WidgetTester tester) {
    final fields = find.byType(TextField).evaluate().toList();
    return (fields.last.widget as TextField).controller!.text;
  }

  testWidgets(
      'chip sertakan/kecualikan HANYA muncul kalau ada >=2 kategori bernama '
      '(satu kategori tak ada gunanya dikecualikan, sama spt acuan)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final g1 = await addGroup(db, 1, 'Sembako');
    await addProduct(db, 'Beras', groupId: g1);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('outcat-1')), findsNothing,
        reason: 'chip toggle kategori tidak boleh muncul kalau cuma 1 '
            'kategori bernama');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'kecualikan kategori: produk kategori itu HILANG dari teks tapi TETAP '
      'tercentang & tampil di daftar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final g1 = await addGroup(db, 1, 'Sembako');
    final g2 = await addGroup(db, 2, 'Gas');
    await addProduct(db, 'Beras', groupId: g1);
    await addProduct(db, 'Lpg', groupId: g2);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    expect(orderText(tester), contains('Beras'));
    expect(orderText(tester), contains('Lpg'));

    // Kecualikan kategori "Gas" (chip TOGGLE, dibedakan dari chip FILTER
    // kategori di baris atas yang labelnya sama persis via Key).
    await tester.tap(find.byKey(const ValueKey('outcat-2')));
    await tester.pumpAndSettle();

    expect(orderText(tester), contains('Beras'));
    expect(orderText(tester), isNot(contains('Lpg')),
        reason: 'produk kategori dikecualikan tidak boleh ikut teks');

    // Tapi TETAP tercentang di DB & tampil di daftar produk.
    final lpg = await (db.select(db.products)
          ..where((t) => t.id.equals('p-Lpg')))
        .getSingle();
    expect(lpg.markedOutOfStock, isTrue,
        reason: 'dikecualikan dari OUTPUT saja, centangnya tetap aman');
    expect(find.text('Lpg'), findsOneWidget,
        reason: 'produk kategori dikecualikan tetap tampil di daftar');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'hint jumlah kategori dikecualikan muncul & bertambah/berkurang sesuai '
      'toggle', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final g1 = await addGroup(db, 1, 'Sembako');
    final g2 = await addGroup(db, 2, 'Gas');
    await addProduct(db, 'Beras', groupId: g1);
    await addProduct(db, 'Lpg', groupId: g2);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('kategori dikecualikan'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('outcat-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 kategori dikecualikan'), findsOneWidget);

    // Sertakan lagi.
    await tester.tap(find.byKey(const ValueKey('outcat-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('kategori dikecualikan'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'PENTING: semua kategori tercentang kebetulan dikecualikan -> panel '
      'TETAP terlihat (chip toggle tetap bisa dijangkau utk menyertakan '
      'balik), bukan hilang total', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addGroup(db, 1, 'Sembako');
    final g2 = await addGroup(db, 2, 'Gas');
    await addProduct(db, 'Lpg', groupId: g2); // hanya 1 produk, di kategori Gas

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('outcat-2')));
    await tester.pumpAndSettle();

    // Teksnya kosong dari sisi produk, tapi panel & chip toggle tetap ada.
    expect(find.byKey(const ValueKey('outcat-2')), findsOneWidget,
        reason: 'chip kategori harus tetap terlihat supaya bisa disertakan '
            'balik, bahkan saat SEMUA produk tercentang kebetulan '
            'dikecualikan');
    expect(find.textContaining('Teks Order Restock'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'dua arah: mengetik nama produk kategori DIKECUALIKAN ke teks tidak '
      'mencentangnya (baris itu diabaikan penuh oleh parser)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final g1 = await addGroup(db, 1, 'Sembako');
    final g2 = await addGroup(db, 2, 'Gas');
    await addProduct(db, 'Beras', groupId: g1);
    await addProduct(db, 'Lpg', groupId: g2, checked: false);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('outcat-2')));
    await tester.pumpAndSettle();

    final panel = find.byType(TextField).last;
    await tester.enterText(
        panel, 'Order Restock:\n1 Pcs Beras\n1 Pcs Lpg');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final lpg = await (db.select(db.products)
          ..where((t) => t.id.equals('p-Lpg')))
        .getSingle();
    expect(lpg.markedOutOfStock, isFalse,
        reason: 'produk kategori dikecualikan tidak boleh ter-centang lewat '
            'edit teks — baris itu diabaikan penuh oleh parser');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets('pengecualian kategori TERSIMPAN persisten (bertahan reload)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final g1 = await addGroup(db, 1, 'Sembako');
    final g2 = await addGroup(db, 2, 'Gas');
    await addProduct(db, 'Beras', groupId: g1);
    await addProduct(db, 'Lpg', groupId: g2);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('outcat-2')));
    await tester.pumpAndSettle();

    final raw = await db.getSetting('cek_stok_excluded_output_groups');
    expect(raw, isNotNull);
    expect(raw, contains('2'));

    // Buka ulang layar (simulasi reload) — exclusion harus terbaca kembali.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    expect(orderText(tester), isNot(contains('Lpg')),
        reason: 'pengecualian kategori harus bertahan setelah layar dibuka '
            'ulang (tersimpan di settings, bukan cuma state sesi)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
