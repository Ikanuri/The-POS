import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/cloudflare_publish_service.dart';
import 'package:the_pos/features/pengaturan/order_share_screen.dart';

import 'helpers/pump_app.dart';

/// Service palsu: kredensial selalu ada, publish langsung sukses.
class _FakeCloudflare extends CloudflarePublishService {
  @override
  Future<CloudflareCredentials?> loadCredentials() async =>
      const CloudflareCredentials(apiToken: 't', accountId: 'a');

  @override
  Future<CloudflarePublishResult> publish({
    required String html,
    required String storeName,
    required String storeUuid,
  }) async =>
      const CloudflarePublishResult(
          url: 'https://toko-abc.pages.dev', projectName: 'toko-abc');
}

void main() {
  testWidgets('tombol Salin menyalin URL hasil publish ke clipboard',
      (tester) async {
    // Clipboard.getData tidak di-mock otomatis (menggantung) — mock manual.
    String? clipboardStore;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardStore = (call.arguments as Map)['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return {'text': clipboardStore};
      }
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => db.close());
    await pumpWithFakeApp(tester,
        db: db,
        child: OrderShareScreen(cloudflare: _FakeCloudflare()),
        surfaceSize: const Size(360, 4200));
    await tester.pumpAndSettle();

    final copy = find.byKey(const ValueKey('copy-published-url'));
    expect(copy, findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('Publish ke Web'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(copy, findsOneWidget);

    await tester.tap(copy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clip?.text, 'https://toko-abc.pages.dev');
    expect(find.text('Link disalin'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
