import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics/perf_diag.dart';

/// Layar "Diagnostik Performa" (khusus build beta): mematikan satu per satu
/// hal yang diduga membuat layar Kasir gaya Baru berat. Pilihan tersimpan.
class PerfDiagScreen extends StatelessWidget {
  const PerfDiagScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostik Performa')),
      body: ValueListenableBuilder<PerfDiagState>(
        valueListenable: PerfDiag.notifier,
        builder: (context, s, _) {
          Widget tile(String key, String title, String sub, bool value,
              PerfDiagState Function(bool) apply) {
            return SwitchListTile(
              key: Key('diag-$key'),
              title: Text(title),
              subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
              value: value,
              onChanged: (v) => PerfDiag.set(apply(v)),
            );
          }

          Widget header(String t) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                child: Text(t,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: cs.primary)),
              );

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Cara pakai: matikan SATU saklar (posisi mati = fitur '
                  'dinonaktifkan), lalu ulangi gerakan yang terasa berat '
                  '(mis. ketuk kolom cari sampai keyboard terbuka) di layar '
                  'Kasir gaya Baru. Nyalakan "Meter frame" untuk melihat '
                  'angkanya. Bila satu saklar membuat jauh lebih lancar, '
                  'itulah biangnya.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),
              header('FITUR YANG BISA DIMATIKAN (nyala = normal)'),
              tile(
                  'stickers',
                  'Stiker animasi (Lottie)',
                  'Landing & produk tidak ditemukan',
                  s.stickers,
                  (v) => s.copyWith(stickers: v)),
              tile(
                  'shadows',
                  'Bayangan blur',
                  'Pil cari, cart bar, kartu produk, tombol header',
                  s.shadows,
                  (v) => s.copyWith(shadows: v)),
              tile('blobs', 'Blob warna latar', 'Dua gradien besar di belakang',
                  s.blobs, (v) => s.copyWith(blobs: v)),
              tile(
                  'pressScale',
                  'Animasi pantul tombol',
                  'Kartu, baris produk, chip kategori',
                  s.pressScale,
                  (v) => s.copyWith(pressScale: v)),
              tile(
                  'pageFade',
                  'Fade antar halaman',
                  'Memudarkan seluruh halaman saat pindah rute',
                  s.pageFade,
                  (v) => s.copyWith(pageFade: v)),
              tile(
                  'heroAnim',
                  'Animasi sapaan menciut',
                  'Kolom cari berpindah tengah <-> atas',
                  s.heroAnim,
                  (v) => s.copyWith(heroAnim: v)),
              tile(
                  'hintRotate',
                  'Saran bergilir di kolom cari',
                  'Hint "Cari <nama produk>" berganti tiap 3 detik',
                  s.hintRotate,
                  (v) => s.copyWith(hintRotate: v)),
              tile(
                  'tileDecor',
                  'Dekorasi kartu produk',
                  'Bayangan + potong sudut tiap baris',
                  s.tileDecor,
                  (v) => s.copyWith(tileDecor: v)),
              tile(
                  'recentQuery',
                  'Query "terakhir dijual"/saran pelanggan',
                  'Baca riwayat transaksi saat landing tampil',
                  s.recentQuery,
                  (v) => s.copyWith(recentQuery: v)),
              header('KEYBOARD'),
              tile(
                  'keyboardResize',
                  'Layar ikut mengecil saat keyboard muncul',
                  'MATIKAN untuk uji: body tidak dikecilkan (cart bar tidak '
                      'ikut naik, tanpa layout ulang per frame)',
                  s.keyboardResize,
                  (v) => s.copyWith(keyboardResize: v)),
              tile(
                  'hideCart',
                  'Sembunyikan cart bar selagi keyboard terbuka',
                  'NYALAKAN untuk uji (default mati)',
                  s.hideCartWhileTyping,
                  (v) => s.copyWith(hideCartWhileTyping: v)),
              header('PENGUKURAN'),
              tile(
                  'meter',
                  'Meter frame',
                  'Rata-rata/terburuk build & raster (ms) + % frame patah',
                  s.meter,
                  (v) => s.copyWith(meter: v)),
              tile(
                  'overlay',
                  'Overlay performa Flutter',
                  'Grafik build & raster di atas layar',
                  s.perfOverlay,
                  (v) => s.copyWith(perfOverlay: v)),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('diag-reset'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44)),
                        onPressed: () => PerfDiag.set(PerfDiagState.normal),
                        child: const Text('Kembalikan normal'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const Key('diag-copy'),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44)),
                        onPressed: () {
                          final t = s.summaryAll();
                          Clipboard.setData(ClipboardData(text: t));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(s.summary().isEmpty
                                  ? 'Semua normal — daftar lengkap disalin'
                                  : 'Disalin (tanda * = beda dari normal): $t')));
                        },
                        child: const Text('Salin pengaturan'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
