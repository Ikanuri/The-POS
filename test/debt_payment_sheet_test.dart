import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/theme/app_theme.dart';
import 'package:the_pos/core/utils/qris_dynamic.dart';
import 'package:the_pos/features/kasir/widgets/debt_payment_sheet.dart';

/// Sheet pelunasan hutang (menggantikan `debt_payment_dialog` lama):
/// kalkulator gaya checkout + pemilihan metode langsung di dalamnya +
/// QRIS statis/dinamis. Kontrak lamanya TETAP sama — mengembalikan
/// `(amount, method)` di mana `method` = `PaymentMethod.type`.
void main() {
  late AppDatabase db;

  // Payload QRIS statis GoPay ASLI (toko nyata), sama dgn fixture
  // `qris_dynamic_test.dart` — supaya QR yang dites benar-benar bisa
  // disisipi nominal, bukan payload karangan.
  const staticQris = '00020101021126610014COM.GO-JEK.WWW01189360091434648855360'
      '210G4648855360303UMI51440014ID.CO.QRIS.WWW0215ID102657224253903'
      '03UMI5204549953033605802ID5920Toko Berkah, BNY NYR6011PROBOLIN'
      'GGO61056727562070703A0163043165';

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSheet(
    WidgetTester tester, {
    required int remaining,
    bool prefillRemaining = true,
    void Function(({int amount, String method})? r)? onResult,
    // Surface default flutter_test (800x600) LEBIH PENDEK dari HP sungguhan,
    // sehingga QR + keypad tidak muat & keypad ter-render di luar viewport
    // (tap gagal "off-screen"). Pakai ukuran HP nyata supaya yang diuji
    // perilaku aslinya, bukan artefak ukuran surface test.
    Size surface = const Size(400, 900),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final r = await showDebtPaymentSheet(context, db,
                  remaining: remaining,
                  title: 'Bayar',
                  prefillRemaining: prefillRemaining);
              onResult?.call(r);
            },
            child: const Text('buka'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
  }

  // Tepat satu FilledButton di dalam sheet = tombol Bayar (pemicu "buka"
  // memakai ElevatedButton, chip memakai Choice/ActionChip).
  Finder payButton() => find.byType(FilledButton);

  testWidgets('pilih metode non-tunai (BCA/bank) → method = bank, bukan tunai',
      (tester) async {
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-bca', type: 'bank', name: 'BCA', sortOrder: const Value(1)));

    ({int amount, String method})? result;
    await pumpSheet(tester, remaining: 50000, onResult: (r) => result = r);

    expect(find.text('Tunai'), findsOneWidget);
    expect(find.text('BCA'), findsOneWidget);

    await tester.tap(find.text('BCA'));
    await tester.pumpAndSettle();
    await tester.tap(payButton());
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.method, 'bank');
    expect(result!.amount, 50000); // prefill sisa
  });

  testWidgets('hanya metode Tunai → method = tunai, nominal via keypad',
      (tester) async {
    ({int amount, String method})? result;
    await pumpSheet(tester,
        remaining: 20000, prefillRemaining: false, onResult: (r) => result = r);

    // Ketik 15000 lewat keypad (bukan TextField — kalkulator gaya checkout).
    await tester.tap(find.text('1'));
    await tester.tap(find.text('5'));
    await tester.tap(find.text('000'));
    await tester.pump();
    expect(find.text(formatRupiah(15000)), findsWidgets);

    await tester.tap(payButton());
    await tester.pumpAndSettle();

    expect(result!.method, 'tunai');
    expect(result!.amount, 15000);
  });

  testWidgets('tombol "Uang Pas" mengisi nominal = sisa tagihan persis',
      (tester) async {
    ({int amount, String method})? result;
    await pumpSheet(tester,
        remaining: 84500, prefillRemaining: false, onResult: (r) => result = r);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Uang Pas'));
    await tester.pumpAndSettle();
    expect(find.text(formatRupiah(84500)), findsWidgets);

    await tester.tap(payButton());
    await tester.pumpAndSettle();
    expect(result!.amount, 84500);
  });

  testWidgets('tombol Bayar mati saat nominal 0, hidup setelah keypad ditekan',
      (tester) async {
    await pumpSheet(tester, remaining: 20000, prefillRemaining: false);

    expect(tester.widget<FilledButton>(payButton()).onPressed, isNull,
        reason: 'belum ada nominal sama sekali');

    await tester.tap(find.text('5'));
    await tester.pump();
    expect(tester.widget<FilledButton>(payButton()).onPressed, isNotNull);
  });

  testWidgets(
      'HP sempit 360x800: tidak overflow & tombol tetap di dalam layar',
      (tester) async {
    // AppTheme menyetel minimumSize Outlined/FilledButton lebar penuh —
    // dua tombol dalam satu Row WAJIB override sempit. Surface default
    // flutter_test terlalu lebar utk menangkap kelas bug ini.
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-qris',
        type: 'qris',
        name: 'QRIS',
        qrValue: const Value(staticQris),
        sortOrder: const Value(1)));

    await pumpSheet(tester,
        remaining: 50000,
        prefillRemaining: false,
        surface: const Size(360, 800));
    expect(tester.takeException(), isNull);

    // Termasuk saat QRIS statis aktif (QR + keypad sekaligus) — kasus
    // paling padat, yang dulu jadi alasan pindah dari AlertDialog ke sheet.
    await tester.tap(find.text('QRIS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'QR statis + keypad tidak boleh bikin overflow');

    final screenW = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(tester.getRect(payButton()).right, lessThanOrEqualTo(screenW));
  });

  testWidgets(
      'jarak keypad -> baris tombol PERMANEN walau isi di atas keypad '
      'berubah (metode diganti)', (tester) async {
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-bca',
        type: 'bank',
        name: 'BCA',
        data: const Value('1234-5678-9012'),
        sortOrder: const Value(1)));
    await pumpSheet(tester, remaining: 50000, prefillRemaining: false);

    // Jarak diukur dari sisi bawah keypad ke sisi atas tombol Bayar.
    double gap() =>
        tester.getRect(payButton()).top - tester.getRect(find.text('000')).bottom;

    final before = gap();

    // Pilih BCA: chip lain collapse & metadata muncul -> isi DI ATAS keypad
    // berubah tinggi, tapi jarak keypad->tombol tidak boleh ikut berubah.
    await tester.tap(find.text('BCA'));
    await tester.pumpAndSettle();
    expect(find.text('1234-5678-9012'), findsOneWidget);

    expect(gap(), closeTo(before, 0.5),
        reason: 'tombol harus mengalir tepat di bawah keypad (jarak tetap), '
            'bukan dipatok ke dasar sheet');
  });

  testWidgets(
      'swipe turun BISA menutup sheet walau state QRIS statis overflow/'
      'scrollable (dulu macet — gesture arena dimenangkan scrollable)',
      (tester) async {
    await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
        id: 'pm-qris',
        type: 'qris',
        name: 'QRIS',
        qrValue: const Value(staticQris),
        sortOrder: const Value(1)));

    ({int amount, String method})? result;
    var resultCalled = false;
    await pumpSheet(tester,
        remaining: 50000,
        prefillRemaining: false,
        surface: const Size(360, 800),
        onResult: (r) {
          result = r;
          resultCalled = true;
        });

    // Masuk ke state QRIS statis (QR + keypad sekaligus) — inilah state
    // overflow yang dikeluhkan tidak bisa ditutup via swipe.
    await tester.tap(find.text('QRIS'));
    await tester.pumpAndSettle();

    final scrollable = find.byType(SingleChildScrollView).first;
    await tester.drag(scrollable, const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(resultCalled, isTrue,
        reason: 'sheet harus ter-pop oleh swipe turun');
    expect(result, isNull,
        reason: 'ditutup via swipe (batal), bukan lewat tombol Bayar');
    expect(find.byType(FilledButton), findsNothing);
  });

  group('chip metode: collapse & batal', () {
    setUp(() async {
      await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
          id: 'pm-bca',
          type: 'bank',
          name: 'BCA',
          data: const Value('1234-5678-9012'),
          sortOrder: const Value(1)));
      await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
          id: 'pm-ovo', type: 'ewallet', name: 'OVO', sortOrder: const Value(2)));
    });

    testWidgets(
        'pilih BCA → chip lain menghilang, metadata + tombol salin muncul '
        'segaris di kanannya', (tester) async {
      await pumpSheet(tester, remaining: 50000);
      expect(find.text('OVO'), findsOneWidget);

      await tester.tap(find.text('BCA'));
      await tester.pumpAndSettle();

      expect(find.text('BCA'), findsOneWidget);
      expect(find.text('OVO'), findsNothing, reason: 'chip lain collapse');
      expect(find.text('Tunai'), findsNothing);
      expect(find.text('1234-5678-9012'), findsOneWidget);
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    });

    testWidgets(
        'ketuk lagi chip yang terpilih → chip lain muncul kembali & metode '
        'balik ke tunai', (tester) async {
      ({int amount, String method})? result;
      await pumpSheet(tester, remaining: 50000, onResult: (r) => result = r);

      await tester.tap(find.text('BCA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BCA')); // batalkan
      await tester.pumpAndSettle();

      expect(find.text('OVO'), findsOneWidget);
      expect(find.text('Tunai'), findsOneWidget);

      await tester.tap(payButton());
      await tester.pumpAndSettle();
      expect(result!.method, 'tunai');
    });

    testWidgets('chip Tunai TIDAK meng-collapse (gerbang ke metode lain)',
        (tester) async {
      await pumpSheet(tester, remaining: 50000);
      await tester.tap(find.text('Tunai'));
      await tester.pumpAndSettle();
      expect(find.text('BCA'), findsOneWidget);
      expect(find.text('OVO'), findsOneWidget);
    });
  });

  group('QRIS statis ⇄ dinamis', () {
    setUp(() async {
      await db.into(db.paymentMethods).insert(PaymentMethodsCompanion.insert(
          id: 'pm-qris',
          type: 'qris',
          name: 'QRIS',
          qrValue: const Value(staticQris),
          sortOrder: const Value(1)));
    });

    testWidgets(
        'default QRIS = STATIS: keypad tetap ada & QR belum bawa nominal',
        (tester) async {
      await pumpSheet(tester, remaining: 50000, prefillRemaining: false);
      await tester.tap(find.text('QRIS'));
      await tester.pumpAndSettle();

      // Tombol menyebut TUJUAN: sedang statis -> tertulis "Nominal".
      expect(find.widgetWithText(OutlinedButton, 'Nominal'), findsOneWidget);
      expect(find.text('7'), findsOneWidget, reason: 'keypad masih tampil');
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets(
        'ketik nominal di statis lalu geser ke Nominal → keypad hilang, QR '
        'membawa nominal yang tadi diketik', (tester) async {
      ({int amount, String method})? result;
      await pumpSheet(tester,
          remaining: 50000,
          prefillRemaining: false,
          onResult: (r) => result = r);
      await tester.tap(find.text('QRIS'));
      await tester.pumpAndSettle();

      // Ketik 30.000 selagi masih statis.
      await tester.tap(find.text('3'));
      await tester.tap(find.text('0'));
      await tester.tap(find.text('000'));
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Nominal'));
      await tester.pumpAndSettle();

      // Sudah di mode nominal -> tombol kini menawarkan tujuan "Statis".
      expect(find.widgetWithText(OutlinedButton, 'Statis'), findsOneWidget);
      expect(find.text('7'), findsNothing, reason: 'keypad disembunyikan');

      await tester.tap(payButton());
      await tester.pumpAndSettle();
      expect(result!.method, 'qris');
      expect(result!.amount, 30000,
          reason: 'nominal yang diketik di mode statis harus terbawa');
    });

    testWidgets(
        'nominal TIDAK tereset saat toggle bolak-balik (salah pencet aman)',
        (tester) async {
      await pumpSheet(tester, remaining: 50000, prefillRemaining: false);
      await tester.tap(find.text('QRIS'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2'));
      await tester.tap(find.text('5'));
      await tester.tap(find.text('000'));
      await tester.pump();
      expect(find.text(formatRupiah(25000)), findsWidgets);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Nominal'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Statis'));
      await tester.pumpAndSettle();

      expect(find.text(formatRupiah(25000)), findsWidgets,
          reason: 'angka harus bertahan, tidak perlu ketik ulang');
      expect(find.text('7'), findsOneWidget, reason: 'keypad kembali');
    });

    testWidgets(
        'geser ke Nominal TANPA mengetik apa pun → QR & nota pakai sisa penuh',
        (tester) async {
      ({int amount, String method})? result;
      await pumpSheet(tester,
          remaining: 50000,
          prefillRemaining: false,
          onResult: (r) => result = r);
      await tester.tap(find.text('QRIS'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Nominal'));
      await tester.pumpAndSettle();

      await tester.tap(payButton());
      await tester.pumpAndSettle();
      expect(result!.amount, 50000,
          reason: 'fallback sisa penuh — QR bernominal 0 tidak sah');
    });

    testWidgets('setting qris_dynamic_enabled=0 → toggle tidak ditawarkan',
        (tester) async {
      await db.setSetting('qris_dynamic_enabled', '0');
      await pumpSheet(tester, remaining: 50000, prefillRemaining: false);
      await tester.tap(find.text('QRIS'));
      await tester.pumpAndSettle();

      expect(find.text('Statis'), findsNothing);
      expect(find.text('Nominal'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Uang Pas'), findsOneWidget);
    });
  });

  test('payload QR dinamis benar-benar membawa nominal yang diketik', () {
    // Pasangan level-1 dari widget test di atas: membuktikan angka yang
    // dibawa QR memang tertulis di tag 54, bukan cuma tampil di layar.
    final dyn = injectQrisAmount(staticQris, 30000);
    expect(verifyQrisCrc(dyn), isTrue);
    expect(Map.fromEntries(parseQrisTlv(dyn))['54'], '30000');
  });
}
