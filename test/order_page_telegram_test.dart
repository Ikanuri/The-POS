import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/order_page_service.dart';

/// Tombol kirim katalog HTML dipecah WhatsApp + Telegram (hanya bila kolom
/// Telegram di Informasi Toko diisi). Perilaku visual/klik diukur lewat
/// Playwright (lihat HANDOFF); test ini mengunci normalisasi tautan, isi DATA,
/// dan struktur sumber HTML.
void main() {
  group('normalizeTelegramUrl', () {
    const want = 'https://t.me/Barokah3?direct';
    test('semua bentuk masukan dengan ?direct => tautan t.me utuh', () {
      for (final raw in [
        '@Barokah3?direct',
        't.me/Barokah3?direct',
        'https://t.me/Barokah3?direct',
        'http://t.me/Barokah3?direct',
        'HTTPS://T.ME/Barokah3?direct',
        'telegram.me/Barokah3?direct',
        'https://www.t.me/Barokah3?direct',
        '  @Barokah3 ?direct  ',
        't.me/@Barokah3?direct',
        'https://t.me/Barokah3/?direct',
        'tg://resolve?domain=Barokah3',
      ]) {
        final got = OrderPageService.normalizeTelegramUrl(raw);
        expect(got, raw.startsWith('tg://') ? 'https://t.me/Barokah3' : want,
            reason: 'masukan "$raw"');
      }
    });

    test('tanpa query: query TIDAK ditambahkan', () {
      for (final raw in ['Barokah3', '@Barokah3', 't.me/Barokah3', ' https://t.me/Barokah3 ']) {
        expect(OrderPageService.normalizeTelegramUrl(raw),
            'https://t.me/Barokah3',
            reason: raw);
      }
    });

    test('tautan undangan & segmen tambahan', () {
      expect(OrderPageService.normalizeTelegramUrl('t.me/+AbCdEf12345'),
          'https://t.me/+AbCdEf12345');
      expect(
          OrderPageService.normalizeTelegramUrl('https://t.me/joinchat/AbCdEf12345'),
          'https://t.me/joinchat/AbCdEf12345');
      // Tautan pesan/kanal: hanya username yang dipakai.
      expect(OrderPageService.normalizeTelegramUrl('t.me/Barokah3/123'),
          'https://t.me/Barokah3');
      expect(OrderPageService.normalizeTelegramUrl('t.me/Barokah3#x'),
          'https://t.me/Barokah3');
    });

    test('tak valid / kosong => string kosong', () {
      for (final raw in [
        '',
        '   ',
        '@',
        't.me/',
        'abc', // < 5 karakter
        '@a_b',
        'a' * 33, // > 32 karakter
      ]) {
        expect(OrderPageService.normalizeTelegramUrl(raw), '',
            reason: 'masukan "$raw"');
      }
      for (final raw in [
        'https://instagram.com/Barokah3',
        'wa.me/62812345678',
        'barokah-3',
        'Barokah3!',
        't.me/+ab', // kode undangan terlalu pendek
        'javascript:alert(1)',
      ]) {
        expect(OrderPageService.normalizeTelegramUrl(raw), '',
            reason: 'masukan "$raw"');
      }
    });

    test('query berbahaya dibuang, username tetap', () {
      expect(OrderPageService.normalizeTelegramUrl('t.me/Barokah3?a="><script>'),
          'https://t.me/Barokah3');
    });
  });

  group('DATA & HTML', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<(String, Map<String, dynamic>)> gen(String tg) async {
      final html = (await OrderPageService.generateHtml(
              db: db, storeName: 'Toko Berkah', storeTelegram: tg))
          .html;
      final m = RegExp(r'^var DATA = (.+);$', multiLine: true).firstMatch(html)!;
      return (html, jsonDecode(m.group(1)!) as Map<String, dynamic>);
    }

    test('telegramUrl di DATA: dinormalisasi; kosong bila tak diisi/tak valid',
        () async {
      expect((await gen('@Barokah3?direct')).$2['telegramUrl'],
          'https://t.me/Barokah3?direct');
      expect((await gen('')).$2['telegramUrl'], '');
      expect((await gen('bukan tautan!')).$2['telegramUrl'], '');
    });

    test('dua tombol: WhatsApp + Telegram berlogo, aria-label, biru Telegram',
        () async {
      final html = (await gen('@Barokah3')).$1;
      expect(html, contains('id="mainBtnTg"'));
      expect(html, contains('aria-label="Kirim pesanan ke Telegram"'));
      expect(html, contains("'Kirim pesanan ke WhatsApp'"));
      expect(html, contains('background:#26A5E4'));
      expect(html, contains('#1d90c8')); // hover lebih gelap
      // Logo resmi simple-icons (CC0): path WhatsApp & Telegram.
      expect(html, contains('M17.472 14.382c-.297-.149'));
      expect(html, contains('M11.944 0A12 12 0 0 0 0 12'));
      // Elemen roll terpisah per tombol; total di kedua tombol.
      expect(html, contains('id="mbTotal"'));
      expect(html, contains('id="mbTotalTg"'));
      expect(html, contains("rollSet(document.getElementById('mbTotalTg')"));
    });

    test('fallback tanpa Telegram: tombol tunggal seperti sebelumnya', () async {
      final html = (await gen('')).$1;
      expect(html, contains("var HAS_TG = !!(DATA.telegramUrl"));
      expect(html, contains('<button class="mainbtn mainbtn-tg" id="mainBtnTg" type="button" hidden'));
      // Teks tunggal lama dipertahankan.
      expect(html, contains("if (!HAS_TG) { wa.textContent = 'Kirim via WhatsApp'; return; }"));
      // Mode dua-tombol hanya aktif dgn kelas has-tg (tidak ada tanpa Telegram).
      expect(html, contains("classList.add('has-tg')"));
      expect(html, contains('#app.order-mode.has-tg .mainbtn{'));
    });

    test('submitOrder(channel): Telegram salin + buka t.me, WA tetap; riwayat bersama',
        () async {
      final html = (await gen('@Barokah3')).$1;
      final a = html.indexOf('function submitOrder(channel){');
      expect(a, greaterThan(0));
      final body = html.substring(a, html.indexOf("document.getElementById('mainBtn').addEventListener", a));
      // Teks pesanan (dgn kode #PSN:) dibangun SEKALI dan dipakai kedua jalur.
      expect(RegExp(r'buildOrderText\(\)').allMatches(body).length, 1);
      expect(body, contains("window.open(DATA.telegramUrl, '_blank')"));
      expect(body, contains('Pesanan disalin — tempel di chat Telegram'));
      expect(RegExp(r'recordOrder\(\)').allMatches(body).length, 2);
      expect(body, contains("'https://wa.me/' + num + '?text='"));
      expect(html, contains("submitOrder('wa')"));
      expect(html, contains("submitOrder('tg')"));
    });
  });
}
