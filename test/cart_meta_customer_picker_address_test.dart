import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/features/kasir/widgets/cart_meta_pickers.dart';

/// Permintaan user: alamat pelanggan di dropdown pelanggan di CART BAR
/// (sheet ringan `showCustomerPickerSheet`, dipanggil dari `_CartMetaTab` di
/// kasir_screen.dart) masih belum tampil — beda dari dropdown di modal
/// checkout/struk yang sudah diperbaiki sebelumnya (file berbeda).
void main() {
  testWidgets(
      'showCustomerPickerSheet menampilkan alamat di bawah nama — mencegah '
      'salah pilih nama kembar', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c1',
          name: 'Budi',
          address: const Value('Jl. Mawar No. 1'),
        ));
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c2',
          name: 'Budi',
          address: const Value('Jl. Melati No. 9'),
        ));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          return Scaffold(
            body: Builder(builder: (context) {
              return ElevatedButton(
                onPressed: () => showCustomerPickerSheet(context, ref),
                child: const Text('Buka'),
              );
            }),
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Budi');
    await tester.pumpAndSettle();

    expect(find.text('Jl. Mawar No. 1'), findsOneWidget);
    expect(find.text('Jl. Melati No. 9'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
