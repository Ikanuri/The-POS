import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Katalog HTML — halaman awal (landing), kategori, saran terlaris,
/// pengumuman, "Pesan lagi". Perilaku visual/animasi/performa diukur lewat
/// Playwright (lihat HANDOFF); test ini mengunci struktur inti di sumber
/// HTML tanpa detail rapuh.
void main() {
  late String html;
  setUpAll(() async {
    final db = AppDatabase(NativeDatabase.memory());
    html =
        (await OrderPageService.generateHtml(db: db, storeName: 'Toko Berkah'))
            .html;
    await db.close();
  });

  String fn(String signature, String until) {
    final a = html.indexOf(signature);
    expect(a, greaterThan(0), reason: 'fungsi $signature harus ada');
    return html.substring(a, html.indexOf(until, a));
  }

  group('landing & kategori', () {
    test('struktur: hero, kolom cari, chip kategori, satu scroller', () {
      expect(html, contains('Mau pesan apa hari ini?'));
      expect(html, contains('id="menuScroll"'));
      expect(html, contains('id="catsHero"'));
      expect(html, contains('id="catRow"'));
      expect(html, contains('data-view='));
      expect(html, contains("var CATS_ON = !!DATA.showCategories"));
      // Input pencarian satu-satunya & tidak dipindah (fokus aman).
      expect(RegExp(r'<input id="q"').allMatches(html).length, 1);
    });

    test('pencarian SELALU global: query menang atas kategori terpilih', () {
      final key = fn('function listKeyFor(q){', '// force=true');
      expect(key.indexOf("'q:'"), lessThan(key.indexOf("'c:'")));
      final state = fn('function computeState(){', 'function ghostOf');
      // Baris chip kategori hanya saat TIDAK ada query.
      expect(state, contains('CATS_ON && view === \'list\' && !q'));
    });

    test('daftar tidak dibangun saat landing; baris dibangun bertahap', () {
      expect(fn('function renderList(force){', '// "+" selalu menambah'),
          contains("if (curView === 'landing') { _stale = true; return; }"));
      expect(html, contains('function fillRows('));
      expect(html, contains('var _fillToken'));
    });

    test('label kategori di tiap baris hanya bila kategori ON', () {
      expect(html, contains("CATS_ON && p.category ?"));
      expect(html, contains('prow-cat'));
    });

    test('transisi hanya transform/opacity (FLIP), hormati reduced-motion',
        () {
      final anim = fn('function ghostOf(el, mode){', 'function syncTbId');
      // Semua keyframe yang dianimasikan: hanya transform & opacity.
      final frames = RegExp(r'\.animate\(\[(.*?)\],', dotAll: true)
          .allMatches(anim)
          .map((m) => m.group(1)!)
          .toList();
      expect(frames, isNotEmpty);
      for (final f in frames) {
        final props = RegExp(r'(\w+)\s*:')
            .allMatches(f)
            .map((m) => m.group(1)!)
            .where((p) => p != 'translateY')
            .toSet();
        expect(props.difference({'transform', 'opacity'}), isEmpty,
            reason: 'keyframe mengandung properti layout: $props');
      }
      expect(html, contains('prefers-reduced-motion: reduce'));
      expect(fn('function motionOk(){', 'function computeState'),
          contains('prefers-reduced-motion'));
    });

    test('Back HP dari mode daftar kembali ke landing (history terkendali)',
        () {
      expect(html, contains('function pushListState()'));
      expect(html, contains('_popIgnore'));
    });
  });

  group('saran terlaris', () {
    test('placeholder bergantian, berhenti saat fokus/terisi/tab hidden', () {
      final run = fn('function phCanRun(){', 'function phStep');
      expect(run, contains('document.hidden'));
      expect(run, contains('document.activeElement !== qEl'));
      expect(run, contains('!qEl.value'));
      expect(html, contains('Cari barang…'));
      expect(html, contains('id="goBtn"'));
    });
  });

  group('pengumuman', () {
    test('teks selalu textContent, bukan innerHTML', () {
      expect(html, contains("byId('annText').textContent = ANN;"));
      final init = fn('function initAnn(){', '\n}\n');
      expect(init.contains('innerHTML'), isFalse);
    });

    test('lama tampil = clamp(3000 + 60 ms x huruf, 3000, 12000)', () {
      expect(html,
          contains('Math.min(12000, Math.max(3000, 3000 + 60 * ANN.length))'));
    });

    test('sekali per halaman, menutup saat scroll / ketuk di luar', () {
      final init = fn('function initAnn(){', '\n}\n');
      expect(init, contains('annAutoShown'));
      expect(init, contains("'scroll'"));
      expect(init, contains("'pointerdown'"));
    });
  });

  group('Pesan lagi & tempel pesanan lama', () {
    test('riwayat di localStorage (kunci tanpa generatedAt), persist, try/catch',
        () {
      expect(html, contains("var HIST_KEY = 'posOrderHistory';"));
      expect(html.contains('HIST_KEY + DATA.generatedAt'), isFalse);
      expect(html, contains('navigator.storage.persist'));
      expect(fn('function loadHistory(){', 'function requestPersist'),
          contains('catch (e)'));
    });

    test('riwayat disimpan saat kirim (submitOrder), anti dobel-ketuk', () {
      expect(fn('function submitOrder(){', '// Blueprint §5'),
          contains('recordOrder()'));
      expect(html, contains('DUP_WINDOW_MS = 120000'));
    });

    test('parser tempel: toleran #PSN: / PSN:, galat ramah', () {
      expect(html, contains(r'/#?PSN:(\S+)/gi'));
      expect(html, contains('Kode pesanan tidak ditemukan di teks ini'));
      expect(html, contains('decodeURIComponent(raw)'));
    });

    test('item habis/tak ada dilewati, harga dari katalog terkini', () {
      final apply = fn('function applyOrderItems(items){', 'function reorderMessage');
      expect(apply, contains('p.outOfStock'));
      expect(apply.contains('price'), isFalse);
      expect(html, contains('tidak tersedia lagi'));
    });

    test('toggle OFF: tanpa simpan riwayat', () {
      expect(fn('function recordOrder(){', 'function p2'),
          contains('if (!DATA.reorder) return;'));
    });
  });
}
