import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/features/laci_meja/laci_meja_dashboard_screen.dart';

/// Susulan dashboard Laci Meja tab Pre-order (permintaan user) — tombol
/// "Salin Laporan" (ikon di sebelah tombol Kuota). Widget test ini HANYA
/// memverifikasi tombol memanggil `Clipboard.setData` dgn isi yang
/// mengandung penanda kunci laporan + menampilkan SnackBar konfirmasi —
/// isi lengkap teksnya (semua kasus format) sudah ditest terpisah di
/// `preorder_report_test.dart` terhadap fungsi murninya.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget buildApp() {
    final router = GoRouter(
      initialLocation: '/laci-meja',
      routes: [
        GoRoute(
          path: '/laci-meja',
          builder: (_, __) => const LaciMejaDashboardScreen(),
        ),
        GoRoute(
          path: '/kasir/laci-meja/riwayat',
          builder: (_, __) => const Scaffold(body: Text('Riwayat')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Future<void> seed() async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'P1', name: 'Gas LPG 3kg'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'U1', productId: 'P1', isBaseUnit: const Value(true)));
    await db.addPreorderEntry(
      id: 'po1',
      productId: 'P1',
      productUnitId: 'U1',
      customerName: 'Umum',
      qtyOrdered: 3,
    );
  }

  testWidgets(
      'tap ikon "Salin Laporan" -> Clipboard.setData terpanggil dgn judul '
      'laporan + SnackBar konfirmasi muncul', (tester) async {
    // Clipboard.getData/setData TIDAK di-mock otomatis oleh flutter_test di
    // environment ini (lihat gotcha CLAUDE.md) — pasang handler manual biar
    // tidak hang selamanya.
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

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await seed();

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pre-order'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Salin Laporan'));
    // Sengaja `pump()` biasa (bukan `pumpAndSettle`) — SnackBar punya timer
    // auto-dismiss yang tidak pernah "settle" di clock sintetis widget test.
    await tester.pump();

    expect(clipboardStore, isNotNull);
    expect(clipboardStore, contains('LAPORAN PRE-ORDER — Gas LPG 3kg'));
    expect(clipboardStore, contains('Pesan 3 Gas LPG 3kg - Sisa 3'));
    expect(clipboardStore, contains('**Total jaminan: 0**'));
    expect(find.text('Laporan pre-order disalin'), findsOneWidget);

    // Drain (gotcha CLAUDE.md): layar ini punya beberapa drift
    // `StreamProvider` (mis. `preorderEntriesProvider`) — wajib drain di
    // akhir supaya tidak hang "Timer is still pending" saat disposal.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
