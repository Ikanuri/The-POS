import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/produk/cek_stok_screen.dart';

import 'helpers/pump_app.dart';

/// Item 4 REVISI (25 Juli) — user membandingkan dgn HTML acuan yang dia
/// kirim & menemukan dua penyimpangan mendasar:
///  1. Qty di teks order diambil dari STOK dan tidak bisa di-set sama
///     sekali, padahal yang dibutuhkan adalah JUMLAH YANG MAU DIORDER.
///     Akibat nyata: stok -104 menghasilkan "-104 Pres Lawet Ijo".
///  2. Produk bersatuan tunggal tidak dapat qty/satuan sama sekali (jatuh
///     ke "- Nama" polos), padahal di acuan SETIAP item tercentang selalu
///     punya qty & satuan.
/// Acuan: tiap kartu punya `[−] [qty] [+] [satuan ▾]`, qty awal 1, angkanya
/// diketuk utk mengetik, dan teks order bisa diedit dua arah.
void main() {
  Future<void> addProduct(AppDatabase db, String name,
      {double stock = 0, bool tiered = false, bool checked = false}) async {
    final id = 'p-$name';
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: id, name: name, markedOutOfStock: Value(checked)));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(101), name: 'Pcs'),
        mode: InsertMode.insertOrIgnore);
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(102), name: 'Dus'),
        mode: InsertMode.insertOrIgnore);
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '$id-base',
          productId: id,
          isBaseUnit: const Value(true),
          unitTypeId: const Value(101),
        ));
    if (tiered) {
      await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
            id: '$id-dus',
            productId: id,
            isBaseUnit: const Value(false),
            ratioToBase: const Value(10),
            unitTypeId: const Value(102),
          ));
    }
    if (stock != 0) {
      await db.adjustStock(productUnitId: '$id-base', newQty: stock);
    }
  }

  String orderText(WidgetTester tester) {
    final fields = find.byType(TextField).evaluate().toList();
    // Panel teks order = TextField multiline terakhir di layar.
    return (fields.last.widget as TextField).controller!.text;
  }

  testWidgets(
      'produk bersatuan TUNGGAL yang dicentang tetap dapat qty + satuan; '
      'teks order "1 Pcs Nama", BUKAN "- Nama" polos', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Warkop', stock: -86);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<String>), findsOneWidget,
        reason: 'produk 1 satuan pun harus dapat pemilih satuan (spt acuan)');
    expect(orderText(tester), 'Order Restock:\n1 Pcs Warkop',
        reason: 'qty awal 1 & satuan selalu ikut; stok -86 TIDAK boleh jadi '
            'angka order');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets('tombol + / − mengubah qty; minus MEMBEKU di 1 (spt acuan)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Warkop', stock: -86, checked: true);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    expect(orderText(tester), contains('1 Pcs Warkop'));

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();
    expect(orderText(tester), contains('3 Pcs Warkop'));

    await tester.tap(find.byIcon(Icons.remove_rounded).first);
    await tester.pumpAndSettle();
    expect(orderText(tester), contains('2 Pcs Warkop'));

    // Tekan minus berlebihan — harus berhenti di 1, tidak ke 0/negatif.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byIcon(Icons.remove_rounded).first);
      await tester.pumpAndSettle();
    }
    expect(orderText(tester), contains('1 Pcs Warkop'),
        reason: 'minus harus membeku di 1, tidak turun ke 0 atau desimal');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets('ketuk angka qty -> dialog; angka yang diketik masuk ke teks',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Warkop', stock: -86, checked: true);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();

    expect(find.text('Jumlah order'), findsOneWidget,
        reason: 'ketuk angka harus membuka dialog entri jumlah');
    await tester.enterText(
        find.ancestor(
          of: find.text('Jumlah order'),
          matching: find.byType(TextField),
        ),
        '12');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(orderText(tester), contains('12 Pcs Warkop'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'produk berjenjang: ganti satuan ke Dus -> teks ikut, qty TIDAK '
      'dikonversi (qty = jumlah order, bukan stok)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Indomie', stock: 25, tiered: true, checked: true);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    final dd = tester
        .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
    expect(dd.items!.map((e) => (e.child as Text).data).take(2).toList(),
        ['Pcs', 'Dus'],
        reason: 'satuan milik produk didahulukan (dasar dulu), baru umum');

    dd.onChanged!('Dus');
    await tester.pumpAndSettle();
    expect(orderText(tester), contains('1 Dus Indomie'),
        reason: 'ganti satuan tidak boleh mengubah angka order');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'dua arah: edit teks order -> centang, qty, & satuan di daftar ikut '
      'berubah; baris dihapus -> produknya ter-uncheck', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Indomie', stock: 25, tiered: true, checked: true);
    await addProduct(db, 'Warkop', stock: -86);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    final panel = find.byType(TextField).last;

    // Tulis ulang: Indomie jadi 7 Dus, Warkop ikut tercentang 3 Pcs.
    await tester.enterText(
        panel, 'Order Restock:\n7 Dus Indomie\n3 Pcs Warkop');
    // Parser di-debounce 600ms.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final indomie = await (db.select(db.products)
          ..where((t) => t.id.equals('p-Indomie')))
        .getSingle();
    final warkop = await (db.select(db.products)
          ..where((t) => t.id.equals('p-Warkop')))
        .getSingle();
    expect(indomie.markedOutOfStock, isTrue);
    expect(warkop.markedOutOfStock, isTrue,
        reason: 'produk yang barisnya DITAMBAHKAN user harus jadi tercentang');

    // Hapus baris Warkop -> harus ter-uncheck lagi.
    await tester.enterText(panel, 'Order Restock:\n7 Dus Indomie');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final warkop2 = await (db.select(db.products)
          ..where((t) => t.id.equals('p-Warkop')))
        .getSingle();
    expect(warkop2.markedOutOfStock, isFalse,
        reason: 'baris yang dihapus dari teks harus ikut membatalkan centang');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'teks tempelan format lama "- Nama" masih dimengerti (qty jadi 1)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await addProduct(db, 'Warkop', stock: -86);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    // Panel baru muncul kalau ada yang tercentang — centang dulu lalu tulis
    // ulang teksnya dgn format lama.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).last, 'Order Restock:\n- Warkop');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final warkop = await (db.select(db.products)
          ..where((t) => t.id.equals('p-Warkop')))
        .getSingle();
    expect(warkop.markedOutOfStock, isTrue,
        reason: 'format lama harus tetap dikenali, bukan malah meng-uncheck');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'produk yang SUDAH tercentang sebelum layar dibuka langsung dapat baris '
      'qty + satuan tanpa perlu ditekan dulu (regresi dari screenshot user)',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    // Ditandai habis di sesi SEBELUMNYA — dulu satuan cuma dimuat di _toggle
    // shg produk spt ini tampil tanpa satuan & teksnya "- Nama" polos.
    await addProduct(db, 'GajahBaru', stock: -74, tiered: true, checked: true);

    await pumpWithFakeApp(tester, db: db, child: const CekStokScreen());
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue,
        reason: 'prasyarat: tercentang dari DB, bukan hasil tap di test ini');
    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(orderText(tester), contains('1 Pcs GajahBaru'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
