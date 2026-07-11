import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/csv_import_screen.dart';
import 'package:the_pos/features/pengaturan/order_share_screen.dart';
import 'package:the_pos/features/pengaturan/pengaturan_screen.dart';

import 'helpers/pump_app.dart';

/// Tier 2 (widget) — flag "Eksperimental" dipindah dari Katalog Pesanan
/// (HTML, sudah jadi fitur native) ke Import dari Griyo POS (fitur baru).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets(
      'Layar Pengaturan: "Import dari Griyo POS" ada di bawah Eksperimental, '
      '"Katalog Pesanan" TIDAK lagi ditandai eksperimental', (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const PengaturanScreen());

    expect(find.text('EKSPERIMENTAL'), findsOneWidget,
        reason: '_SectionHeader me-uppercase judulnya');
    expect(find.text('Import dari Griyo POS'), findsOneWidget);
    expect(find.text('Katalog Pesanan'), findsOneWidget);

    // "Katalog Pesanan" bukan yang berada tepat di bawah section
    // Eksperimental — cek dengan memastikan tile Katalog Pesanan tidak
    // pakai ikon science_outlined (badge eksperimental lama).
    final scienceIcons = find.byIcon(Icons.science_outlined);
    expect(scienceIcons, findsOneWidget, reason: 'cuma 1 fitur eksperimental sekarang');
  });

  testWidgets('CsvImportScreen griyoMode: tampil badge Eksperimental & judul',
      (tester) async {
    await pumpWithFakeApp(tester,
        db: db, child: const CsvImportScreen(griyoMode: true));

    expect(find.text('Import dari Griyo POS'), findsOneWidget);
    expect(find.text('Eksperimental'), findsOneWidget);
  });

  testWidgets(
      'CsvImportScreen generik (default): TANPA badge Eksperimental',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const CsvImportScreen());

    expect(find.text('Import Produk CSV'), findsOneWidget);
    expect(find.text('Eksperimental'), findsNothing);
  });

  testWidgets('OrderShareScreen (Katalog Pesanan HTML): TANPA badge Eksperimental',
      (tester) async {
    await pumpWithFakeApp(tester, db: db, child: const OrderShareScreen());

    expect(find.text('Eksperimental'), findsNothing);
  });
}
