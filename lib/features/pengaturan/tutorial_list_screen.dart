import 'package:flutter/material.dart';

/// Satu bab panduan — judul + isi singkat + (opsional) satu atau lebih
/// Pro Tips (fitur "tersembunyi"/kurang kentara, bukan cuma dokumentasi
/// dasar). [keywords] TIDAK ditampilkan — cuma memperluas jangkauan
/// pencarian (mis. sinonim/istilah lain yang mungkin diketik user).
class _TutorialChapter {
  const _TutorialChapter({
    required this.title,
    required this.body,
    this.proTips = const [],
    this.keywords = const [],
  });

  final String title;
  final String body;
  final List<String> proTips;
  final List<String> keywords;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        body.toLowerCase().contains(q) ||
        proTips.any((t) => t.toLowerCase().contains(q)) ||
        keywords.any((k) => k.toLowerCase().contains(q));
  }
}

const _chapters = <_TutorialChapter>[
  _TutorialChapter(
    title: 'Keranjang & Tempel Pesanan',
    body: 'Tap produk untuk menambah ke keranjang. Kalau ada pesanan dari '
        'pelanggan (lewat katalog online atau chat), tidak perlu diketik '
        'ulang satu-satu.',
    proTips: [
      'Tombol "Tempel Pesanan" (ikon di header keranjang) membaca teks '
          'pesanan dari clipboard dan langsung MENAMBAHKAN item yang '
          'cocok ke keranjang yang sedang aktif — termasuk saat mode '
          '"Tambah Belanjaan" sedang dipakai, bukan cuma mode kasir biasa.',
      'Scan QR "Transfer via QR" dari device lain juga otomatis '
          'MENGGABUNG ke keranjang yang sedang berisi item, tidak selalu '
          'membuat antrian terpisah — kalau keranjang device ini sedang '
          'kosong, baru masuk sebagai pesanan tertahan (held order).',
    ],
    keywords: ['paste order', 'clipboard', 'qr handoff', 'transfer'],
  ),
  _TutorialChapter(
    title: 'Laci Meja — Titip, Ketinggalan, Pinjaman, Pre-order',
    body: 'Menu Laci Meja mencatat 4 jenis kondisi barang yang tidak '
        'langsung dibawa pulang pelanggan: dititip di meja kasir, '
        'ketinggalan tak sengaja, dipinjam (biasanya wadah/galon kosong), '
        'atau pre-order (stok belum ada).',
    proTips: [
      'Qty Titip/Ketinggalan bisa SEBAGIAN dari qty di nota (mis. beli 5, '
          'yang ketinggalan cuma 2) — bukan harus semua atau tidak sama '
          'sekali.',
      'Struk in-app menampilkan tanda "Pinjaman"/"Pre-order" sebagai '
          'rujukan kebenaran kalau ada perselisihan barang apa yang '
          'sebenarnya dipinjam/dipesan — cek nota asli lewat menu ini.',
    ],
    keywords: ['titip', 'ketinggalan', 'pinjam', 'preorder', 'jaminan'],
  ),
  _TutorialChapter(
    title: 'Sinkronisasi antar HP (Sync WiFi)',
    body: 'Owner dan kasir/asisten bisa pakai HP terpisah dalam satu toko, '
        'saling sinkron otomatis lewat jaringan WiFi/hotspot lokal — '
        'tanpa perlu internet setelah pairing awal.',
    proTips: [
      'Perubahan yang dibuat kasir/asisten (harga, satuan produk, data '
          'pelanggan baru) TIDAK langsung berlaku — masuk dulu ke '
          'antrian "Usulan" yang harus ditinjau & disetujui owner di menu '
          'Sync WiFi, supaya owner tetap pegang kendali data toko.',
      'Layar tinjau usulan menampilkan SEMUA yang berubah secara rinci '
          '(satuan, isi kemasan, barcode, harga alternatif, dst.) — bukan '
          'cuma perubahan harga, supaya tidak ada perubahan yang '
          'terlewat/disangka glitch.',
    ],
    keywords: ['sinkron', 'wifi sync', 'usulan', 'proposal', 'multi device'],
  ),
  _TutorialChapter(
    title: 'Sinkron Harga Antar Toko',
    body: 'Kalau toko ini punya cabang/toko induk yang independen (bukan '
        'satu grup device yang sama), harga produk bisa dicocokkan lewat '
        'file katalog, bukan lewat Sync WiFi biasa.',
    proTips: [
      'Pencocokan produk antar toko memakai barcode PERSIS atau kode '
          'produk unik — bukan kemiripan nama (fuzzy matching sengaja '
          'dihapus, pernah salah-cocokkan produk beda varian/ukuran di '
          'data toko nyata).',
      'Begitu owner konfirmasi satu pasangan produk secara manual, '
          'barcode dari toko lain otomatis diingat sebagai alias — sync '
          'produk yang SAMA berikutnya tidak akan ditanyakan ulang lagi.',
    ],
    keywords: ['price sync', 'harga cabang', 'katalog', 'barcode'],
  ),
  _TutorialChapter(
    title: 'Izin Pegawai/Asisten',
    body: 'Owner bisa mengatur secara rinci apa saja yang boleh dilakukan '
        'tiap peran (Pegawai/Asisten) lewat Pengaturan → Izin Pegawai/Izin '
        'Asisten — mis. boleh override harga, input stok, jual meski stok '
        'minus, terima pembayaran, dll.',
    proTips: [
      'Toggle "Izinkan Stok Minus" bisa diaktifkan GLOBAL untuk semua '
          'produk sekaligus (Pengaturan → Toko) kalau memang sedang tidak '
          'sempat rapikan data stok — owner sendiri selalu bebas jual '
          'meski stok minus, terlepas dari toggle ini.',
    ],
    keywords: ['permission', 'kasir', 'pegawai', 'stok minus'],
  ),
  _TutorialChapter(
    title: 'Barcode & Label Cetak',
    body: 'Barcode produk bisa dipindai lewat kamera atau scanner eksternal '
        '(via keyboard). Barcode yang belum ada bisa digenerate otomatis '
        'saat menambah produk baru.',
    proTips: [
      'Banyak barcode toko nyata BUKAN format resmi EAN 12/13-digit '
          '(cuma angka asal tempel) — cetak label otomatis pakai format '
          'CODE128 sebagai fallback kalau barcode-nya bukan EAN-13 valid, '
          'jadi tetap bisa dicetak & dipindai dengan benar.',
    ],
    keywords: ['scan', 'barcode', 'label', 'cetak', 'ean'],
  ),
  _TutorialChapter(
    title: 'Jeda Pelacakan Stok',
    body: 'Kalau sedang tidak sempat merapikan data stok tapi kasir tetap '
        'perlu jualan tanpa peringatan/pengurangan stok, ada tombol jeda '
        'sementara di Pengaturan → Manajemen Data.',
    proTips: [
      '"Jeda Pelacakan Stok" menandai SEMUA produk yang masih dilacak '
          'jadi non-stok sementara dalam satu tap — produk yang memang '
          'sudah non-stok dari awal (mis. jasa) tidak ikut tersentuh, dan '
          'bisa dikembalikan kapan saja lewat toggle yang sama.',
    ],
    keywords: ['stok', 'pause', 'non-stok'],
  ),
  _TutorialChapter(
    title: 'Printer Bluetooth',
    body: 'Pilih printer thermal di Pengaturan → Printer Bluetooth. Setelah '
        'dipasangkan sekali, struk bisa langsung dicetak dari layar '
        'Pembayaran maupun Riwayat Nota.',
    proTips: [
      'Barcode produk otomatis dicetak pakai format CODE128 (bukan '
          'EAN-13) kalau kodenya bukan barcode resmi 13-digit — struk '
          'tetap bisa dipindai ulang dengan benar walau barcode asalnya '
          'cuma angka asal tempel dari toko.',
      'Isi struk bisa diatur detail lewat "Format Nota" (ukuran kertas '
          '58/80mm, tampil-tidaknya nomor transaksi/nama pelanggan/'
          'detail pembayaran/status lunas) — tidak harus ikut format '
          'bawaan kalau ada yang dirasa kurang perlu.',
    ],
    keywords: ['printer', 'bluetooth', 'cetak', 'struk', 'thermal'],
  ),
  _TutorialChapter(
    title: 'Backup & Restore, Alihkan Owner',
    body: 'Dua fitur beda tujuan yang sering tertukar. "Backup & Restore" '
        '(Pengaturan → Sinkronisasi) untuk menyalin SELURUH data toko ini '
        'ke file — dipakai kalau mau pindah HP atau sebagai cadangan rutin. '
        '"Alihkan Owner" untuk memindahkan IDENTITAS kepemilikan toko '
        '(bukan sekadar salinan data) ke device lain, mis. saat owner '
        'ganti HP permanen atau menyerahkan toko ke pemilik baru.',
    proTips: [
      '"Alihkan Owner" MENIMPA TOTAL data & identitas device penerima '
          '(boleh device baru atau device yang sudah aktif dipakai toko '
          'lain) — beda dari Backup & Restore biasa yang lebih ringan, '
          'makanya alurnya sengaja pakai peringatan + centang konfirmasi '
          'lebih ketat sebelum lanjut.',
    ],
    keywords: ['backup', 'restore', 'alih owner', 'pindah hp', 'berkahpos'],
  ),
  _TutorialChapter(
    title: 'Poin Loyalitas Pelanggan',
    body: 'Pelanggan terdaftar bisa otomatis dapat poin tiap transaksi '
        'lunas — atur aturannya di Pengaturan → Toko → Poin Loyalitas '
        '("setiap belanja Rp sekian, dapat sekian poin").',
    proTips: [
      'Kosongkan nominal ambang batas kalau mau menonaktifkan poin '
          'otomatis sama sekali — tidak perlu menghapus data pelanggan '
          'atau poin yang sudah terkumpul sebelumnya.',
      'Retur/pembatalan transaksi lunas otomatis mengurangi poin yang '
          'sudah didapat SECARA PROPORSIONAL terhadap nilai refund, bukan '
          'membiarkan poin "nyangkut" walau transaksinya sudah dibatalkan.',
    ],
    keywords: ['loyalitas', 'poin', 'membership', 'pelanggan setia'],
  ),
  _TutorialChapter(
    title: 'Retur & Edit Transaksi Lunas',
    body: 'Nota yang sudah lunas masih bisa diretur (sebagian/seluruh '
        'barang) atau diedit qty-nya langsung dari Riwayat Nota — tidak '
        'perlu buat transaksi pembatalan manual terpisah.',
    proTips: [
      'Menurunkan qty item di nota lunas otomatis menghitung refund '
          'tunai negatif & memperbarui item itu DI TEMPAT (bukan '
          'menambah baris retur terpisah) — riwayat nota tetap ringkas '
          'dibaca.',
      'Tidak bisa retur melebihi qty yang benar-benar pernah dibeli di '
          'nota itu (dicegah otomatis) — mencegah double-retur yang '
          'bikin stok/kas tercatat salah kalau tombol retur tak sengaja '
          'ditekan berulang.',
    ],
    keywords: ['retur', 'edit nota', 'refund', 'batalkan transaksi'],
  ),
  _TutorialChapter(
    title: 'Tutup Kasir vs Tutup Buku',
    body: '"Tutup Kasir" (Pengaturan → Manajemen Data) itu rekap kas '
        'HARIAN — bandingkan uang tunai sistem vs uang fisik di laci, '
        'biasanya dilakukan tiap akhir shift/hari. "Tutup Buku" itu '
        'mengarsipkan SELURUH transaksi tahun lalu supaya laporan tahun '
        'berjalan tetap ringan — jarang dipakai, biasanya sekali setahun.',
    proTips: [
      'Transaksi yang sudah diarsipkan lewat Tutup Buku masih bisa '
          'dilihat lagi lewat "Buka Arsip" — arsip bukan penghapusan '
          'permanen, cuma dipindahkan keluar dari laporan tahun aktif.',
    ],
    keywords: ['tutup kasir', 'tutup buku', 'arsip', 'rekap kas'],
  ),
  _TutorialChapter(
    title: 'Katalog Pesanan (pelanggan pesan sendiri)',
    body: 'Bagikan katalog produk berbentuk halaman HTML (Pengaturan → '
        'Katalog Pesanan) ke pelanggan lewat WhatsApp/link — pelanggan '
        'bisa pilih barang & kirim balik pesanannya sendiri tanpa perlu '
        'ditelepon atau dicatat manual dulu.',
    proTips: [
      'Pesanan yang pelanggan kirim balik dari katalog ini bisa langsung '
          'ditempel ke keranjang kasir lewat "Tempel Pesanan" (lihat bab '
          'Keranjang & Tempel Pesanan) — item yang namanya cocok otomatis '
          'terisi, tidak perlu ketik ulang.',
    ],
    keywords: ['katalog', 'pesan sendiri', 'link produk', 'whatsapp'],
  ),
];

class TutorialListScreen extends StatefulWidget {
  const TutorialListScreen({super.key});

  @override
  State<TutorialListScreen> createState() => _TutorialListScreenState();
}

class _TutorialListScreenState extends State<TutorialListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        _chapters.where((c) => c.matches(_query)).toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Panduan & Tips')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cari panduan (mis. "tempel pesanan", "izin")',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('Tidak ada panduan yang cocok'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ChapterCard(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard(this.chapter);

  final _TutorialChapter chapter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        // Bug visual dilaporkan user (screenshot): garis tipis nongol di
        // atas konten begitu card di-expand. `ExpansionTile` bawaan Flutter
        // menggambar border atas+bawah pakai warna divider tema SAAT
        // expanded — nempel aneh di dalam `Card` yang sudah punya
        // batas/elevation sendiri. `Border()` kosong menonaktifkannya.
        shape: const Border(),
        collapsedShape: const Border(),
        // Bug visual dilaporkan user (screenshot): garis tipis nongol di
        // atas konten begitu card di-expand. `ExpansionTile` bawaan Flutter
        // menggambar border atas+bawah pakai warna divider tema SAAT
        // expanded — nempel aneh di dalam `Card` yang sudah punya
        // batas/elevation sendiri. `Border()` kosong menonaktifkannya.
        title: Text(
          chapter.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(chapter.body, style: const TextStyle(fontSize: 13.5, height: 1.5)),
          for (final tip in chapter.proTips) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.primary.withOpacity(0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tip,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
