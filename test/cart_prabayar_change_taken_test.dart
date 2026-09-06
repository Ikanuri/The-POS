import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/features/kasir/cart_prabayar_provider.dart';

/// Fitur "kembalian sudah diambil" — akumulator `changeTakenTotal` di
/// `CartPrabayarNotifier` (murni provider, tanpa UI). Level "logic murni"
/// (CLAUDE.md §Metode Test poin 1), tapi lewat `testWidgets` (bukan `test`
/// polos) supaya `SharedPreferences.getInstance()` (async, dipakai
/// `_load`/`_persist`) sungguhan sempat resolve lewat `pump` — pola sama dgn
/// `kasir_prabayar_hold_resume_test.dart`.
void main() {
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  }

  /// Widget kosong sekadar supaya `ProviderContainer` "hidup" dalam pohon
  /// widget & microtask SharedPreferences sempat di-pump.
  Future<void> pumpNoop(WidgetTester tester, ProviderContainer container) =>
      tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const SizedBox(),
      ));

  testWidgets(
      'recordChangeTaken AKUMULATIF (bisa dipanggil berkali-kali) — '
      'poolAvailable ikut berkurang tiap panggilan', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpNoop(tester, container);

    final notifier = container.read(cartPrabayarProvider('c1').notifier);
    notifier.add(PrabayarEntry(
        id: 'e1', amount: 100000, method: 'tunai', lockedAt: DateTime.now()));
    await tester.pump();

    expect(notifier.poolAvailable, 100000);

    // Kembalian Rp40rb muncul & diambil.
    notifier.recordChangeTaken(40000);
    await tester.pump();
    expect(notifier.changeTakenTotal, 40000);
    expect(notifier.poolAvailable, 60000);

    // Cart dikurangi lagi → kembalian baru Rp15rb muncul & diambil lagi.
    notifier.recordChangeTaken(15000);
    await tester.pump();
    expect(notifier.changeTakenTotal, 55000,
        reason: 'akumulasi kedua panggilan, BUKAN nilai terakhir menimpa');
    expect(notifier.poolAvailable, 45000);

    await drain(tester);
  });

  testWidgets('recordChangeTaken(0) atau negatif diabaikan (no-op)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpNoop(tester, container);

    final notifier = container.read(cartPrabayarProvider('c1').notifier);
    notifier.add(PrabayarEntry(
        id: 'e1', amount: 50000, method: 'tunai', lockedAt: DateTime.now()));
    await tester.pump();

    notifier.recordChangeTaken(0);
    notifier.recordChangeTaken(-100);
    await tester.pump();
    expect(notifier.changeTakenTotal, 0);

    await drain(tester);
  });

  testWidgets('clear() reset changeTakenTotal balik ke 0', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpNoop(tester, container);

    final notifier = container.read(cartPrabayarProvider('c1').notifier);
    notifier.add(PrabayarEntry(
        id: 'e1', amount: 30000, method: 'tunai', lockedAt: DateTime.now()));
    notifier.recordChangeTaken(10000);
    await tester.pump();
    expect(notifier.changeTakenTotal, 10000);

    notifier.clear();
    await tester.pump();
    expect(notifier.changeTakenTotal, 0);
    expect(notifier.poolAvailable, 0);

    await drain(tester);
  });

  testWidgets(
      'persist ke SharedPreferences & reload: changeTakenTotal ikut '
      'tersimpan/terpulihkan (bukan cuma daftar entri)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container1 = ProviderContainer();
    addTearDown(container1.dispose);
    await pumpNoop(tester, container1);

    final notifier1 = container1.read(cartPrabayarProvider('cX').notifier);
    // `_load()` sendiri async (nunggu `SharedPreferences.getInstance()`) —
    // beri waktu SELESAI dulu sebelum mutasi, kalau tidak `_loaded` masih
    // false saat `add`/`recordChangeTaken` dipanggil & `_persist()` (yang
    // butuh `_loaded == true`) ke-skip utk mutasi itu.
    await tester.pump();
    notifier1.add(PrabayarEntry(
        id: 'e1', amount: 80000, method: 'tunai', lockedAt: DateTime.now()));
    notifier1.recordChangeTaken(25000);
    // Beri waktu utk `_persist()` (async, `SharedPreferences.getInstance()
    // .then(...)`) benar2 menulis sebelum container dibuang.
    await tester.pump();
    await tester.pump();

    // Container BARU (simulasi restart app) — muat ulang dari
    // SharedPreferences yg SAMA (mock tetap sama instance selama test ini).
    // Baca notifier (memicu `CartPrabayarNotifier` dibuat & `_load()` mulai)
    // SEBELUM pump — supaya pump berikutnya benar2 menunggu `_load()` itu.
    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    final notifier2 = container2.read(cartPrabayarProvider('cX').notifier);
    await pumpNoop(tester, container2);
    await tester.pump();

    expect(notifier2.changeTakenTotal, 25000);
    expect(container2.read(cartPrabayarProvider('cX')), hasLength(1));
    expect(container2.read(cartPrabayarProvider('cX')).single.amount, 80000);
    expect(notifier2.poolAvailable, 55000);

    await drain(tester);
  });

  testWidgets(
      'format lama tersimpan (bare list, TANPA changeTakenTotal) tetap bisa '
      'dimuat — fallback changeTakenTotal=0 (kompatibel mundur)',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartprabayar_v1_cOld':
          '[{"id":"e1","amount":20000,"method":"tunai","methodName":null,'
              '"lockedAt":${DateTime(2026, 1, 1).millisecondsSinceEpoch}}]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(cartPrabayarProvider('cOld').notifier);
    await pumpNoop(tester, container);
    await tester.pump();

    expect(notifier.changeTakenTotal, 0);
    expect(container.read(cartPrabayarProvider('cOld')), hasLength(1));
    expect(notifier.poolAvailable, 20000);

    await drain(tester);
  });

  // --- Riwayat "kembalian sudah diambil" (ChangeTakenEntry) -------------

  testWidgets(
      'tambah 2+ entri riwayat lalu hapus salah satu (removeChangeTaken) → '
      'changeTakenTotal/poolAvailable recompute dari SISA list (bukan '
      'nilai terakhir/pertama saja)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpNoop(tester, container);

    final notifier = container.read(cartPrabayarProvider('c2').notifier);
    notifier.add(PrabayarEntry(
        id: 'e1', amount: 100000, method: 'tunai', lockedAt: DateTime.now()));
    await tester.pump();

    notifier.recordChangeTaken(40000);
    await tester.pump();
    notifier.recordChangeTaken(15000);
    await tester.pump();

    expect(notifier.changeTakenEntries, hasLength(2));
    expect(notifier.changeTakenTotal, 55000);
    expect(notifier.poolAvailable, 45000);

    // Hapus entri PERTAMA (40000) — entri kedua (15000) HARUS tetap ada &
    // ikut dihitung, bukan seluruh riwayat ikut hilang.
    final firstId = notifier.changeTakenEntries.first.id;
    notifier.removeChangeTaken(firstId);
    await tester.pump();

    expect(notifier.changeTakenEntries, hasLength(1));
    expect(notifier.changeTakenEntries.single.amount, 15000);
    expect(notifier.changeTakenTotal, 15000);
    expect(notifier.poolAvailable, 85000,
        reason: 'pool balik naik — undo entri 40000 mengembalikan porsi itu '
            'ke kredit tersedia');

    await drain(tester);
  });

  testWidgets(
      'removeChangeTaken dgn id yg tidak ada di list = no-op (tidak error, '
      'tidak mengubah total)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await pumpNoop(tester, container);

    final notifier = container.read(cartPrabayarProvider('c3').notifier);
    notifier.add(PrabayarEntry(
        id: 'e1', amount: 50000, method: 'tunai', lockedAt: DateTime.now()));
    notifier.recordChangeTaken(20000);
    await tester.pump();

    notifier.removeChangeTaken('id-tidak-ada');
    await tester.pump();
    expect(notifier.changeTakenTotal, 20000);

    await drain(tester);
  });

  testWidgets(
      'format transisi lama (Map dgn `entries` + int `changeTakenTotal`, '
      'SEBELUM jadi riwayat) tetap dimuat sbg SATU entri sintetis — tidak '
      'hilang saat resume', (tester) async {
    SharedPreferences.setMockInitialValues({
      'cartprabayar_v1_cLegacy': jsonEncode({
        'entries': [
          {
            'id': 'e1',
            'amount': 80000,
            'method': 'tunai',
            'methodName': null,
            'lockedAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
          }
        ],
        'changeTakenTotal': 25000,
      }),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(cartPrabayarProvider('cLegacy').notifier);
    await pumpNoop(tester, container);
    await tester.pump();

    expect(notifier.changeTakenEntries, hasLength(1),
        reason: 'nilai lama (int) dibaca sbg SATU entri sintetis, tidak '
            'hilang');
    expect(notifier.changeTakenEntries.single.amount, 25000);
    expect(notifier.changeTakenTotal, 25000);
    expect(notifier.poolAvailable, 55000);

    await drain(tester);
  });

  testWidgets(
      'persist format BARU (changeTakenEntries list) & reload — seluruh '
      'riwayat (bukan cuma total) tersimpan/terpulihkan', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container1 = ProviderContainer();
    addTearDown(container1.dispose);
    await pumpNoop(tester, container1);

    final notifier1 = container1.read(cartPrabayarProvider('cY').notifier);
    await tester.pump();
    notifier1.add(PrabayarEntry(
        id: 'e1', amount: 90000, method: 'tunai', lockedAt: DateTime.now()));
    notifier1.recordChangeTaken(30000);
    notifier1.recordChangeTaken(10000);
    await tester.pump();
    await tester.pump();

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    final notifier2 = container2.read(cartPrabayarProvider('cY').notifier);
    await pumpNoop(tester, container2);
    await tester.pump();

    expect(notifier2.changeTakenEntries, hasLength(2));
    expect(notifier2.changeTakenTotal, 40000);
    expect(notifier2.poolAvailable, 50000);

    await drain(tester);
  });
}
