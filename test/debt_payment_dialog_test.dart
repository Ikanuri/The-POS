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
    await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.method, 'tunai');
    expect(result!.amount, 15000);
  });
}
