import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/features/pengaturan/payment_methods_screen.dart';

import 'helpers/pump_app.dart';

/// Widget test — reorder metode pembayaran via drag-handle di
/// `PaymentMethodsScreen`. Membuktikan drag-handle benar-benar mengubah
/// URUTAN tampil (bukan cuma render tanpa efek), yang lalu tersimpan
/// sebagai `sortOrder` di DB.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  /// Unmount tree secara eksplisit lalu pump — memicu disposal
  /// StreamProvider (drift `markAsClosed` menjadwalkan timer 0ms saat
  /// cancel) SELAGI test masih jalan, lalu drain timer itu; kalau tidak,
  /// binding menemukan "Timer still pending" saat disposal di akhir test.
  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(milliseconds: 10));
  }

  testWidgets(
      'drag-handle memindahkan metode pembayaran ke posisi baru & tersimpan ke sortOrder',
      (tester) async {
    // Seed default sudah menyisipkan "Tunai" (sortOrder 0). Tambah 2 metode
    // lain dengan sortOrder awal 1 & 2 (urutan tampil: Tunai, BCA, OVO).
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-bca', type: 'bank', name: 'BCA', sortOrder: const Value(1)));
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-ovo',
        type: 'ewallet',
        name: 'OVO',
        sortOrder: const Value(2)));

    await pumpWithFakeApp(tester,
        db: db, child: const PaymentMethodsScreen());

    // Prakondisi: urutan awal Tunai, BCA, OVO (top-to-bottom).
    final namesBefore = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(namesBefore, ['Tunai', 'BCA', 'OVO']);

    final handles = find.byIcon(Icons.drag_handle);
    expect(handles, findsNWidgets(3),
        reason: 'tiap baris metode pembayaran harus punya drag-handle-nya '
            'sendiri (termasuk Tunai — bebas direorder spt lainnya)');

    // Drag handle baris pertama (Tunai) TURUN melewati baris ketiga (OVO).
    final gesture = await tester.startGesture(tester.getCenter(handles.first));
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 8; step++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // Setelah drag: "Tunai" sekarang tampil PALING BAWAH.
    final namesAfter = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(namesAfter, ['BCA', 'OVO', 'Tunai'],
        reason: 'drag-handle harus benar-benar menukar urutan tampil, bukan '
            'cuma me-render ulang tanpa efek');

    // Urutan baru tersimpan ke sortOrder di DB, terbaca lewat query lain
    // yang orderBy(sortOrder) juga.
    final rows = await (db.select(db.paymentMethods)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    expect(rows.map((m) => m.id).toList(), ['pm-bca', 'pm-ovo', 'pm-tunai']);

    await drain(tester);
  });
}
