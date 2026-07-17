import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/order_share_screen.dart';

import 'helpers/pump_app.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Item 37 — tombol "Publish ke Web" di layar Katalog Pesanan: kalau
/// kredensial Cloudflare belum diisi, HARUS mengarahkan ke dialog
/// Pengaturan Cloudflare (bukan gagal diam-diam / crash).
void main() {
  Map<String, String> installFakeSecureStorage() {
    final store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return store[call.arguments['key']];
        case 'write':
          store[call.arguments['key']] = call.arguments['value'];
          return null;
        case 'delete':
          store.remove(call.arguments['key']);
          return null;
        default:
          return null;
      }
    });
    return store;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets(
      'tombol "Publish ke Web" ada, tap tanpa kredensial membuka dialog '
      'Pengaturan Cloudflare Pages', (tester) async {
    installFakeSecureStorage();
    final db = AppDatabase(NativeDatabase.memory());

    await pumpWithFakeApp(tester, db: db, child: const OrderShareScreen());

    expect(find.text('Publish ke Web'), findsOneWidget);
    await tester.tap(find.text('Publish ke Web'));
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan Cloudflare Pages'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Account ID'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'API Token'), findsOneWidget);

    await db.close();
  });

  testWidgets('ikon cloud di app bar juga membuka dialog Cloudflare yang sama',
      (tester) async {
    installFakeSecureStorage();
    final db = AppDatabase(NativeDatabase.memory());

    await pumpWithFakeApp(tester, db: db, child: const OrderShareScreen());

    await tester.tap(find.byIcon(Icons.cloud_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Pengaturan Cloudflare Pages'), findsOneWidget);

    await db.close();
  });
}
