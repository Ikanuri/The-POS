import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/kasir/widgets/quick_sync_dialog.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, String role) async {
  await tester.binding.setSurfaceSize(const Size(360, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      deviceProvider.overrideWith((ref) => DeviceNotifier()
        ..state = DeviceIdentity(
          storeUuid: 'u',
          storeKey: 'k',
          deviceName: 'Uji',
          deviceCode: 'K1',
          deviceRole: role,
        )),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: QuickSyncDialog(
          // Kamera palsu: satu tombol yang "memindai" QR host.
          scannerBuilder: (c, onRaw) => TextButton(
            key: const Key('fake-scan'),
            onPressed: () =>
                onRaw(jsonEncode({'ip': '192.168.1.5:8625', 'key': 'abc123'})),
            child: const Text('pindai'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  testWidgets('owner: Host terpilih; pindah ke Klien menampilkan pemindai',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _pump(tester, db, 'owner');
    expect(find.byKey(const Key('quick-sync-host')), findsOneWidget);
    expect(find.byKey(const Key('fake-scan')), findsNothing);
    await tester.tap(find.text('Klien'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake-scan')), findsOneWidget);
    expect(find.byKey(const Key('quick-sync-host')), findsNothing);
    await _drain(tester);
    await db.close();
  });

  testWidgets('kasir: pindai QR host mengisi IP & token', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await _pump(tester, db, 'kasir');
    expect(find.byKey(const Key('quick-sync-host')), findsNothing);
    await tester.tap(find.byKey(const Key('fake-scan')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-sync-scanned')), findsOneWidget);
    expect(find.textContaining('192.168.1.5'), findsWidgets);
    await _drain(tester);
    await db.close();
  });
}
