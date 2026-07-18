import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laporan/tabs/stok_tab.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';

import 'helpers/pump_app.dart';

/// Permintaan user: kartu Ringkasan/Laporan/Pengaturan diberi aksen warna
/// soft sesuai fungsi (Varian B — latar kartu penuh ditint). Test ini utk
/// tab Stok (Laporan) & seksi Pengaturan (lihat test terpisah utk layar
/// Ringkasan utama: ringkasan_accent_color_test.dart).
void main() {
  const isDark = false;

  testWidgets(
      'tab Stok (Laporan): kartu nilai inventori pakai latar amber, kartu '
      'Stok Negatif pakai latar merah (kritis)', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    const unitId = 'p1-u';
    await db.into(db.products).insert(ProductsCompanion.insert(id: 'p1', name: 'Gula'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
        id: 'p1-t', productUnitId: unitId, minQty: const Value(1), price: 10000, costPrice: const Value(5000)));
    await db.adjustStock(productUnitId: unitId, newQty: -3);

    await pumpWithFakeApp(tester, db: db, child: const StokTab());

    final stokBg = AppTheme.stockWarnBg(isDark);
    final negBg = AppTheme.debtBg(isDark);
    final cards = tester.widgetList<Card>(find.byType(Card));
    expect(cards.where((c) => c.color == stokBg), isNotEmpty,
        reason: 'kartu nilai inventori/kategori harus pakai latar amber');
    expect(cards.where((c) => c.color == negBg), isNotEmpty,
        reason: 'kartu Stok Negatif harus pakai latar merah (kritis)');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });

  testWidgets(
      'Pengaturan: kartu seksi "Sinkronisasi" ungu, "Eksperimental" amber, '
      '"Manajemen Data" merah', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());

    final syncBg = AppTheme.riwayatBg(isDark);
    final expBg = AppTheme.stockWarnBg(isDark);
    final dataMgmtBg = AppTheme.debtBg(isDark);
    final cards = tester.widgetList<Card>(find.byType(Card));

    expect(cards.where((c) => c.color == syncBg), isNotEmpty,
        reason: 'kartu seksi Sinkronisasi harus pakai latar ungu');
    expect(cards.where((c) => c.color == expBg), isNotEmpty,
        reason: 'kartu seksi Eksperimental harus pakai latar amber');
    expect(cards.where((c) => c.color == dataMgmtBg), isNotEmpty,
        reason: 'kartu seksi Manajemen Data harus pakai latar merah');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    await db.close();
  });
}
