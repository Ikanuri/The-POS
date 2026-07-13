import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/kasir/widgets/debt_payment_dialog.dart';

/// Item 10 — pelunasan hutang mencatat METODE BAYAR terpilih, bukan lagi
/// hardcode 'tunai'. Uji dialog reusable-nya langsung (widget test), sebab
/// itu satu-satunya sumber `method` untuk ke-3 call site.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
      'pilih metode non-tunai (BCA/bank) → dialog mengembalikan method '
      'metode itu, bukan tunai', (tester) async {
    // Seed metode kedua bertipe bank (Tunai sudah di-seed default oleh DB).
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-bca', type: 'bank', name: 'BCA', sortOrder: const Value(1)));

    ({int amount, String method})? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDebtPaymentDialog(context, db,
                  remaining: 50000, title: 'Lunasi Transaksi');
            },
            child: const Text('buka'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    // Chip metode tampil (Tunai default terpilih + BCA).
    expect(find.text('Tunai'), findsOneWidget);
    expect(find.text('BCA'), findsOneWidget);

    // Pilih BCA lalu Bayar.
    await tester.tap(find.text('BCA'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.method, 'bank'); // BUKAN 'tunai'
    expect(result!.amount, 50000); // prefill remaining
  });

  testWidgets(
      'hanya ada metode Tunai (default) → tanpa chip, method = tunai',
      (tester) async {
    ({int amount, String method})? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDebtPaymentDialog(context, db,
                  remaining: 20000, title: 'Tambah Bayar',
                  prefillRemaining: false);
            },
            child: const Text('buka'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    // Hanya 1 metode → tidak ada baris chip "Metode bayar".
    expect(find.text('Metode bayar'), findsNothing);

    // Isi nominal manual (tidak di-prefill) lalu Bayar.
    await tester.enterText(find.byType(TextField), '15000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.method, 'tunai');
    expect(result!.amount, 15000);
  });

  testWidgets(
      'tap chip "Uang Pas" saat field kosong (Tambah Bayar) → field terisi '
      'sisa tagihan persis', (tester) async {
    ({int amount, String method})? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showDebtPaymentDialog(context, db,
                  remaining: 84500, title: 'Tambah Bayar',
                  prefillRemaining: false);
            },
            child: const Text('buka'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    // Field kosong (prefillRemaining: false) sebelum chip ditap.
    expect(find.text('84.500'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Uang Pas'));
    await tester.pumpAndSettle();

    expect(find.text('84.500'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.amount, 84500);
  });

  testWidgets(
      'Item 11 — tombol Bayar TIDAK menyala saat field kosong, menyala '
      'begitu diisi', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDebtPaymentDialog(context, db,
                remaining: 20000, title: 'Tambah Bayar',
                prefillRemaining: false),
            child: const Text('buka'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    FilledButton bayarButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Bayar'));

    expect(bayarButton().onPressed, isNull,
        reason: 'field masih kosong, belum ada nominal');

    await tester.enterText(find.byType(TextField), '5000');
    await tester.pump();
    expect(bayarButton().onPressed, isNotNull,
        reason: 'sudah ada nominal > 0');

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(bayarButton().onPressed, isNull,
        reason: 'dikosongkan lagi -> mati lagi');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
