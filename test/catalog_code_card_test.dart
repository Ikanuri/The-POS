import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/catalog_access_service.dart';
import 'package:the_pos/features/pelanggan/pelanggan_form_screen.dart';

import 'helpers/pump_app.dart';

/// Kartu "Kode katalog" di form pelanggan (khusus owner): buat, buat ulang
/// (kode lama berganti), cabut — tersimpan lewat CatalogAccessService.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('buat -> buat ulang -> cabut kode pelanggan', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await db
        .into(db.customers)
        .insert(CustomersCompanion.insert(id: 'C1', name: 'Bu Sari'));
    await pumpWithFakeApp(tester,
        db: db,
        child: const PelangganFormScreen(customerId: 'C1'),
        surfaceSize: const Size(360, 1800));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('catalog-code-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-code-value')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('catalog-code-create')));
    await tester.pumpAndSettle();
    final first = tester
        .widget<SelectableText>(
            find.byKey(const ValueKey('catalog-code-value')))
        .data!;
    expect(first, matches(RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}$')));
    expect(await CatalogAccessService.codeFor(db, 'C1'), first);

    await tester.tap(find.byKey(const ValueKey('catalog-code-rotate')));
    await tester.pumpAndSettle();
    expect(find.text('Buat kode baru?'), findsOneWidget);
    await tester.tap(find.text('Buat baru'));
    await tester.pumpAndSettle();
    final second = tester
        .widget<SelectableText>(
            find.byKey(const ValueKey('catalog-code-value')))
        .data!;
    expect(second, isNot(first));
    expect(await CatalogAccessService.codeFor(db, 'C1'), second);

    await tester.tap(find.byKey(const ValueKey('catalog-code-revoke')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cabut').last);
    await tester.pumpAndSettle();
    expect(await CatalogAccessService.codeFor(db, 'C1'), isNull);
    expect(find.byKey(const ValueKey('catalog-code-create')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets('pelanggan baru (belum tersimpan): kartu kode tidak tampil',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpWithFakeApp(tester,
        db: db,
        child: const PelangganFormScreen(),
        surfaceSize: const Size(360, 1800));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-code-card')), findsNothing);
    await drain(tester);
  });
}
